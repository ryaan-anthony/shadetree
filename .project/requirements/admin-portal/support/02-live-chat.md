# Feature: Live Chat Support

## Description
Real-time chat functionality that allows customers to instantly connect with support agents for immediate assistance, with chat routing, queuing, and conversation management.

## User Stories
- As a customer, I can initiate a live chat session for immediate help
- As a support agent, I can accept and manage multiple chat conversations
- As a support agent, I can see typing indicators and customer information
- As a manager, I can monitor chat queues and agent availability
- As a business owner, I can customize chat widget appearance and availability hours

## Acceptance Criteria
- Chat widget embedded on customer-facing pages
- Real-time messaging with WebSocket connections
- Agent availability and status management
- Chat queue management with routing rules
- Conversation history and transcript storage
- File sharing capabilities within chat
- Automated responses and chatbot integration

## Tasks

### Task 1: Create Chat Models and Real-time Infrastructure
**Description:** Design and implement the core data models for the live chat system, and set up WebSocket connections for real-time chat functionality.

**Implementation Notes:**
- Create models for chat sessions and messages
- Implement relationships between users, businesses and support agents
- Add support for chat statuses and transitions
- Create Action Cable channels for chat communication
- Implement WebSocket connections and message broadcasting
- Add presence indicators and typing notifications

```ruby
# app/models/chat_session.rb
class ChatSession < ApplicationRecord
  belongs_to :business
  belongs_to :user
  belongs_to :agent, class_name: 'User', optional: true
  has_many :chat_messages, dependent: :destroy
  
  validates :status, presence: true
  
  enum status: { waiting: 0, active: 1, ended: 2, converted_to_ticket: 3 }
  
  scope :active, -> { where(status: [:waiting, :active]) }
  scope :waiting, -> { where(status: :waiting) }
  scope :with_agent, -> { where.not(agent_id: nil) }
  
  before_create :set_session_key
  
  def duration
    return nil unless active? || ended? || converted_to_ticket?
    return Time.current - created_at if active?
    
    ended_at - created_at if ended_at.present?
  end
  
  def idle_time
    return 0 if chat_messages.empty?
    
    Time.current - chat_messages.order(created_at: :desc).first.created_at
  end
  
  def assign_to_agent(agent)
    update(agent: agent, status: :active)
    
    # Create system message about agent assignment
    chat_messages.create!(
      content: "#{agent.name} has joined the chat.",
      sender_type: :system
    )
  end
  
  def end_chat(ended_by_user: true)
    update(status: :ended, ended_at: Time.current)
    
    # Create system message about chat ending
    message = ended_by_user ? "Chat ended by user." : "Chat ended by agent."
    chat_messages.create!(
      content: message,
      sender_type: :system
    )
  end
  
  def convert_to_ticket
    ticket = nil
    
    # Transaction to ensure both operations succeed or fail together
    ActiveRecord::Base.transaction do
      # Create ticket from chat
      ticket = business.support_tickets.create!(
        subject: "Chat converted to ticket",
        description: chat_summary,
        priority: :normal,
        category: :general,
        status: :open,
        created_by: user,
        reference_number: generate_reference_number
      )
      
      # Update chat session status
      update!(status: :converted_to_ticket, ended_at: Time.current)
      
      # Add system message about conversion
      chat_messages.create!(
        content: "Chat converted to support ticket ##{ticket.reference_number}",
        sender_type: :system
      )
    end
    
    ticket
  end
  
  private
  
  def set_session_key
    self.session_key ||= SecureRandom.hex(16)
  end
  
  def chat_summary
    summary = "This ticket was converted from a chat session that started on #{created_at.strftime('%B %d, %Y at %H:%M')}.\n\n"
    summary += "Chat History:\n"
    
    chat_messages.order(created_at: :asc).each do |message|
      prefix = case message.sender_type
               when 'user' then "#{user.name}: "
               when 'agent' then "Agent (#{agent&.name || 'Unknown'}): "
               when 'system' then "System: "
               end
               
      summary += "#{prefix}#{message.content}\n"
    end
    
    summary
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
# app/models/chat_message.rb
class ChatMessage < ApplicationRecord
  belongs_to :chat_session
  belongs_to :sender, polymorphic: true, optional: true
  
  validates :content, presence: true
  validates :sender_type, presence: true
  
  enum sender_type: { user: 0, agent: 1, system: 2 }
  
  scope :from_user, -> { where(sender_type: :user) }
  scope :from_agent, -> { where(sender_type: :agent) }
  scope :system_messages, -> { where(sender_type: :system) }
  
  after_create_commit -> { broadcast_message }
  
  def sender_name
    return "System" if system?
    return sender&.name || "Unknown" if sender.present?
    "Unknown"
  end
  
  private
  
  def broadcast_message
    # Broadcast message to appropriate channels
    ChatSessionChannel.broadcast_to(
      chat_session,
      {
        message: self,
        html: ApplicationController.renderer.render(
          partial: 'admin/chats/message',
          locals: { message: self }
        )
      }
    )
  end
end
```

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_chat_sessions.rb
class CreateChatSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :chat_sessions do |t|
      t.references :business, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :agent, null: true, foreign_key: { to_table: :users }
      t.integer :status, default: 0, null: false
      t.datetime :ended_at
      t.string :session_key, null: false
      
      t.timestamps
    end
    
    add_index :chat_sessions, :session_key, unique: true
    add_index :chat_sessions, :status
  end
