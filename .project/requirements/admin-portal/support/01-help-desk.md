# Feature: Help Desk & Ticket Management

## Description
Internal ticket management system that allows staff to create, track, prioritize, and resolve customer support tickets with full lifecycle management.

## User Stories
- As a staff member, I can create support tickets for customer issues
- As a staff member, I can assign tickets to team members and set priorities
- As a staff member, I can track ticket status and add internal notes
- As a staff member, I can view ticket history and resolution details
- As a manager, I can monitor team performance and ticket metrics

## Acceptance Criteria
- Tickets can be created with title, description, priority, and category
- Staff can assign tickets to specific team members
- Ticket status tracking (Open, In Progress, Pending, Resolved, Closed)
- Internal notes and comments on tickets
- Time tracking for resolution metrics
- Email notifications for ticket updates
- Search and filter tickets by various criteria

## Tasks

### Task 1: Create Support Ticket Models and Database Schema
**Description:** Design and implement the core data models and database schema for the ticketing system.

**Implementation Notes:**
- Create models for tickets, messages, and related entities
- Implement appropriate validations and relationships
- Add support for file attachments

```ruby
# app/models/support_ticket.rb
class SupportTicket < ApplicationRecord
  belongs_to :business
  belongs_to :created_by, class_name: 'User'
  belongs_to :assigned_to, class_name: 'User', optional: true
  has_many :support_messages, dependent: :destroy
  has_many_attached :attachments
  
  validates :subject, :description, :priority, :category, presence: true
  
  enum status: { 
    open: 0, 
    in_progress: 1, 
    waiting_for_customer: 2, 
    resolved: 3, 
    closed: 4 
  }
  
  enum priority: { 
    low: 0, 
    normal: 1, 
    high: 2, 
    urgent: 3 
  }
  
  enum category: {
    technical: 0,
    billing: 1,
    feature_request: 2,
    bug_report: 3,
    general: 4,
    integration: 5
  }
  
  scope :open_tickets, -> { where(status: [:open, :in_progress, :waiting_for_customer]) }
  scope :by_priority, ->(priority) { where(priority: priority) }
  scope :recent, -> { where(created_at: 30.days.ago..) }
  
  def response_time
    first_response = support_messages.where.not(created_by: created_by).first
    return nil unless first_response
    
    first_response.created_at - created_at
  end
  
  def time_to_resolution
    return nil unless resolved? || closed?
    
    resolution_time = if resolved?
                        support_messages.where("content LIKE '%resolved%'").order(created_at: :asc).first&.created_at || updated_at
                      else
                        updated_at
                      end
    
    resolution_time - created_at
  end
  
  def customer_wait_time
    return 0 if support_messages.empty?
    
    # Calculate total time waiting for support responses
    wait_periods = []
    last_customer_message = nil
    
    support_messages.order(created_at: :asc).each do |message|
      if message.customer?
        last_customer_message = message.created_at
      elsif message.agent? && last_customer_message
        wait_periods << (message.created_at - last_customer_message)
        last_customer_message = nil
      end
    end
    
    # If there's an outstanding customer message with no response
    if last_customer_message
      wait_periods << (Time.current - last_customer_message)
    end
    
    wait_periods.sum
  end
end
```

```ruby
# app/models/support_message.rb
class SupportMessage < ApplicationRecord
  belongs_to :support_ticket
  belongs_to :created_by, class_name: 'User'
  has_many_attached :attachments
  
  validates :content, presence: true
  validates :message_type, presence: true
  
  enum message_type: { customer: 0, agent: 1, system: 2 }
  
  scope :customer_messages, -> { where(message_type: 'customer') }
  scope :agent_messages, -> { where(message_type: 'agent') }
  
  after_create :update_ticket_status
  
  def sender_name
    created_by.name
  end
  
  private
  
  def update_ticket_status
    ticket = support_ticket
    
    # When agent responds, update status to waiting for customer
    if agent? && ticket.open? || ticket.in_progress?
      ticket.update(status: :waiting_for_customer)
    end
    
    # When customer responds to a waiting ticket, set back to in progress
    if customer? && ticket.waiting_for_customer?
      ticket.update(status: :in_progress)
    end
  end
end
```

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_support_tickets.rb
class CreateSupportTickets < ActiveRecord::Migration[8.0]
  def change
    create_table :support_tickets do |t|
      t.string :subject, null: false
      t.text :description, null: false
      t.integer :status, default: 0, null: false
      t.integer :priority, default: 1, null: false
      t.integer :category, default: 4, null: false
      t.references :business, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.references :assigned_to, null: true, foreign_key: { to_table: :users }
      t.datetime :resolved_at
      t.datetime :closed_at
      t.string :reference_number
      
      t.timestamps
    end
    
    add_index :support_tickets, :status
    add_index :support_tickets, :priority
    add_index :support_tickets, :reference_number, unique: true
  end
