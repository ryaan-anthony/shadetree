# Feature: Quick Actions Panel

## Description
A widget providing fast access to common administrative tasks and frequently used functions, allowing admins to perform routine operations without navigating through multiple pages.

## User Stories
- As a business owner, I want quick access to create new bookings so I can handle walk-in customers efficiently
- As a staff member, I want to quickly mark services as unavailable so I can manage my schedule
- As a manager, I want fast access to view today's schedule so I can coordinate operations
- As an admin, I want shortcuts to common settings so I can make quick adjustments

## Tasks

### Task 1: Create Quick Actions Service
**Implementation Notes:**
- Define available actions based on user roles
- Implement action validation and permissions
- Create service to handle action execution

```ruby
# app/services/admin/quick_actions_service.rb
class Admin::QuickActionsService
  attr_reader :admin, :business

  def initialize(admin)
    @admin = admin
    @business = admin.business
  end

  def available_actions
    base_actions = [
      {
        id: 'new_booking',
        title: 'New Booking',
        description: 'Create a booking for a customer',
        icon: 'fas fa-plus-circle',
        color: 'blue',
        path: new_admin_booking_path,
        permission: 'create_bookings'
      },
      {
        id: 'view_schedule',
        title: "Today's Schedule",
        description: 'View appointments for today',
        icon: 'fas fa-calendar-day',
        color: 'green',
        path: admin_schedule_path(date: Date.current),
        permission: 'view_schedule'
      },
      {
        id: 'add_customer',
        title: 'Add Customer',
        description: 'Register a new customer',
        icon: 'fas fa-user-plus',
        color: 'purple',
        path: new_admin_customer_path,
        permission: 'manage_customers'
      },
      {
        id: 'quick_note',
        title: 'Add Note',
        description: 'Create a quick business note',
        icon: 'fas fa-sticky-note',
        color: 'yellow',
        action: 'modal',
        modal_target: 'quick-note-modal',
        permission: 'create_notes'
      }
    ]

    # Add manager-specific actions
    if admin.manager? || admin.owner?
      base_actions += manager_actions
    end

    # Add owner-specific actions
    if admin.owner?
      base_actions += owner_actions
    end

    # Filter by permissions
    base_actions.select { |action| admin.can?(action[:permission]) }
  end

  def execute_action(action_id, params = {})
    case action_id
    when 'toggle_availability'
      toggle_staff_availability(params[:staff_id])
    when 'quick_block_time'
      create_time_block(params)
    when 'send_reminder'
      send_appointment_reminder(params[:booking_id])
    when 'quick_note'
      create_quick_note(params)
    else
      { success: false, error: 'Unknown action' }
    end
  end

  private

  def manager_actions
    [
      {
        id: 'staff_availability',
        title: 'Staff Status',
        description: 'View and update staff availability',
        icon: 'fas fa-users',
        color: 'indigo',
        path: admin_staff_path,
        permission: 'manage_staff'
      },
      {
        id: 'block_time',
        title: 'Block Time',
        description: 'Block time slots for maintenance',
        icon: 'fas fa-ban',
        color: 'red',
        action: 'modal',
        modal_target: 'block-time-modal',
        permission: 'manage_schedule'
      }
    ]
  end

  def owner_actions
    [
      {
        id: 'business_settings',
        title: 'Settings',
        description: 'Quick access to business settings',
        icon: 'fas fa-cog',
        color: 'gray',
        path: admin_business_settings_path,
        permission: 'manage_business'
      },
      {
        id: 'reports',
        title: 'Reports',
        description: 'View business reports',
        icon: 'fas fa-chart-bar',
        color: 'emerald',
        path: admin_reports_path,
        permission: 'view_reports'
      }
    ]
  end

  def toggle_staff_availability(staff_id)
    staff_member = business.staff_members.find(staff_id)
    staff_member.toggle!(:available)
    
    {
      success: true,
      message: "#{staff_member.name} is now #{staff_member.available? ? 'available' : 'unavailable'}",
      data: { available: staff_member.available? }
    }
  rescue ActiveRecord::RecordNotFound
    { success: false, error: 'Staff member not found' }
  end

  def create_time_block(params)
    time_block = business.time_blocks.create!(
      start_time: params[:start_time],
      end_time: params[:end_time],
      reason: params[:reason],
      staff_member_id: params[:staff_member_id],
      created_by: admin
    )

    {
      success: true,
      message: 'Time block created successfully',
      data: { id: time_block.id }
    }
  rescue ActiveRecord::RecordInvalid => e
    { success: false, error: e.message }
  end

  def send_appointment_reminder(booking_id)
    booking = business.bookings.find(booking_id)
    NotificationService.new.send_booking_reminder(booking)
    
    {
      success: true,
      message: 'Reminder sent successfully'
    }
  rescue ActiveRecord::RecordNotFound
    { success: false, error: 'Booking not found' }
  end

  def create_quick_note(params)
    note = business.notes.create!(
      content: params[:content],
      category: params[:category] || 'general',
      created_by: admin,
      priority: params[:priority] || 'normal'
    )

    {
      success: true,
      message: 'Note created successfully',
      data: { id: note.id }
    }
  rescue ActiveRecord::RecordInvalid => e
    { success: false, error: e.message }
  end
end
```