end
```

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_chat_messages.rb
class CreateChatMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :chat_messages do |t|
      t.references :chat_session, null: false, foreign_key: true
      t.text :content, null: false
      t.integer :sender_type, default: 0, null: false
      t.references :sender, polymorphic: true, null: true
      t.boolean :read, default: false
      t.datetime :read_at
      
      t.timestamps
    end
    
    add_index :chat_messages, [:chat_session_id, :created_at]
    add_index :chat_messages, :sender_type
  end
end
```

```ruby
# app/channels/chat_session_channel.rb
class ChatSessionChannel < ApplicationCable::Channel
  def subscribed
    chat_session = ChatSession.find_by(id: params[:id], session_key: params[:session_key])
    
    if chat_session && can_access_chat?(chat_session)
      stream_for chat_session
      track_presence(chat_session)
    else
      reject
    end
  end
  
  def unsubscribed
    stop_all_streams
    remove_presence
  end
  
  def send_message(data)
    chat_session = ChatSession.find(params[:id])
    return unless can_access_chat?(chat_session)
    
    sender_type = current_user.support_agent? ? :agent : :user
    
    message = chat_session.chat_messages.create!(
      content: data['content'],
      sender_type: sender_type,
      sender: current_user
    )
  end
  
  def typing(data)
    chat_session = ChatSession.find(params[:id])
    return unless can_access_chat?(chat_session)
    
    is_typing = data['typing'] == true
    role = current_user.support_agent? ? 'agent' : 'user'
    
    ChatSessionChannel.broadcast_to(
      chat_session,
      {
        typing: {
          user_id: current_user.id,
          name: current_user.name,
          role: role,
          is_typing: is_typing
        }
      }
    )
  end
  
  private
  
  def can_access_chat?(chat_session)
    return true if current_user.support_agent?
    return true if current_user.id == chat_session.user_id
    false
  end
  
  def track_presence(chat_session)
    role = current_user.support_agent? ? 'agent' : 'user'
    
    ChatSessionChannel.broadcast_to(
      chat_session,
      {
        presence: {
          user_id: current_user.id,
          name: current_user.name,
          role: role,
          status: 'online'
        }
      }
    )
  end
  
  def remove_presence
    return unless params[:id].present?
    
    chat_session = ChatSession.find_by(id: params[:id])
    return unless chat_session
    
    role = current_user.support_agent? ? 'agent' : 'user'
    
    ChatSessionChannel.broadcast_to(
      chat_session,
      {
        presence: {
          user_id: current_user.id,
          name: current_user.name,
          role: role,
          status: 'offline'
        }
      }
    )
  end
end
```