end
```

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_support_messages.rb
class CreateSupportMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :support_messages do |t|
      t.text :content, null: false
      t.integer :message_type, default: 0, null: false
      t.references :support_ticket, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.boolean :internal_note, default: false
      
      t.timestamps
    end
    
    add_index :support_messages, [:support_ticket_id, :created_at]
    add_index :support_messages, :message_type
  end
end
```

### Task 2: Build Ticket Management Interface
**Description:** Create a user-friendly interface for staff to manage support tickets.

**Implementation Notes:**
- Design ticket submission form with category, priority, and description fields
- Implement file upload functionality for attachments
- Add ticket preview and submission confirmation
- Create ticket listing page with filtering and sorting options
- Implement detailed ticket view with conversation thread
- Add ticket management actions (close, reopen, escalate)

```ruby
# app/controllers/admin/support_tickets_controller.rb
class Admin::SupportTicketsController < Admin::BaseController
  before_action :set_ticket, only: [:show, :edit, :update, :close, :reopen]
  
  def index
    @tickets = current_business.support_tickets
      .includes(:created_by, :assigned_to)
      .order(created_at: :desc)
    
    if params[:status].present?
      @tickets = @tickets.where(status: params[:status])
    end
    
    if params[:category].present?
      @tickets = @tickets.where(category: params[:category])
    end
    
    if params[:priority].present?
      @tickets = @tickets.where(priority: params[:priority])
    end
    
    @tickets = @tickets.paginate(page: params[:page], per_page: 10)
  end
  
  def show
    @messages = @ticket.support_messages
      .includes(:created_by, :attachments)
      .order(created_at: :asc)
      
    @message = @ticket.support_messages.new
  end
  
  def new
    @ticket = current_business.support_tickets.new
  end
  
  def create
    @ticket = current_business.support_tickets.new(ticket_params)
    @ticket.created_by = current_user
    @ticket.status = :open
    @ticket.reference_number = generate_reference_number
    
    if @ticket.save
      # Create the initial message from the ticket description
      @ticket.support_messages.create!(
        content: @ticket.description,
        message_type: :customer,
        created_by: current_user
      )
      
      # Handle attachments if any
      if params[:ticket_attachments].present?
        params[:ticket_attachments].each do |attachment|
          @ticket.attachments.attach(attachment)
        end
      end
      
      # Notify support team about new ticket
      SupportMailer.new_ticket_notification(@ticket).deliver_later
      
      redirect_to admin_support_ticket_path(@ticket), notice: "Support ticket ##{@ticket.reference_number} was successfully created."
    else
      render :new
    end
  end
  
  def close
    if @ticket.update(status: :closed, closed_at: Time.current)
      @ticket.support_messages.create!(
        content: "Ticket closed by #{current_user.name}",
        message_type: :system,
        created_by: current_user
      )
      
      redirect_to admin_support_ticket_path(@ticket), notice: "Ticket ##{@ticket.reference_number} was closed successfully."
    else
      redirect_to admin_support_ticket_path(@ticket), alert: "Unable to close the ticket."
    end
  end
  
  def reopen
    if @ticket.closed? && @ticket.update(status: :open)
      @ticket.support_messages.create!(
        content: "Ticket reopened by #{current_user.name}",
        message_type: :system,
        created_by: current_user
      )
      
      redirect_to admin_support_ticket_path(@ticket), notice: "Ticket ##{@ticket.reference_number} was reopened successfully."
    else
      redirect_to admin_support_ticket_path(@ticket), alert: "Unable to reopen the ticket."
    end
  end
  
  private
  
  def set_ticket
    @ticket = current_business.support_tickets.find(params[:id])
  end
  
  def ticket_params
    params.require(:support_ticket).permit(
      :subject, 
      :description, 
      :priority, 
      :category
    )
  end
  
  def generate_reference_number
    loop do
      reference = "TICKET-#{SecureRandom.alphanumeric(8).upcase}"
      break reference unless SupportTicket.exists?(reference_number: reference)
    end
  end
end
```