### Task 2: Create Quick Actions Widget View
**Implementation Notes:**
- Grid layout with action buttons
- Modal support for complex actions
- Responsive design for different screen sizes

```erb
<!-- app/views/admin/dashboard/widgets/_quick_actions.html.erb -->
<div 
  class="col-span-1 md:col-span-2 bg-white rounded-lg shadow p-6"
  data-widget="quick_actions"
  data-controller="quick-actions"
>
  <div class="flex items-center justify-between mb-6">
    <h3 class="text-lg font-medium text-gray-900">Quick Actions</h3>
    <button 
      class="text-sm text-blue-600 hover:text-blue-800"
      data-action="click->quick-actions#toggleExpanded"
    >
      <span data-quick-actions-target="toggleText">Show All</span>
    </button>
  </div>

  <% actions = Admin::QuickActionsService.new(current_admin).available_actions %>
  
  <div class="grid grid-cols-2 gap-4" data-quick-actions-target="actionsGrid">
    <% actions.first(4).each do |action| %>
      <div class="quick-action-item" data-expanded="false">
        <%= render 'admin/dashboard/widgets/quick_action_button', action: action %>
      </div>
    <% end %>
    
    <% if actions.length > 4 %>
      <% actions[4..-1].each do |action| %>
        <div class="quick-action-item hidden" data-expanded="true">
          <%= render 'admin/dashboard/widgets/quick_action_button', action: action %>
        </div>
      <% end %>
    <% end %>
  </div>

  <!-- Quick Note Modal -->
  <div 
    id="quick-note-modal" 
    class="fixed inset-0 bg-gray-600 bg-opacity-50 hidden z-50"
    data-quick-actions-target="modal"
  >
    <div class="flex items-center justify-center min-h-screen p-4">
      <div class="bg-white rounded-lg shadow-xl max-w-md w-full">
        <div class="p-6">
          <h3 class="text-lg font-medium mb-4">Add Quick Note</h3>
          
          <%= form_with url: admin_quick_actions_path, 
                        method: :post, 
                        local: false,
                        data: { 
                          action: "submit->quick-actions#submitForm",
                          quick_actions_target: "noteForm"
                        } do |form| %>
            <%= form.hidden_field :action_id, value: 'quick_note' %>
            
            <div class="mb-4">
              <%= form.label :content, class: "block text-sm font-medium text-gray-700 mb-2" %>
              <%= form.text_area :content, 
                                 rows: 3, 
                                 required: true,
                                 class: "w-full border-gray-300 rounded-md shadow-sm focus:border-blue-500 focus:ring-blue-500" %>
            </div>
            
            <div class="mb-4">
              <%= form.label :category, class: "block text-sm font-medium text-gray-700 mb-2" %>
              <%= form.select :category, 
                              options_for_select([
                                ['General', 'general'],
                                ['Customer', 'customer'],
                                ['Staff', 'staff'],
                                ['Operations', 'operations']
                              ]), 
                              {},
                              { class: "w-full border-gray-300 rounded-md shadow-sm focus:border-blue-500 focus:ring-blue-500" } %>
            </div>
            
            <div class="mb-6">
              <%= form.label :priority, class: "block text-sm font-medium text-gray-700 mb-2" %>
              <%= form.select :priority, 
                              options_for_select([
                                ['Normal', 'normal'],
                                ['High', 'high'],
                                ['Urgent', 'urgent']
                              ]), 
                              {},
                              { class: "w-full border-gray-300 rounded-md shadow-sm focus:border-blue-500 focus:ring-blue-500" } %>
            </div>
            
            <div class="flex justify-end space-x-3">
              <button 
                type="button" 
                class="btn btn-secondary"
                data-action="click->quick-actions#closeModal"
              >
                Cancel
              </button>
              <%= form.submit "Save Note", class: "btn btn-primary" %>
            </div>
          <% end %>
        </div>
      </div>
    </div>
  </div>

  <!-- Block Time Modal -->
  <div 
    id="block-time-modal" 
    class="fixed inset-0 bg-gray-600 bg-opacity-50 hidden z-50"
    data-quick-actions-target="modal"
  >
    <div class="flex items-center justify-center min-h-screen p-4">
      <div class="bg-white rounded-lg shadow-xl max-w-md w-full">
        <div class="p-6">
          <h3 class="text-lg font-medium mb-4">Block Time Slot</h3>
          
          <%= form_with url: admin_quick_actions_path, 
                        method: :post, 
                        local: false,
                        data: { 
                          action: "submit->quick-actions#submitForm",
                          quick_actions_target: "blockForm"
                        } do |form| %>
            <%= form.hidden_field :action_id, value: 'quick_block_time' %>
            
            <div class="mb-4">
              <%= form.label :start_time, class: "block text-sm font-medium text-gray-700 mb-2" %>
              <%= form.datetime_local_field :start_time, 
                                           required: true,
                                           class: "w-full border-gray-300 rounded-md shadow-sm focus:border-blue-500 focus:ring-blue-500" %>
            </div>
            
            <div class="mb-4">
              <%= form.label :end_time, class: "block text-sm font-medium text-gray-700 mb-2" %>
              <%= form.datetime_local_field :end_time, 
                                           required: true,
                                           class: "w-full border-gray-300 rounded-md shadow-sm focus:border-blue-500 focus:ring-blue-500" %>
            </div>
            
            <div class="mb-4">
              <%= form.label :reason, class: "block text-sm font-medium text-gray-700 mb-2" %>
              <%= form.text_field :reason, 
                                  required: true,
                                  placeholder: "e.g., Equipment maintenance",
                                  class: "w-full border-gray-300 rounded-md shadow-sm focus:border-blue-500 focus:ring-blue-500" %>
            </div>
            
            <div class="mb-6">
              <%= form.label :staff_member_id, "Staff Member (Optional)", class: "block text-sm font-medium text-gray-700 mb-2" %>
              <%= form.select :staff_member_id, 
                              options_from_collection_for_select(current_admin.business.staff_members, :id, :name), 
                              { prompt: 'All staff' },
                              { class: "w-full border-gray-300 rounded-md shadow-sm focus:border-blue-500 focus:ring-blue-500" } %>
            </div>
            
            <div class="flex justify-end space-x-3">
              <button 
                type="button" 
                class="btn btn-secondary"
                data-action="click->quick-actions#closeModal"
              >
                Cancel
              </button>
              <%= form.submit "Block Time", class: "btn btn-primary" %>
            </div>
          <% end %>
        </div>
      </div>
    </div>
  </div>
</div>
```