```javascript
// app/javascript/controllers/chat_controller.js
import { Controller } from "@hotwired/stimulus"
import consumer from "../channels/consumer"

export default class extends Controller {
  static targets = ["messages", "input", "form", "status", "typingIndicator"]
  
  connect() {
    this.sessionId = this.element.dataset.sessionId
    this.sessionKey = this.element.dataset.sessionKey
    this.userId = this.element.dataset.userId
    this.typingTimer = null
    this.lastTypingSignal = 0
    
    this.setupChannel()
    this.scrollToBottom()
    
    this.element.addEventListener("keydown", this.handleKeyDown.bind(this))
  }
  
  disconnect() {
    if (this.subscription) {
      this.subscription.unsubscribe()
    }
  }
  
  setupChannel() {
    this.subscription = consumer.subscriptions.create(
      {
        channel: "ChatSessionChannel",
        id: this.sessionId,
        session_key: this.sessionKey
      },
      {
        connected: this.channelConnected.bind(this),
        disconnected: this.channelDisconnected.bind(this),
        received: this.channelReceived.bind(this)
      }
    )
  }
  
  channelConnected() {
    this.setStatus("Connected")
  }
  
  channelDisconnected() {
    this.setStatus("Disconnected")
  }
  
  channelReceived(data) {
    if (data.html) {
      this.appendMessage(data.html)
    }
    
    if (data.typing) {
      this.handleTypingIndicator(data.typing)
    }
    
    if (data.presence) {
      this.handlePresenceChange(data.presence)
    }
  }
  
  submitForm(event) {
    event.preventDefault()
    
    const content = this.inputTarget.value.trim()
    if (!content) return
    
    this.subscription.perform("send_message", { content })
    this.inputTarget.value = ""
    this.resetTypingIndicator()
  }
  
  handleKeyDown(event) {
    if (event.target === this.inputTarget) {
      // Only send typing indicator every 2 seconds
      const now = Date.now()
      if (now - this.lastTypingSignal > 2000) {
        this.subscription.perform("typing", { typing: true })
        this.lastTypingSignal = now
      }
      
      // Reset the typing indicator 2 seconds after stopping
      clearTimeout(this.typingTimer)
      this.typingTimer = setTimeout(() => {
        this.subscription.perform("typing", { typing: false })
      }, 2000)
    }
  }
  
  handleTypingIndicator(data) {
    // Don't show typing indicator for our own messages
    if (data.user_id.toString() === this.userId) return
    
    if (data.is_typing) {
      this.typingIndicatorTarget.textContent = `${data.name} is typing...`
      this.typingIndicatorTarget.classList.remove("hidden")
    } else {
      this.typingIndicatorTarget.classList.add("hidden")
    }
  }
  
  resetTypingIndicator() {
    this.subscription.perform("typing", { typing: false })
    this.typingIndicatorTarget.classList.add("hidden")
  }
  
  handlePresenceChange(data) {
    // Update UI based on presence changes
    const userStatus = document.querySelector(`[data-user-id="${data.user_id}"]`)
    if (userStatus) {
      userStatus.dataset.status = data.status
      userStatus.classList.toggle("online", data.status === "online")
      userStatus.classList.toggle("offline", data.status === "offline")
    }
  }
  
  appendMessage(html) {
    this.messagesTarget.insertAdjacentHTML("beforeend", html)
    this.scrollToBottom()
  }
  
  scrollToBottom() {
    this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
  }
  
  setStatus(status) {
    this.statusTarget.textContent = status
  }
}
```

```erb
<!-- app/views/admin/chats/show.html.erb -->
<div class="container mx-auto px-4 py-6">
  <div class="flex justify-between items-center mb-6">
    <h1 class="text-2xl font-bold text-gray-800">
      Live Chat
      <span class="text-sm font-normal text-gray-500 ml-2">
        <%= @chat_session.active? ? "Active" : @chat_session.status.humanize %>
      </span>
    </h1>
    
    <div>
      <%= link_to "Back to Chats", admin_chats_path, class: "text-indigo-600 hover:text-indigo-900 mr-4" %>
      
      <% if @chat_session.active? || @chat_session.waiting? %>
        <%= button_to "End Chat", end_admin_chat_path(@chat_session), 
            method: :patch, 
            class: "inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-red-600 hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500" %>
        
        <%= button_to "Convert to Ticket", convert_to_ticket_admin_chat_path(@chat_session), 
            method: :post, 
            class: "inline-flex items-center px-4 py-2 border border-gray-300 shadow-sm text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 ml-3" %>
      <% end %>
    </div>
  </div>
  
  <div class="bg-white rounded-lg shadow-lg overflow-hidden">
    <!-- Chat metadata header -->
    <div class="bg-gray-50 px-4 py-3 border-b border-gray-200">
      <div class="flex justify-between items-center">
        <div>
          <p class="text-sm font-medium text-gray-900">
            Chat started: <%= @chat_session.created_at.strftime('%B %d, %Y at %H:%M') %>
          </p>
          
          <% if @chat_session.topic.present? %>
            <p class="text-sm text-gray-500">Topic: <%= @chat_session.topic %></p>
          <% end %>
        </div>
        
        <div class="flex items-center">
          <span class="text-xs font-medium text-gray-500 mr-2">Status:</span>
          <span id="chat-status" class="px-2 py-1 text-xs font-medium rounded-full
            <%= @chat_session.active? ? 'bg-green-100 text-green-800' : 
               (@chat_session.waiting? ? 'bg-yellow-100 text-yellow-800' : 'bg-gray-100 text-gray-800') %>">
            <%= @chat_session.status.humanize %>
          </span>
        </div>
      </div>
    </div>
    
    <!-- Chat interface -->
    <div class="flex flex-col h-[600px]" 
         data-controller="chat" 
         data-chat-session-id-value="<%= @chat_session.id %>" 
         data-chat-session-key-value="<%= @chat_session.session_key %>"
         data-chat-user-id-value="<%= current_user.id %>">
      
      <!-- Messages container -->
      <div class="flex-1 overflow-y-auto p-4" data-chat-target="messages">
        <% @messages.each do |message| %>
          <%= render 'message', message: message %>
        <% end %>
      </div>
      
      <!-- Typing indicator -->
      <div class="px-4 py-2 text-sm text-gray-500 italic hidden" data-chat-target="typingIndicator"></div>
      
      <!-- Chat input -->
      <div class="border-t border-gray-200 px-4 py-3 bg-gray-50">
        <%= form_with url: '#', html: { class: "flex", data: { chat_target: "form", action: "submit->chat#submitForm" } } do |f| %>
          <%= f.text_field :content, 
              placeholder: (@chat_session.active? || @chat_session.waiting?) ? "Type your message..." : "Chat has ended",
              disabled: !(@chat_session.active? || @chat_session.waiting?),
              class: "flex-1 rounded-md border-gray-300 focus:border-indigo-500 focus:ring-indigo-500",
              data: { chat_target: "input" } %>
              
          <%= f.submit "Send", 
              disabled: !(@chat_session.active? || @chat_session.waiting?),
              class: "ml-3 inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 disabled:opacity-50" %>
        <% end %>
      </div>
    </div>
  </div>
</div>
```