```ruby
# app/controllers/admin/support_messages_controller.rb
class Admin::SupportMessagesController < Admin::BaseController
  before_action :set_ticket
  
  def create
    @message = @ticket.support_messages.new(message_params)
    @message.created_by = current_user
    @message.message_type = :customer
    
    if @message.save
      # Handle attachments
      if params[:message_attachments].present?
        params[:message_attachments].each do |attachment|
          @message.attachments.attach(attachment)
        end
      end
      
      # Notify support team
      SupportMailer.new_message_notification(@message).deliver_later
      
      redirect_to admin_support_ticket_path(@ticket), notice: "Your message was sent."
    else
      @messages = @ticket.support_messages.includes(:created_by).order(created_at: :asc)
      render "admin/support_tickets/show"
    end
  end
  
  private
  
  def set_ticket
    @ticket = current_business.support_tickets.find(params[:support_ticket_id])
  end
  
  def message_params
    params.require(:support_message).permit(:content, :internal_note)
  end
end
```

### Task 3: Implement Ticket Assignment and Workflow
**Description:** Enable assignment of tickets to specific team members and define workflow states.

**Implementation Notes:**
- Implement ticket assignment logic in the controller
- Add workflow state machine to the SupportTicket model
- Create views for ticket assignment and status updates
- Implement notifications for ticket assignments

```ruby
# app/models/support_ticket.rb
class SupportTicket < ApplicationRecord
  # ... existing code ...
  
  enum status: { 
    open: 0, 
    in_progress: 1, 
    waiting_for_customer: 2, 
    resolved: 3, 
    closed: 4 
  }
  
  # State machine for ticket workflow
  state_machine initial: :open do
    state :open
    state :in_progress
    state :waiting_for_customer
    state :resolved
    state :closed
    
    event :start_progress do
      transition open: :in_progress
    end
    
    event :wait_for_customer do
      transition in_progress: :waiting_for_customer
    end
    
    event :resolve do
      transition waiting_for_customer: :resolved
    end
    
    event :close do
      transition resolved: :closed
    end
    
    # Add more events and transitions as needed
  end
end
```

```ruby
# app/controllers/admin/support_tickets_controller.rb
class Admin::SupportTicketsController < Admin::BaseController
  # ... existing code ...
  
  def update
    if @ticket.update(ticket_params)
      # Log the status change
      if ticket_params[:status].present? && @ticket.saved_change_to_status?
        @ticket.support_messages.create!(
          content: "Ticket status changed to #{@ticket.status.humanize} by #{current_user.name}",
          message_type: :system,
          created_by: current_user
        )
      end
      
      redirect_to admin_support_ticket_path(@ticket), notice: "Ticket updated successfully."
    else
      redirect_to admin_support_ticket_path(@ticket), alert: "Failed to update ticket: #{@ticket.errors.full_messages.join(', ')}"
    end
  end
  
  private
  
  def ticket_params
    params.require(:support_ticket).permit(:subject, :description, :priority, :category, :assigned_to_id, :status)
  end
end
```

### Task 4: Add Ticket Search and Filtering
**Description:** Implement search and filtering functionality for tickets.

**Implementation Notes:**
- Add search form to the ticket index page
- Implement filtering by status, priority, category, and assigned agent
- Enable search by ticket reference number or subject
- Update ticket listing logic in the controller