### Task 3: Create Quick Action Button Partial
**Implementation Notes:**
- Reusable button component
- Support for different action types (links, modals, AJAX)
- Visual consistency with color coding

```erb
<!-- app/views/admin/dashboard/widgets/_quick_action_button.html.erb -->
<% 
  color_classes = {
    'blue' => 'bg-blue-50 border-blue-200 text-blue-700 hover:bg-blue-100',
    'green' => 'bg-green-50 border-green-200 text-green-700 hover:bg-green-100',
    'purple' => 'bg-purple-50 border-purple-200 text-purple-700 hover:bg-purple-100',
    'yellow' => 'bg-yellow-50 border-yellow-200 text-yellow-700 hover:bg-yellow-100',
    'red' => 'bg-red-50 border-red-200 text-red-700 hover:bg-red-100',
    'indigo' => 'bg-indigo-50 border-indigo-200 text-indigo-700 hover:bg-indigo-100',
    'gray' => 'bg-gray-50 border-gray-200 text-gray-700 hover:bg-gray-100',
    'emerald' => 'bg-emerald-50 border-emerald-200 text-emerald-700 hover:bg-emerald-100'
  }
  
  button_classes = "w-full p-4 border-2 rounded-lg transition-colors duration-200 text-left #{color_classes[action[:color]] || color_classes['gray']}"
%>

<% if action[:action] == 'modal' %>
  <button 
    class="<%= button_classes %>"
    data-action="click->quick-actions#openModal"
    data-modal-target="<%= action[:modal_target] %>"
  >
    <div class="flex items-start">
      <div class="flex-shrink-0">
        <i class="<%= action[:icon] %> text-lg"></i>
      </div>
      <div class="ml-3">
        <h4 class="font-medium text-sm"><%= action[:title] %></h4>
        <p class="text-xs opacity-75 mt-1"><%= action[:description] %></p>
      </div>
    </div>
  </button>
<% elsif action[:path] %>
  <%= link_to action[:path], class: button_classes do %>
    <div class="flex items-start">
      <div class="flex-shrink-0">
        <i class="<%= action[:icon] %> text-lg"></i>
      </div>
      <div class="ml-3">
        <h4 class="font-medium text-sm"><%= action[:title] %></h4>
        <p class="text-xs opacity-75 mt-1"><%= action[:description] %></p>
      </div>
    </div>
  <% end %>
<% else %>
  <button 
    class="<%= button_classes %>"
    data-action="click->quick-actions#executeAction"
    data-action-id="<%= action[:id] %>"
  >
    <div class="flex items-start">
      <div class="flex-shrink-0">
        <i class="<%= action[:icon] %> text-lg"></i>
      </div>
      <div class="ml-3">
        <h4 class="font-medium text-sm"><%= action[:title] %></h4>
        <p class="text-xs opacity-75 mt-1"><%= action[:description] %></p>
      </div>
    </div>
  </button>
<% end %>
```