### Task 2: Build Agent Chat Dashboard
**Description:** Create the interface for support agents to manage multiple chat sessions.

**Implementation Notes:**
- Design an agent dashboard showing all active chats
- Implement chat assignment and transfer functionality
- Create agent presence and availability indicators

```ruby
# app/controllers/support/agent/chats_controller.rb
class Support::Agent::ChatsController < Support::AgentController
  before_action :set_chat_session, only: [:show, :take, :end, :transfer]
  
  def index
    @waiting_chats = ChatSession.waiting.includes(:business, :user).order(created_at: :asc)
    @active_chats = ChatSession.active.includes(:business, :user, :agent).order(created_at: :desc)
    @my_chats = ChatSession.active.where(agent: current_user).includes(:business, :user).order(created_at: :desc)
    
    # Get online agents for transfer options
    @online_agents = User.support_agents.where(status: :online)
  end
  
  def show
    @messages = @chat_session.chat_messages.includes(:sender).order(created_at: :asc)
    
    # Mark any unread messages as read
    @messages.where(read: false).where.not(sender_type: :agent).update_all(read: true, read_at: Time.current)
    
    # Get customer details for agent context
    @customer = @chat_session.user
    @business = @chat_session.business
    @recent_tickets = @business.support_tickets.where(created_by: @customer).order(created_at: :desc).limit(5)
    @recent_chats = @business.chat_sessions.where(user: @customer).where.not(id: @chat_session.id).order(created_at: :desc).limit(5)
    
    # Get canned responses for quick replies
    @canned_responses = CannedResponse.active
  end
  
  def take
    if @chat_session.waiting?
      @chat_session.assign_to_agent(current_user)
      redirect_to support_agent_chat_path(@chat_session), notice: "You've joined the chat."
    else
      redirect_to support_agent_chats_path, alert: "This chat is no longer available."
    end
  end
  
  def end
    @chat_session.end_chat(ended_by_user: false)
    redirect_to support_agent_chats_path, notice: "Chat session ended."
  end
  
  def transfer
    agent = User.support_agents.find(params[:agent_id])
    
    if @chat_session.update(agent: agent)
      # Create system message about transfer
      @chat_session.chat_messages.create!(
        content: "Chat transferred from #{current_user.name} to #{agent.name}.",
        sender_type: :system
      )
      
      redirect_to support_agent_chats_path, notice: "Chat transferred to #{agent.name}."
    else
      redirect_to support_agent_chat_path(@chat_session), alert: "Failed to transfer chat."
    end
  end
  
  def create_message
    @chat_session = ChatSession.find(params[:chat_id])
    
    if @chat_session.active? && @chat_session.agent == current_user
      @message = @chat_session.chat_messages.new(
        content: params[:content],
        sender_type: :agent,
        sender: current_user
      )
      
      if @message.save
        # ChatChannel will broadcast the message
        head :ok
      else
        render json: { errors: @message.errors.full_messages }, status: :unprocessable_entity
      end
    else
      head :forbidden
    end
  end
  
  private
  
  def set_chat_session
    @chat_session = ChatSession.find(params[:id])
  end
end
```