```ruby
# app/controllers/admin/support_tickets_controller.rb
class Admin::SupportTicketsController < Admin::BaseController
  def index
    @tickets = current_business.support_tickets
      .includes(:created_by, :assigned_to)
      .order(created_at: :desc)
    
    # Filter by status
    if params[:status].present?
      @tickets = @tickets.where(status: params[:status])
    end
    
    # Filter by priority
    if params[:priority].present?
      @tickets = @tickets.where(priority: params[:priority])
    end
    
    # Filter by category
    if params[:category].present?
      @tickets = @tickets.where(category: params[:category])
    end
    
    # Filter by assigned agent
    if params[:assigned_to].present?
      if params[:assigned_to] == 'unassigned'
        @tickets = @tickets.where(assigned_to: nil)
      elsif params[:assigned_to] == 'me'
        @tickets = @tickets.where(assigned_to: current_user)
      else
        @tickets = @tickets.where(assigned_to_id: params[:assigned_to])
      end
    end
    
    # Search by reference number or subject
    if params[:search].present?
      @tickets = @tickets.where("reference_number LIKE ? OR subject LIKE ?", 
                              "%#{params[:search]}%", "%#{params[:search]}%")
    end
    
    @tickets = @tickets.paginate(page: params[:page], per_page: 10)
  end
end
```

```erb
<!-- app/views/admin/support_tickets/index.html.erb -->
<div class="container mx-auto px-4 py-6">
  <div class="flex justify-between items-center mb-6">
    <h1 class="text-2xl font-bold text-gray-800">Support Tickets</h1>
    <%= link_to "Create New Ticket", new_admin_support_ticket_path, class: "bg-indigo-600 hover:bg-indigo-700 text-white font-semibold py-2 px-4 rounded" %>
  </div>
  
  <div class="bg-white rounded-lg shadow mb-6">
    <div class="p-4 border-b border-gray-200">
      <h2 class="text-lg font-semibold text-gray-700">Filter Tickets</h2>
    </div>
    <div class="p-4">
      <%= form_with url: admin_support_tickets_path, method: :get, local: true, class: "flex flex-wrap items-center gap-4" do |f| %>
        <div>
          <%= f.label :status, "Status", class: "block text-sm font-medium text-gray-700 mb-1" %>
          <%= f.select :status, 
              options_for_select(SupportTicket.statuses.map { |k, v| [k.humanize, k] }, params[:status]), 
              { include_blank: "All Statuses" }, 
              class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" %>
        </div>
        
        <div>
          <%= f.label :priority, "Priority", class: "block text-sm font-medium text-gray-700 mb-1" %>
          <%= f.select :priority, 
              options_for_select(SupportTicket.priorities.map { |k, v| [k.humanize, k] }, params[:priority]), 
              { include_blank: "All Priorities" }, 
              class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" %>
        </div>
        
        <div>
          <%= f.label :category, "Category", class: "block text-sm font-medium text-gray-700 mb-1" %>
          <%= f.select :category, 
              options_for_select(SupportTicket.categories.map { |k, v| [k.humanize, k] }, params[:category]), 
              { include_blank: "All Categories" }, 
              class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" %>
        </div>
        
        <div>
          <%= f.label :assigned_to, "Assigned To", class: "block text-sm font-medium text-gray-700 mb-1" %>
          <%= f.select :assigned_to, 
              options_for_select(User.all.collect { |u| [u.name, u.id] }, params[:assigned_to]), 
              { include_blank: "All Agents", unassigned: "Unassigned", me: "My Tickets" }, 
              class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" %>
        </div>
        
        <div class="w-full md:w-auto">
          <%= f.label :search, "Search", class: "block text-sm font-medium text-gray-700 mb-1" %>
          <%= f.text_field :search, 
              params[:search], 
              class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500", 
              placeholder: "Ticket reference or subject" %>
        </div>
        
        <div class="self-end">
          <%= f.submit "Apply Filters", class: "bg-indigo-600 hover:bg-indigo-700 text-white font-semibold py-2 px-4 rounded mt-5" %>
          <%= link_to "Clear", admin_support_tickets_path, class: "ml-2 text-indigo-600 hover:text-indigo-900" %>
        </div>
      <% end %>
    </div>
  </div>
  
  <div class="bg-white rounded-lg shadow overflow-hidden">
    <% if @tickets.any? %>
      <table class="min-w-full divide-y divide-gray-200">
        <thead class="bg-gray-50">
          <tr>
            <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Ticket</th>
            <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Subject</th>
            <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Status</th>
            <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Priority</th>
            <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Created</th>
            <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Last Update</th>
            <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Actions</th>
          </tr>
        </thead>
        <tbody class="bg-white divide-y divide-gray-200">
          <% @tickets.each do |ticket| %>
            <tr>
              <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                <%= ticket.reference_number %>
              </td>
              <td class="px-6 py-4 text-sm text-gray-900">
                <%= link_to ticket.subject, admin_support_ticket_path(ticket), class: "text-indigo-600 hover:text-indigo-900" %>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                <%= render "status_badge", status: ticket.status %>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                <%= render "priority_badge", priority: ticket.priority %>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                <%= time_ago_in_words(ticket.created_at) %> ago
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                <%= time_ago_in_words(ticket.updated_at) %> ago
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                <%= link_to "View", admin_support_ticket_path(ticket), class: "text-indigo-600 hover:text-indigo-900" %>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
      
      <div class="px-4 py-3 border-t border-gray-200">
        <%= will_paginate @tickets, class: "pagination" %>
      </div>
    <% else %>
      <div class="p-6 text-center">
        <p class="text-gray-500 mb-4">No support tickets found matching your criteria.</p>
        <%= link_to "Create Your First Ticket", new_admin_support_ticket_path, class: "bg-indigo-600 hover:bg-indigo-700 text-white font-semibold py-2 px-4 rounded" %>
      </div>
    <% end %>
  </div>
</div>
```