### Task 4: Create Quick Actions Controller and Routes
**Implementation Notes:**
- Handle quick action execution via AJAX
- Implement proper error handling and responses
- Add authorization checks

```ruby
# Add to config/routes.rb
namespace :admin do
  # ...existing routes...
  post 'quick_actions', to: 'quick_actions#execute'
end

# app/controllers/admin/quick_actions_controller.rb
class Admin::QuickActionsController < Admin::BaseController
  before_action :authenticate_admin!

  def execute
    service = Admin::QuickActionsService.new(current_admin)
    result = service.execute_action(params[:action_id], action_params)

    if result[:success]
      render json: {
        success: true,
        message: result[:message],
        data: result[:data]
      }
    else
      render json: {
        success: false,
        error: result[:error]
      }, status: :unprocessable_entity
    end
  rescue StandardError => e
    Rails.logger.error "Quick action error: #{e.message}"
    render json: {
      success: false,
      error: 'An unexpected error occurred'
    }, status: :internal_server_error
  end

  private

  def action_params
    params.permit(:content, :category, :priority, :start_time, :end_time, :reason, :staff_member_id)
  end
end
```

### Task 5: Create Quick Actions Stimulus Controller
**Implementation Notes:**
- Handle modal opening/closing
- Form submission via AJAX
- Action execution and feedback