```erb
<!-- app/views/support/agent/chats/index.html.erb -->
<div class="container mx-auto px-4 py-6">
  <div class="flex justify-between items-center mb-6">
    <h1 class="text-2xl font-bold text-gray-800">Support Chat Dashboard</h1>
    
    <!-- Agent status control -->
    <div class="flex items-center">
      <span class="mr-2 text-sm font-medium text-gray-700">Status:</span>
      <div class="relative" data-controller="agent-status">
        <button type="button" data-action="agent-status#toggle" class="inline-flex items-center px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium
            <%= current_user.online? ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-800' %>">
          <span data-agent-status-target="statusText"><%= current_user.status.humanize %></span>
          <svg class="ml-2 -mr-0.5 h-4 w-4" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
            <path fill-rule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clip-rule="evenodd" />
          </svg>
        </button>
        
        <div data-agent-status-target="dropdown" class="origin-top-right absolute right-0 mt-2 w-48 rounded-md shadow-lg bg-white ring-1 ring-black ring-opacity-5 focus:outline-none hidden">
          <div class="py-1">
            <%= button_to "Online", support_agent_status_path(status: :online), method: :patch, class: "text-left w-full px-4 py-2 text-sm text-gray-700 hover:bg-gray-100" %>
            <%= button_to "Away", support_agent_status_path(status: :away), method: :patch, class: "text-left w-full px-4 py-2 text-sm text-gray-700 hover:bg-gray-100" %>
            <%= button_to "Busy", support_agent_status_path(status: :busy), method: :patch, class: "text-left w-full px-4 py-2 text-sm text-gray-700 hover:bg-gray-100" %>
            <%= button_to "Offline", support_agent_status_path(status: :offline), method: :patch, class: "text-left w-full px-4 py-2 text-sm text-gray-700 hover:bg-gray-100" %>
          </div>
        </div>
      </div>
    </div>
  </div>
  
  <!-- Dashboard stats -->
  <div class="grid grid-cols-1 md:grid-cols-4 gap-6 mb-6">
    <div class="bg-white overflow-hidden shadow rounded-lg">
      <div class="px-4 py-5 sm:p-6">
        <div class="flex items-center">
          <div class="flex-shrink-0 bg-indigo-500 rounded-md p-3">
            <svg class="h-6 w-6 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
            </svg>
          </div>
          <div class="ml-5 w-0 flex-1">
            <dt class="text-sm font-medium text-gray-500 truncate">My Active Chats</dt>
            <dd class="flex items-baseline">
              <div class="text-2xl font-semibold text-gray-900">
                <%= @my_chats.count %>
              </div>
            </dd>
          </div>
        </div>
      </div>
    </div>
    
    <div class="bg-white overflow-hidden shadow rounded-lg">
      <div class="px-4 py-5 sm:p-6">
        <div class="flex items-center">
          <div class="flex-shrink-0 bg-yellow-500 rounded-md p-3">
            <svg class="h-6 w-6 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
          </div>
          <div class="ml-5 w-0 flex-1">
            <dt class="text-sm font-medium text-gray-500 truncate">Waiting Chats</dt>
            <dd class="flex items-baseline">
              <div class="text-2xl font-semibold text-gray-900">
                <%= @waiting_chats.count %>
              </div>
            </dd>
          </div>
        </div>
      </div>
    </div>
    
    <div class="bg-white overflow-hidden shadow rounded-lg">
      <div class="px-4 py-5 sm:p-6">
        <div class="flex items-center">
          <div class="flex-shrink-0 bg-green-500 rounded-md p-3">
            <svg class="h-6 w-6 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 8h2a2 2 0 012 2v6a2 2 0 01-2 2h-2v4l-4-4H9a1.994 1.994 0 01-1.414-.586m0 0L11 14h4a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2v4l.586-.586z" />
            </svg>
          </div>
          <div class="ml-5 w-0 flex-1">
            <dt class="text-sm font-medium text-gray-500 truncate">Total Active Chats</dt>
            <dd class="flex items-baseline">
              <div class="text-2xl font-semibold text-gray-900">
                <%= @active_chats.count %>
              </div>
            </dd>
          </div>
        </div>
      </div>
    </div>
    
    <div class="bg-white overflow-hidden shadow rounded-lg">
      <div class="px-4 py-5 sm:p-6">
        <div class="flex items-center">
          <div class="flex-shrink-0 bg-purple-500 rounded-md p-3">
            <svg class="h-6 w-6 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z" />
            </svg>
          </div>
          <div class="ml-5 w-0 flex-1">
            <dt class="text-sm font-medium text-gray-500 truncate">Online Agents</dt>
            <dd class="flex items-baseline">
              <div class="text-2xl font-semibold text-gray-900">
                <%= @online_agents.count %>
              </div>
            </dd>
          </div>
        </div>
      </div>
    </div>
  </div>
  
  <!-- Waiting chats section -->
  <div class="bg-white shadow rounded-lg mb-6">
    <div class="px-4 py-5 border-b border-gray-200 sm:px-6">
      <h2 class="text-lg font-medium text-gray-900">Waiting for Support</h2>
    </div>
    
    <div class="overflow-x-auto">
      <% if @waiting_chats.any? %>
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Customer</th>
              <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Business</th>
              <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Topic</th>
              <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Waiting Since</th>
              <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Actions</th>
            </tr>
          </thead>
          <tbody class="bg-white divide-y divide-gray-200">
            <% @waiting_chats.each do |chat| %>
              <tr>
                <td class="px-6 py-4 whitespace-nowrap">
                  <div class="flex items-center">
                    <div class="flex-shrink-0 h-10 w-10 rounded-full bg-gray-200 flex items-center justify-center">
                      <span class="text-gray-500 font-medium"><%= chat.user.name.first.upcase %></span>
                    </div>
                    <div class="ml-4">
                      <div class="text-sm font-medium text-gray-900"><%= chat.user.name %></div>
                      <div class="text-sm text-gray-500"><%= chat.user.email %></div>
                    </div>
                  </div>
                </td>
                <td class="px-6 py-4 whitespace-nowrap">
                  <div class="text-sm text-gray-900"><%= chat.business.name %></div>
                </td>
                <td class="px-6 py-4">
                  <div class="text-sm text-gray-900"><%= chat.topic.present? ? chat.topic : "No topic specified" %></div>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  <%= time_ago_in_words(chat.created_at) %> ago
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                  <%= button_to "Take Chat", take_support_agent_chat_path(chat), 
                      method: :patch,
                      class: "text-indigo-600 hover:text-indigo-900" %>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      <% else %>
        <div class="px-6 py-4 text-center text-sm text-gray-500">
          No waiting chats at this time.
        </div>
      <% end %>
    </div>
  </div>
  
  <!-- My chats section -->
  <div class="bg-white shadow rounded-lg mb-6">
    <div class="px-4 py-5 border-b border-gray-200 sm:px-6">
      <h2 class="text-lg font-medium text-gray-900">My Chats</h2>
    </div>
    
    <div class="overflow-x-auto">
      <% if @my_chats.any? %>
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Customer</th>
              <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Business</th>
              <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Topic</th>
              <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Duration</th>
              <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Last Message</th>
              <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Actions</th>
            </tr>
          </thead>
          <tbody class="bg-white divide-y divide-gray-200">
            <% @my_chats.each do |chat| %>
              <tr>
                <td class="px-6 py-4 whitespace-nowrap">
                  <div class="flex items-center">
                    <div class="flex-shrink-0 h-10 w-10 rounded-full bg-gray-200 flex items-center justify-center">
                      <span class="text-gray-500 font-medium"><%= chat.user.name.first.upcase %></span>
                    </div>
                    <div class="ml-4">
                      <div class="text-sm font-medium text-gray-900"><%= chat.user.name %></div>
                      <div class="text-sm text-gray-500"><%= chat.user.email %></div>
                    </div>
                  </div>
                </td>
                <td class="px-6 py-4 whitespace-nowrap">
                  <div class="text-sm text-gray-900"><%= chat.business.name %></div>
                </td>
                <td class="px-6 py-4">
                  <div class="text-sm text-gray-900"><%= chat.topic.present? ? chat.topic : "No topic specified" %></div>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  <%= distance_of_time_in_words(chat.created_at, Time.current) %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  <% last_message = chat.chat_messages.order(created_at: :desc).first %>
                  <% if last_message %>
                    <%= time_ago_in_words(last_message.created_at) %> ago
                  <% else %>
                    No messages yet
                  <% end %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                  <%= link_to "Open Chat", support_agent_chat_path(chat), class: "text-indigo-600 hover:text-indigo-900" %>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      <% else %>
        <div class="px-6 py-4 text-center text-sm text-gray-500">
          You don't have any active chats.
        </div>
      <% end %>
    </div>
  </div>
</div>
```