```erb
<!-- app/views/admin/support_tickets/show.html.erb -->
<div class="container mx-auto px-4 py-6">
  <div class="flex justify-between items-center mb-6">
    <h1 class="text-2xl font-bold text-gray-800">
      Ticket #<%= @ticket.reference_number %>
    </h1>
    <%= link_to "Back to All Tickets", admin_support_tickets_path, class: "text-indigo-600 hover:text-indigo-900" %>
  </div>
  
  <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
    <!-- Ticket Details Sidebar -->
    <div class="md:col-span-1">
      <div class="bg-white rounded-lg shadow divide-y divide-gray-200">
        <div class="p-4">
          <h2 class="text-lg font-semibold text-gray-700 mb-4">Ticket Details</h2>
          
          <div class="mb-3">
            <h3 class="text-sm font-medium text-gray-500">Status</h3>
            <p><%= render "status_badge", status: @ticket.status %></p>
          </div>
          
          <div class="mb-3">
            <h3 class="text-sm font-medium text-gray-500">Priority</h3>
            <p><%= render "priority_badge", priority: @ticket.priority %></p>
          </div>
          
          <div class="mb-3">
            <h3 class="text-sm font-medium text-gray-500">Category</h3>
            <p class="text-gray-900"><%= @ticket.category.humanize %></p>
          </div>
          
          <div class="mb-3">
            <h3 class="text-sm font-medium text-gray-500">Created By</h3>
            <p class="text-gray-900"><%= @ticket.created_by.name %></p>
          </div>
          
          <div class="mb-3">
            <h3 class="text-sm font-medium text-gray-500">Created On</h3>
            <p class="text-gray-900"><%= @ticket.created_at.strftime('%B %d, %Y at %H:%M') %></p>
          </div>
          
          <div class="mb-3">
            <h3 class="text-sm font-medium text-gray-500">Last Updated</h3>
            <p class="text-gray-900"><%= @ticket.updated_at.strftime('%B %d, %Y at %H:%M') %></p>
          </div>
          
          <% if @ticket.assigned_to.present? %>
            <div class="mb-3">
              <h3 class="text-sm font-medium text-gray-500">Assigned To</h3>
              <p class="text-gray-900"><%= @ticket.assigned_to.name %></p>
            </div>
          <% end %>
        </div>
        
        <div class="p-4">
          <h2 class="text-lg font-semibold text-gray-700 mb-4">Actions</h2>
          
          <div class="space-y-2">
            <% if @ticket.open? || @ticket.in_progress? || @ticket.waiting_for_customer? %>
              <%= button_to "Close Ticket", close_admin_support_ticket_path(@ticket), 
                  method: :patch, 
                  class: "w-full bg-red-600 hover:bg-red-700 text-white font-semibold py-2 px-4 rounded",
                  data: { confirm: "Are you sure you want to close this ticket?" } %>
            <% elsif @ticket.closed? %>
              <%= button_to "Reopen Ticket", reopen_admin_support_ticket_path(@ticket), 
                  method: :patch, 
                  class: "w-full bg-green-600 hover:bg-green-700 text-white font-semibold py-2 px-4 rounded" %>
            <% end %>
            
            <%= link_to "Create New Ticket", new_admin_support_ticket_path, 
                class: "block text-center w-full mt-2 border border-gray-300 bg-white text-gray-700 hover:bg-gray-100 font-semibold py-2 px-4 rounded" %>
          </div>
        </div>
        
        <% if @ticket.attachments.attached? %>
          <div class="p-4">
            <h2 class="text-lg font-semibold text-gray-700 mb-4">Attachments</h2>
            
            <div class="space-y-2">
              <% @ticket.attachments.each do |attachment| %>
                <div class="flex items-center justify-between p-2 bg-gray-50 rounded">
                  <div class="flex items-center">
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-gray-400 mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.172 7l-6.586 6.586a2 2 0 102.828 2.828l6.414-6.586a4 4 0 00-5.656-5.656l-6.415 6.585a6 6 0 108.486 8.486L20.5 13" />
                    </svg>
                    <span class="text-sm truncate max-w-xs"><%= attachment.filename %></span>
                  </div>
                  
                  <%= link_to rails_blob_path(attachment, disposition: "attachment"), target: "_blank", class: "text-indigo-600 hover:text-indigo-900" do %>
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4" />
                    </svg>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    
    <!-- Message Thread -->
    <div class="md:col-span-2">
      <div class="bg-white rounded-lg shadow">
        <div class="p-4 border-b border-gray-200">
          <h2 class="text-xl font-semibold text-gray-800"><%= @ticket.subject %></h2>
        </div>
        
        <div class="p-4 border-b border-gray-200 bg-gray-50">
          <div class="flex items-start mb-4">
            <div class="flex-shrink-0">
              <!-- Avatar placeholder -->
              <div class="h-10 w-10 rounded-full bg-indigo-100 flex items-center justify-center">
                <span class="text-indigo-700 font-semibold"><%= @ticket.created_by.name.first.upcase %></span>
              </div>
            </div>
            
            <div class="ml-3 flex-1">
              <div class="flex items-center">
                <h3 class="text-sm font-medium text-gray-900"><%= @ticket.created_by.name %></h3>
                <span class="ml-2 text-xs text-gray-500"><%= @ticket.created_at.strftime('%B %d, %Y at %H:%M') %></span>
              </div>
              
              <div class="mt-1 text-sm text-gray-700">
                <p><%= simple_format(@ticket.description) %></p>
              </div>
            </div>
          </div>
        </div>
        
        <!-- Message Thread -->
        <div class="p-4 space-y-6">
          <% @messages.each do |message| %>
            <div class="flex items-start">
              <div class="flex-shrink-0">
                <!-- Avatar placeholder -->
                <div class="h-10 w-10 rounded-full flex items-center justify-center <%= message.agent? ? 'bg-green-100' : 'bg-indigo-100' %>">
                  <span class="<%= message.agent? ? 'text-green-700' : 'text-indigo-700' %> font-semibold">
                    <%= message.created_by.name.first.upcase %>
                  </span>
                </div>
              </div>
              
              <div class="ml-3 flex-1">
                <div class="flex items-center">
                  <h3 class="text-sm font-medium text-gray-900">
                    <%= message.created_by.name %>
                    <% if message.agent? %>
                      <span class="ml-2 px-2 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">Support Agent</span>
                    <% end %>
                    <% if message.system? %>
                      <span class="ml-2 px-2 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800">System</span>
                    <% end %>
                  </h3>
                  <span class="ml-2 text-xs text-gray-500"><%= message.created_at.strftime('%B %d, %Y at %H:%M') %></span>
                </div>
                
                <div class="mt-1 text-sm text-gray-700">
                  <p><%= simple_format(message.content) %></p>
                  
                  <% if message.attachments.attached? %>
                    <div class="mt-2">
                      <h4 class="text-xs font-medium text-gray-500 mb-1">Attachments:</h4>
                      <div class="space-y-1">
                        <% message.attachments.each do |attachment| %>
                          <div class="flex items-center justify-between p-1 bg-gray-50 rounded text-xs">
                            <span class="truncate max-w-xs"><%= attachment.filename %></span>
                            <%= link_to rails_blob_path(attachment, disposition: "attachment"), target: "_blank", class: "text-indigo-600 hover:text-indigo-900 ml-2" do %>
                              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4" />
                              </svg>
                            <% end %>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>
        </div>
        
        <!-- Reply Form -->
        <% unless @ticket.closed? || @ticket.resolved? %>
          <div class="p-4 bg-gray-50 border-t border-gray-200">
            <h3 class="text-lg font-medium text-gray-900 mb-3">Reply to this ticket</h3>
            
            <%= form_with model: @message, url: admin_support_ticket_support_messages_path(@ticket), local: true do |f| %>
              <div class="mb-4">
                <%= f.label :content, "Your message", class: "block text-sm font-medium text-gray-700" %>
                <%= f.text_area :content, rows: 4, class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500", placeholder: "Type your message here..." %>
                <% if @message.errors[:content].any? %>
                  <p class="mt-1 text-sm text-red-600"><%= @message.errors[:content].first %></p>
                <% end %>
              </div>
              
              <div class="mb-4">
                <%= label_tag :message_attachments, "Attachments", class: "block text-sm font-medium text-gray-700" %>
                <%= file_field_tag :message_attachments, multiple: true, class: "mt-1 block w-full text-sm text-gray-500
                                  file:mr-4 file:py-2 file:px-4
                                  file:rounded-md file:border-0
                                  file:text-sm file:font-semibold
                                  file:bg-indigo-50 file:text-indigo-700
                                  hover:file:bg-indigo-100" %>
                <p class="mt-1 text-xs text-gray-500">You can upload multiple files (max 5MB each)</p>
              </div>
              
              <%= f.submit "Send Message", class: "bg-indigo-600 hover:bg-indigo-700 text-white font-semibold py-2 px-4 rounded" %>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
  </div>
</div>
```