```javascript
// app/javascript/controllers/quick_actions_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["actionsGrid", "modal", "noteForm", "blockForm", "toggleText"]

  connect() {
    this.expanded = false
  }

  toggleExpanded() {
    this.expanded = !this.expanded
    
    const expandedItems = this.actionsGridTarget.querySelectorAll('[data-expanded="true"]')
    const toggleText = this.toggleTextTarget
    
    if (this.expanded) {
      expandedItems.forEach(item => item.classList.remove('hidden'))
      toggleText.textContent = 'Show Less'
    } else {
      expandedItems.forEach(item => item.classList.add('hidden'))
      toggleText.textContent = 'Show All'
    }
  }

  openModal(event) {
    const modalTarget = event.currentTarget.dataset.modalTarget
    const modal = document.getElementById(modalTarget)
    
    if (modal) {
      modal.classList.remove('hidden')
      document.body.classList.add('overflow-hidden')
      
      // Focus first input
      const firstInput = modal.querySelector('input, textarea, select')
      if (firstInput) {
        setTimeout(() => firstInput.focus(), 100)
      }
    }
  }

  closeModal() {
    this.modalTargets.forEach(modal => {
      modal.classList.add('hidden')
    })
    document.body.classList.remove('overflow-hidden')
    
    // Reset forms
    this.resetForms()
  }

  submitForm(event) {
    event.preventDefault()
    
    const form = event.target
    const formData = new FormData(form)
    
    fetch(form.action, {
      method: 'POST',
      headers: {
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      },
      body: formData
    })
    .then(response => response.json())
    .then(data => {
      if (data.success) {
        this.showSuccess(data.message)
        this.closeModal()
      } else {
        this.showError(data.error)
      }
    })
    .catch(error => {
      console.error('Quick action error:', error)
      this.showError('An unexpected error occurred')
    })
  }

  executeAction(event) {
    const actionId = event.currentTarget.dataset.actionId
    const button = event.currentTarget
    
    // Show loading state
    button.disabled = true
    button.style.opacity = '0.6'
    
    fetch('/admin/quick_actions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      },
      body: JSON.stringify({ action_id: actionId })
    })
    .then(response => response.json())
    .then(data => {
      if (data.success) {
        this.showSuccess(data.message)
      } else {
        this.showError(data.error)
      }
    })
    .catch(error => {
      console.error('Quick action error:', error)
      this.showError('An unexpected error occurred')
    })
    .finally(() => {
      // Restore button state
      button.disabled = false
      button.style.opacity = '1'
    })
  }

  resetForms() {
    if (this.hasNoteFormTarget) {
      this.noteFormTarget.reset()
    }
    if (this.hasBlockFormTarget) {
      this.blockFormTarget.reset()
    }
  }

  showSuccess(message) {
    this.showNotification(message, 'success')
  }

  showError(message) {
    this.showNotification(message, 'error')
  }

  showNotification(message, type) {
    const notification = document.createElement('div')
    const bgColor = type === 'success' ? 'bg-green-500' : 'bg-red-500'
    
    notification.className = `fixed top-4 right-4 ${bgColor} text-white px-4 py-2 rounded shadow-lg z-50`
    notification.textContent = message
    
    document.body.appendChild(notification)
    
    setTimeout(() => {
      notification.remove()
    }, 5000)
  }

  // Handle escape key to close modals
  keydown(event) {
    if (event.key === 'Escape') {
      this.closeModal()
    }
  }
}
```

## Acceptance Criteria
- [ ] Actions display based on user role and permissions
- [ ] Modal forms submit successfully via AJAX
- [ ] Direct action buttons execute without page refresh
- [ ] Success/error notifications appear appropriately
- [ ] Mobile layout displays actions clearly
- [ ] Expand/collapse functionality works smoothly
- [ ] Keyboard navigation (ESC to close modals) works

## Testing Requirements
- Unit tests for QuickActionsService
- Integration tests for action execution
- Permission testing for role-based actions
- JavaScript functionality testing
- Mobile responsiveness testing