### Task 3: Implement Customer Chat Widget
**Description:** Create a global chat widget that allows users to start conversations from anywhere in the admin portal.

**Implementation Notes:**
- Design a floating chat button and panel
- Implement session persistence
- Create chat notifications for new messages

```javascript
// app/javascript/controllers/chat_widget_controller.js
import { Controller } from "@hotwired/stimulus"
import consumer from "../channels/consumer"

export default class extends Controller {
  static targets = ["button", "panel", "messages", "input", "form", "badge"]
  
  connect() {
    this.loadActiveChatSession()
    this.checkForNotifications()
  }
  
  toggle() {
    this.panelTarget.classList.toggle("hidden")
    
    if (!this.panelTarget.classList.contains("hidden")) {
      this.inputTarget.focus()
      
      // Mark notifications as read when opening the panel
      if (this.hasActiveChatSession()) {
        this.badgeTarget.classList.add("hidden")
        this.badgeTarget.textContent = "0"
      }
    }
  }
  
  loadActiveChatSession() {
    // Check for existing chat session
    fetch("/admin/active_chat_session")
      .then(response => response.json())
      .then(data => {
        if (data.active_chat) {
          this.setupExistingChat(data.active_chat)
        }
      })
      .catch(error => console.error("Error checking for active chat:", error))
  }
  
  setupExistingChat(chatData) {
    this.chatId = chatData.id
    this.sessionKey = chatData.session_key
    
    // Update the badge with unread count
    if (chatData.unread_count > 0) {
      this.badgeTarget.textContent = chatData.unread_count
      this.badgeTarget.classList.remove("hidden")
    }
    
    // Setup the connection for receiving messages
    this.setupChatChannel()
    
    // Load existing messages
    this.loadChatMessages()
  }
  
  setupChatChannel() {
    if (!this.chatId || !this.sessionKey) return
    
    this.subscription = consumer.subscriptions.create(
      {
        channel: "ChatSessionChannel",
        id: this.chatId,
        session_key: this.sessionKey
      },
      {
        received: data => {
          if (data.html) {
            this.appendMessage(data.html)
            
            // Show notification if the panel is closed
            if (this.panelTarget.classList.contains("hidden")) {
              this.showNotification()
            }
          }
        }
      }
    )
  }
  
  loadChatMessages() {
    if (!this.chatId) return
    
    fetch(`/admin/chats/${this.chatId}/messages`)
      .then(response => response.text())
      .then(html => {
        this.messagesTarget.innerHTML = html
        this.scrollToBottom()
      })
      .catch(error => console.error("Error loading chat messages:", error))
  }
  
  startNewChat(event) {
    event.preventDefault()
    
    const formData = new FormData(this.formTarget)
    
    fetch("/admin/chats", {
      method: "POST",
      body: formData,
      headers: {
        "X-Requested-With": "XMLHttpRequest"
      }
    })
    .then(response => response.json())
    .then(data => {
      if (data.success) {
        this.chatId = data.chat_id
        this.sessionKey = data.session_key
        this.setupChatChannel()
        this.loadChatMessages()
        this.inputTarget.value = ""
      } else {
        console.error("Error starting chat:", data.errors)
      }
    })
    .catch(error => console.error("Error starting chat:", error))
  }
  
  sendMessage(event) {
    event.preventDefault()
    
    if (!this.chatId || !this.sessionKey) return
    
    const content = this.inputTarget.value.trim()
    if (!content) return
    
    fetch(`/admin/chats/${this.chatId}/messages`, {
      method: "POST",
      body: JSON.stringify({ content }),
      headers: {
        "Content-Type": "application/json",
        "X-Requested-With": "XMLHttpRequest"
      }
    })
    .then(response => {
      if (response.ok) {
        this.inputTarget.value = ""
      }
    })
    .catch(error => console.error("Error sending message:", error))
  }
  
  appendMessage(html) {
    this.messagesTarget.insertAdjacentHTML("beforeend", html)
    this.scrollToBottom()
  }
  
  scrollToBottom() {
    this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
  }
  
  showNotification() {
    // Update the badge count
    const currentCount = parseInt(this.badgeTarget.textContent) || 0
    this.badgeTarget.textContent = currentCount + 1
    this.badgeTarget.classList.remove("hidden")
    
    // Flash the chat button
    this.buttonTarget.classList.add("animate-pulse")
    setTimeout(() => {
      this.buttonTarget.classList.remove("animate-pulse")
    }, 2000)
    
    // Browser notification if supported and permitted
    if ("Notification" in window && Notification.permission === "granted") {
      new Notification("New support message", {
        body: "You have a new message from support.",
        icon: "/favicon.ico"
      })
    }
  }
  
  hasActiveChatSession() {
    return !!this.chatId
  }
  
  checkForNotifications() {
    // Periodically check for new messages if we have an active chat
    if (this.hasActiveChatSession()) {
      this.notificationChecker = setInterval(() => {
        fetch(`/admin/chats/${this.chatId}/unread_count`)
          .then(response => response.json())
          .then(data => {
            if (data.unread_count > 0 && this.panelTarget.classList.contains("hidden")) {
              this.badgeTarget.textContent = data.unread_count
              this.badgeTarget.classList.remove("hidden")
            }
          })
      }, 30000) // Check every 30 seconds
    }
  }
  
  disconnect() {
    if (this.subscription) {
      this.subscription.unsubscribe()
    }
    
    if (this.notificationChecker) {
      clearInterval(this.notificationChecker)
    }
  }
}
```