### Task 5: Create Ticket Notification System
**Description:** Implement email notifications for ticket updates and responses.

**Implementation Notes:**
- Create mailers for ticket creation and updates
- Implement ticket response notifications
- Add email reply-to-ticket functionality
- Create email templates with branding

```ruby
# app/mailers/support_mailer.rb
class SupportMailer < ApplicationMailer
  def new_ticket_notification(ticket)
    @ticket = ticket
    @business = ticket.business
    
    mail(
      to: "support@shadetree.io",
      subject: "New Support Ticket: #{@ticket.reference_number} - #{@ticket.subject}",
      reply_to: "ticket+#{@ticket.reference_number}@shadetree.io"
    )
  end
  
  def new_message_notification(message)
    @message = message
    @ticket = message.support_ticket
    @business = @ticket.business
    
    mail(
      to: "support@shadetree.io",
      subject: "New Message on Ticket: #{@ticket.reference_number} - #{@ticket.subject}",
      reply_to: "ticket+#{@ticket.reference_number}@shadetree.io"
    )
  end
  
  def new_agent_response(message)
    @message = message
    @ticket = message.support_ticket
    @business = @ticket.business
    @user = @ticket.created_by
    
    mail(
      to: @user.email,
      subject: "Update on your support request: #{@ticket.reference_number} - #{@ticket.subject}",
      reply_to: "ticket+#{@ticket.reference_number}@shadetree.io"
    )
  end
  
  def ticket_status_update(ticket, previous_status)
    @ticket = ticket
    @business = ticket.business
    @user = ticket.created_by
    @previous_status = previous_status
    
    mail(
      to: @user.email,
      subject: "Status update on ticket: #{@ticket.reference_number} - #{@ticket.subject}",
      reply_to: "ticket+#{@ticket.reference_number}@shadetree.io"
    )
  end
end
```