```erb
<!-- app/views/shared/_chat_widget.html.erb -->
<div class="fixed right-4 bottom-4 z-50" data-controller="chat-widget">
  <!-- Chat button -->
  <button data-chat-widget-target="button" data-action="click->chat-widget#toggle" class="relative bg-indigo-600 hover:bg-indigo-700 text-white rounded-full p-4 shadow-lg focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500">
    <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
    </svg>
    
    <!-- Notification badge -->
    <span data-chat-widget-target="badge" class="absolute top-0 right-0 transform translate-x-1/2 -translate-y-1/2 bg-red-500 text-white text-xs font-bold rounded-full h-5 w-5 flex items-center justify-center hidden">0</span>
  </button>
  
  <!-- Chat panel -->
  <div data-chat-widget-target="panel" class="hidden absolute bottom-16 right-0 w-80 sm:w-96 bg-white rounded-lg shadow-xl border border-gray-200 overflow-hidden">
    <!-- Chat header -->
    <div class="bg-indigo-600 text-white px-4 py-3 flex justify-between items-center">
      <h3 class="text-lg font-medium">Support Chat</h3>
      <button data-action="click->chat-widget#toggle" class="text-white hover:text-gray-200">
        <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
          <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd" />
        </svg>
      </button>
    </div>
    
    <!-- Messages area -->
    <div data-chat-widget-target="messages" class="h-80 overflow-y-auto p-4">
      <% if !@active_chat %>
        <div class="text-center text-gray-500 mt-10">
          <svg xmlns="http://www.w3.org/2000/svg" class="mx-auto h-12 w-12" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
          </svg>
          <p class="mt-2">How can we help you today?</p>
          <p class="text-sm">Start a conversation with our support team.</p>
        </div>
      <% end %>
    </div>
    
    <!-- Input area -->
    <div class="border-t border-gray-200 px-4 py-3 bg-gray-50">
      <% if !@active_chat %>
        <%= form_with url: admin_chats_path, html: { data: { chat_widget_target: "form", action: "submit->chat-widget#startNewChat" } } do |f| %>
          <div class="mb-3">
            <%= f.text_field :initial_message, 
                placeholder: "Type your question...",
                required: true,
                class: "w-full rounded-md border-gray-300 focus:border-indigo-500 focus:ring-indigo-500",
                data: { chat_widget_target: "input" } %>
          </div>
          
          <div class="flex justify-end">
            <%= f.submit "Start Chat", class: "inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500" %>
          </div>
        <% end %>
      <% else %>
        <%= form_with url: '#', html: { data: { chat_widget_target: "form", action: "submit->chat-widget#sendMessage" } } do |f| %>
          <%= f.text_field :content, 
              placeholder: "Type your message...",
              class: "w-full rounded-md border-gray-300 focus:border-indigo-500 focus:ring-indigo-500",
              data: { chat_widget_target: "input" } %>
        <% end %>
      <% end %>
    </div>
  </div>
</div>
```

## Security Considerations
- Ensure proper authentication and authorization for chat access
- Implement rate limiting for message sending
- Validate and sanitize all user inputs
- Secure WebSocket connections with proper token authentication
- Add timeout handling for inactive chats
- Implement proper data retention policies for chat logs

## Testing Strategy
- Unit tests for chat models and business logic
- Integration tests for real-time message delivery
- End-to-end tests for the chat widget functionality
- Performance tests for concurrent chat sessions
- Security tests for authentication and authorization

## Rollout Plan
1. Deploy core chat models and backend services
2. Enable basic user chat interface for admin portal
3. Implement support agent dashboard
4. Add WebSocket infrastructure for real-time communication
5. Release chat widget for global accessibility
6. Enable chat to ticket conversion functionality
````