```erb
<!-- app/views/support_mailer/new_agent_response.html.erb -->
<!DOCTYPE html>
<html>
  <head>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
    <style>
      /* Email styles */
      body {
        font-family: Arial, sans-serif;
        line-height: 1.6;
        color: #333333;
      }
      
      .container {
        max-width: 600px;
        margin: 0 auto;
        padding: 20px;
      }
      
      .header {
        background-color: #4f46e5;
        color: white;
        padding: 20px;
        text-align: center;
        border-radius: 5px 5px 0 0;
      }
      
      .content {
        background-color: #f9fafb;
        padding: 20px;
        border-left: 1px solid #e5e7eb;
        border-right: 1px solid #e5e7eb;
      }
      
      .message {
        background-color: white;
        padding: 15px;
        border-left: 4px solid #4f46e5;
        margin-top: 15px;
        margin-bottom: 15px;
      }
      
      .footer {
        background-color: #f3f4f6;
        padding: 15px;
        text-align: center;
        font-size: 12px;
        color: #6b7280;
        border-radius: 0 0 5px 5px;
        border: 1px solid #e5e7eb;
      }
      
      .button {
        display: inline-block;
        background-color: #4f46e5;
        color: white;
        padding: 10px 20px;
        text-decoration: none;
        border-radius: 5px;
        margin-top: 15px;
      }
    </style>
  </head>
  
  <body>
    <div class="container">
      <div class="header">
        <h1>Support Update</h1>
      </div>
      
      <div class="content">
        <p>Hello <%= @user.first_name %>,</p>
        
        <p>We have an update on your support request <strong>#<%= @ticket.reference_number %></strong>:</p>
        
        <div class="message">
          <%= simple_format(@message.content) %>
          
          <% if @message.attachments.any? %>
            <p><strong>Attachments:</strong></p>
            <ul>
              <% @message.attachments.each do |attachment| %>
                <li><%= attachment.filename %></li>
              <% end %>
            </ul>
            <p><small>Please log in to your account to download the attachments.</small></p>
          <% end %>
          
          <p><small>
            Replied by <%= @message.created_by.name %> on <%= @message.created_at.strftime('%B %d, %Y at %H:%M') %>
          </small></p>
        </div>
        
        <p>You can reply directly to this email or click the button below to view the full conversation.</p>
        
        <div style="text-align: center;">
          <a href="<%= admin_support_ticket_url(@ticket) %>" class="button">View Ticket</a>
        </div>
      </div>
      
      <div class="footer">
        <p>This is an automated message from the Shadetree support system. Please do not reply directly to this email.</p>
        <p>© <%= Date.today.year %> Shadetree. All rights reserved.</p>
      </div>
    </div>
  </body>
</html>
```

## Security Considerations
- Implement proper access controls to ticket data
- Sanitize and validate all user inputs
- Ensure file upload security with proper validation and scanning
- Securely handle email reply processing
- Protect sensitive information in ticket contents

## Testing Strategy
- Unit tests for ticket and message models
- Integration tests for ticket creation and updates
- Controller tests for security and access controls
- View tests for UI components
- Mailer tests for notification delivery

## Rollout Plan
1. Deploy help desk models and basic ticket management
2. Add support agent interface and ticket assignment
3. Implement email notifications and templates
4. Release knowledge base integration with tickets
5. Enable file attachments and security scanning
6. Add canned responses and efficiency features
`````
