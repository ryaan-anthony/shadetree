# Feature: Recent Activity Feed

## Description
A real-time activity timeline displaying recent bookings, changes, and system activities to keep administrators informed about business operations and system events.

## User Stories
- As a business owner, I want to see recent bookings so I can stay informed about customer activity
- As a manager, I want to see staff changes so I can monitor team activities
- As an admin, I want to see system events so I can track important changes
- As a business owner, I want to filter activities by type so I can focus on specific areas

## Tasks

### Task 1: Create Activity Tracking System
**Implementation Notes:**
- Create activity model to track various business events
- Implement activity creation via model callbacks
- Add polymorphic associations for flexible tracking

```ruby
# app/models/activity.rb
class Activity < ApplicationRecord
  belongs_to :business
  belongs_to :trackable, polymorphic: true, optional: true
  belongs_to :actor, class_name: 'User', optional: true

  validates :action, :description, presence: true

  enum priority: { low: 0, normal: 1, high: 2, urgent: 3 }
  enum category: { 
    booking: 0, 
    customer: 1, 
    staff: 2, 
    system: 3, 
    payment: 4, 
    service: 5,
    business: 6
  }

  scope :recent, -> { order(created_at: :desc) }
  scope :today, -> { where(created_at: Date.current.beginning_of_day..Date.current.end_of_day) }
  scope :for_dashboard, -> { recent.limit(10) }

  def time_ago
    return "just now" if created_at > 1.minute.ago
    return "#{time_ago_in_words(created_at)} ago" if created_at > 1.day.ago
    created_at.strftime("%m/%d at %I:%M %p")
  end

  def icon_class
    case category
    when 'booking'
      'fas fa-calendar-plus'
    when 'customer'
      'fas fa-user'
    when 'staff'
      'fas fa-users'
    when 'system'
      'fas fa-cog'
    when 'payment'
      'fas fa-credit-card'
    when 'service'
      'fas fa-wrench'
    when 'business'
      'fas fa-building'
    else
      'fas fa-info-circle'
    end
  end

  def color_class
    case priority
    when 'urgent'
      'text-red-600'
    when 'high'
      'text-orange-600'
    when 'normal'
      'text-blue-600'
    else
      'text-gray-600'
    end
  end
end

# Migration
# rails g model Activity business:references trackable:polymorphic actor:references action:string description:text category:integer priority:integer metadata:text
class CreateActivities < ActiveRecord::Migration[8.0]
  def change
    create_table :activities do |t|
      t.references :business, null: false, foreign_key: true
      t.references :trackable, polymorphic: true, null: true
      t.references :actor, null: true, foreign_key: { to_table: :users }
      t.string :action, null: false
      t.text :description, null: false
      t.integer :category, default: 0
      t.integer :priority, default: 1
      t.text :metadata
      t.timestamps
    end

    add_index :activities, [:business_id, :created_at]
    add_index :activities, [:business_id, :category]
    add_index :activities, [:trackable_type, :trackable_id]
  end
end
```

### Task 2: Create Activity Tracking Service
**Implementation Notes:**
- Service to create standardized activity records
- Helper methods for common activity types
- Metadata handling for detailed context

```ruby
# app/services/admin/activity_tracking_service.rb
class Admin::ActivityTrackingService
  attr_reader :business

  def initialize(business)
    @business = business
  end

  def track_booking_created(booking, actor = nil)
    create_activity(
      trackable: booking,
      actor: actor,
      action: 'booking_created',
      description: "New booking created for #{booking.customer.name} - #{booking.service.name}",
      category: 'booking',
      priority: 'normal',
      metadata: {
        customer_name: booking.customer.name,
        service_name: booking.service.name,
        scheduled_at: booking.scheduled_at,
        total_amount: booking.total_amount
      }
    )
  end

  def track_booking_cancelled(booking, actor = nil, reason = nil)
    create_activity(
      trackable: booking,
      actor: actor,
      action: 'booking_cancelled',
      description: "Booking cancelled for #{booking.customer.name}#{reason ? " - #{reason}" : ''}",
      category: 'booking',
      priority: 'high',
      metadata: {
        customer_name: booking.customer.name,
        service_name: booking.service.name,
        cancellation_reason: reason,
        cancelled_at: Time.current
      }
    )
  end

  def track_customer_created(customer, actor = nil)
    create_activity(
      trackable: customer,
      actor: actor,
      action: 'customer_created',
      description: "New customer registered: #{customer.name}",
      category: 'customer',
      priority: 'normal',
      metadata: {
        customer_email: customer.email,
        customer_phone: customer.phone
      }
    )
  end

  def track_staff_status_changed(staff_member, actor = nil, status_change = nil)
    create_activity(
      trackable: staff_member,
      actor: actor,
      action: 'staff_status_changed',
      description: "#{staff_member.name} status changed to #{staff_member.status}",
      category: 'staff',
      priority: 'normal',
      metadata: {
        staff_name: staff_member.name,
        new_status: staff_member.status,
        previous_status: status_change&.dig(:from)
      }
    )
  end

  def track_payment_received(payment, actor = nil)
    create_activity(
      trackable: payment,
      actor: actor,
      action: 'payment_received',
      description: "Payment received: #{number_to_currency(payment.amount)} for #{payment.booking.customer.name}",
      category: 'payment',
      priority: 'normal',
      metadata: {
        amount: payment.amount,
        payment_method: payment.payment_method,
        customer_name: payment.booking.customer.name
      }
    )
  end

  def track_service_updated(service, actor = nil, changes = {})
    create_activity(
      trackable: service,
      actor: actor,
      action: 'service_updated',
      description: "Service '#{service.name}' was updated",
      category: 'service',
      priority: 'normal',
      metadata: {
        service_name: service.name,
        changes: changes
      }
    )
  end

  def track_business_setting_changed(setting_name, actor = nil, old_value = nil, new_value = nil)
    create_activity(
      trackable: business,
      actor: actor,
      action: 'business_setting_changed',
      description: "Business setting '#{setting_name.humanize}' was updated",
      category: 'business',
      priority: 'normal',
      metadata: {
        setting_name: setting_name,
        old_value: old_value,
        new_value: new_value
      }
    )
  end

  def track_system_event(event_type, description, priority: 'normal', metadata: {})
    create_activity(
      trackable: nil,
      actor: nil,
      action: event_type,
      description: description,
      category: 'system',
      priority: priority,
      metadata: metadata
    )
  end

  private

  def create_activity(attributes)
    business.activities.create!(attributes)
  rescue StandardError => e
    Rails.logger.error "Failed to create activity: #{e.message}"
    nil
  end

  def number_to_currency(amount)
    ActionController::Base.helpers.number_to_currency(amount)
  end
end
```

### Task 3: Add Activity Tracking to Models
**Implementation Notes:**
- Add callbacks to relevant models
- Use consistent activity tracking patterns
- Handle edge cases and errors gracefully

```ruby
# Add to app/models/booking.rb
class Booking < ApplicationRecord
  # ...existing code...

  after_create :track_creation_activity
  after_update :track_status_change_activity
  before_destroy :track_cancellation_activity

  private

  def track_creation_activity
    Admin::ActivityTrackingService.new(business)
                                  .track_booking_created(self, Current.user)
  end

  def track_status_change_activity
    if saved_change_to_status? && status_previously_changed?
      previous_status = status_before_last_save
      case status
      when 'cancelled'
        Admin::ActivityTrackingService.new(business)
                                      .track_booking_cancelled(self, Current.user, cancellation_reason)
      when 'completed'
        Admin::ActivityTrackingService.new(business)
                                      .track_system_event(
                                        'booking_completed',
                                        "Booking completed for #{customer.name}",
                                        priority: 'normal',
                                        metadata: { 
                                          customer_name: customer.name,
                                          service_name: service.name
                                        }
                                      )
      end
    end
  end

  def track_cancellation_activity
    Admin::ActivityTrackingService.new(business)
                                  .track_booking_cancelled(self, Current.user, "Booking deleted")
  end
end

# Add to app/models/customer.rb
class Customer < ApplicationRecord
  # ...existing code...

  after_create :track_creation_activity

  private

  def track_creation_activity
    Admin::ActivityTrackingService.new(business)
                                  .track_customer_created(self, Current.user)
  end
end

# Add to app/models/staff_member.rb (or User model for staff)
class StaffMember < ApplicationRecord
  # ...existing code...

  after_update :track_status_changes

  private

  def track_status_changes
    if saved_change_to_status?
      Admin::ActivityTrackingService.new(business)
                                    .track_staff_status_changed(
                                      self, 
                                      Current.user,
                                      { from: status_before_last_save, to: status }
                                    )
    end
  end
end
```

### Task 4: Create Recent Activity Widget View
**Implementation Notes:**
- Timeline-style layout for activities
- Real-time updates capability
- Filtering and pagination support

```erb
<!-- app/views/admin/dashboard/widgets/_recent_activity.html.erb -->
<div 
  class="col-span-1 md:col-span-2 bg-white rounded-lg shadow p-6"
  data-widget="recent_activity"
  data-widget-refresh="true"
  data-controller="recent-activity"
>
  <div class="flex items-center justify-between mb-6">
    <h3 class="text-lg font-medium text-gray-900">Recent Activity</h3>
    <div class="flex items-center space-x-2">
      <select 
        class="text-sm border-gray-300 rounded-md"
        data-action="change->recent-activity#filterActivities"
        data-recent-activity-target="categoryFilter"
      >
        <option value="">All Activities</option>
        <option value="booking">Bookings</option>
        <option value="customer">Customers</option>
        <option value="staff">Staff</option>
        <option value="payment">Payments</option>
        <option value="system">System</option>
      </select>
      <button 
        class="text-sm text-blue-600 hover:text-blue-800"
        data-action="click->recent-activity#refreshActivities"
      >
        <i class="fas fa-refresh mr-1"></i>
        Refresh
      </button>
    </div>
  </div>

  <div class="space-y-4" data-recent-activity-target="activitiesList">
    <% 
      activities = current_admin.business.activities
                                        .includes(:actor, :trackable)
                                        .for_dashboard
    %>
    
    <% if activities.any? %>
      <% activities.each do |activity| %>
        <div class="activity-item flex items-start space-x-3 p-3 rounded-lg hover:bg-gray-50 transition-colors duration-150" 
             data-category="<%= activity.category %>"
             data-priority="<%= activity.priority %>">
          
          <!-- Activity Icon -->
          <div class="flex-shrink-0">
            <div class="w-8 h-8 rounded-full bg-gray-100 flex items-center justify-center">
              <i class="<%= activity.icon_class %> text-sm <%= activity.color_class %>"></i>
            </div>
          </div>
          
          <!-- Activity Content -->
          <div class="flex-1 min-w-0">
            <div class="flex items-start justify-between">
              <div class="flex-1">
                <p class="text-sm text-gray-900 font-medium">
                  <%= activity.description %>
                </p>
                
                <div class="flex items-center mt-1 text-xs text-gray-500 space-x-2">
                  <span class="capitalize px-2 py-1 bg-gray-100 rounded-full">
                    <%= activity.category.humanize %>
                  </span>
                  
                  <% if activity.actor %>
                    <span>by <%= activity.actor.name %></span>
                  <% end %>
                  
                  <span><%= activity.time_ago %></span>
                </div>
                
                <!-- Additional Details for High Priority -->
                <% if activity.priority.in?(['high', 'urgent']) %>
                  <div class="mt-2 p-2 bg-yellow-50 border border-yellow-200 rounded text-xs">
                    <div class="flex items-center">
                      <i class="fas fa-exclamation-triangle text-yellow-600 mr-1"></i>
                      <span class="text-yellow-800 font-medium">
                        <%= activity.priority.humanize %> Priority Activity
                      </span>
                    </div>
                  </div>
                <% end %>
              </div>
              
              <!-- Action Link -->
              <% if activity.trackable && activity.trackable.respond_to?(:to_param) %>
                <div class="flex-shrink-0 ml-2">
                  <%= link_to polymorphic_path([:admin, activity.trackable]),
                             class: "text-blue-600 hover:text-blue-800 text-xs" do %>
                    View <i class="fas fa-external-link-alt ml-1"></i>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>
    <% else %>
      <div class="text-center py-8 text-gray-500">
        <i class="fas fa-clock text-3xl mb-2"></i>
        <p>No recent activity</p>
        <p class="text-sm">Activities will appear here as they happen</p>
      </div>
    <% end %>
  </div>

  <!-- View All Link -->
  <% if activities.count >= 10 %>
    <div class="mt-6 text-center">
      <%= link_to admin_activities_path, 
                  class: "text-blue-600 hover:text-blue-800 text-sm font-medium" do %>
        View All Activities
        <i class="fas fa-arrow-right ml-1"></i>
      <% end %>
    </div>
  <% end %>

  <!-- Loading Indicator -->
  <div class="hidden text-center py-4" data-recent-activity-target="loadingIndicator">
    <i class="fas fa-spinner fa-spin text-gray-400"></i>
    <span class="ml-2 text-sm text-gray-500">Loading activities...</span>
  </div>
</div>
```

### Task 5: Create Recent Activity Stimulus Controller
**Implementation Notes:**
- Real-time filtering functionality
- AJAX refresh capability
- Smooth animations for updates

```javascript
// app/javascript/controllers/recent_activity_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["activitiesList", "categoryFilter", "loadingIndicator"]

  connect() {
    this.originalActivities = Array.from(this.activitiesListTarget.children)
  }

  filterActivities() {
    const selectedCategory = this.categoryFilterTarget.value
    const activities = this.activitiesListTarget.querySelectorAll('.activity-item')
    
    activities.forEach(activity => {
      const category = activity.dataset.category
      
      if (!selectedCategory || category === selectedCategory) {
        activity.style.display = 'flex'
        activity.classList.remove('hidden')
      } else {
        activity.style.display = 'none'
        activity.classList.add('hidden')
      }
    })

    // Show message if no activities match filter
    this.toggleEmptyState()
  }

  refreshActivities() {
    this.showLoading()
    
    fetch('/admin/dashboard/widget_data?widget_type=recent_activity', {
      headers: {
        'Accept': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      }
    })
    .then(response => response.json())
    .then(data => {
      this.updateActivitiesList(data.activities)
      this.hideLoading()
    })
    .catch(error => {
      console.error('Failed to refresh activities:', error)
      this.hideLoading()
      this.showError('Failed to refresh activities')
    })
  }

  updateActivitiesList(activities) {
    // Create new activity elements
    const newActivitiesHTML = activities.map(activity => 
      this.createActivityHTML(activity)
    ).join('')
    
    // Fade out current list
    this.activitiesListTarget.style.opacity = '0.5'
    
    setTimeout(() => {
      this.activitiesListTarget.innerHTML = newActivitiesHTML
      this.activitiesListTarget.style.opacity = '1'
      
      // Reapply current filter
      this.filterActivities()
    }, 200)
  }

  createActivityHTML(activity) {
    return `
      <div class="activity-item flex items-start space-x-3 p-3 rounded-lg hover:bg-gray-50 transition-colors duration-150" 
           data-category="${activity.category}"
           data-priority="${activity.priority}">
        
        <div class="flex-shrink-0">
          <div class="w-8 h-8 rounded-full bg-gray-100 flex items-center justify-center">
            <i class="${activity.icon_class} text-sm ${activity.color_class}"></i>
          </div>
        </div>
        
        <div class="flex-1 min-w-0">
          <div class="flex items-start justify-between">
            <div class="flex-1">
              <p class="text-sm text-gray-900 font-medium">
                ${activity.description}
              </p>
              
              <div class="flex items-center mt-1 text-xs text-gray-500 space-x-2">
                <span class="capitalize px-2 py-1 bg-gray-100 rounded-full">
                  ${activity.category_display}
                </span>
                
                ${activity.actor_name ? `<span>by ${activity.actor_name}</span>` : ''}
                
                <span>${activity.time_ago}</span>
              </div>
              
              ${activity.priority_high ? this.createHighPriorityHTML(activity) : ''}
            </div>
            
            ${activity.view_url ? this.createViewLinkHTML(activity.view_url) : ''}
          </div>
        </div>
      </div>
    `
  }

  createHighPriorityHTML(activity) {
    return `
      <div class="mt-2 p-2 bg-yellow-50 border border-yellow-200 rounded text-xs">
        <div class="flex items-center">
          <i class="fas fa-exclamation-triangle text-yellow-600 mr-1"></i>
          <span class="text-yellow-800 font-medium">
            ${activity.priority_display} Priority Activity
          </span>
        </div>
      </div>
    `
  }

  createViewLinkHTML(url) {
    return `
      <div class="flex-shrink-0 ml-2">
        <a href="${url}" class="text-blue-600 hover:text-blue-800 text-xs">
          View <i class="fas fa-external-link-alt ml-1"></i>
        </a>
      </div>
    `
  }

  toggleEmptyState() {
    const visibleActivities = this.activitiesListTarget.querySelectorAll('.activity-item:not(.hidden)')
    
    if (visibleActivities.length === 0) {
      this.showEmptyState()
    } else {
      this.hideEmptyState()
    }
  }

  showEmptyState() {
    const emptyState = this.activitiesListTarget.querySelector('.empty-state')
    if (!emptyState) {
      const emptyHTML = `
        <div class="empty-state text-center py-8 text-gray-500">
          <i class="fas fa-filter text-3xl mb-2"></i>
          <p>No activities match the current filter</p>
          <p class="text-sm">Try selecting a different category</p>
        </div>
      `
      this.activitiesListTarget.insertAdjacentHTML('beforeend', emptyHTML)
    }
  }

  hideEmptyState() {
    const emptyState = this.activitiesListTarget.querySelector('.empty-state')
    if (emptyState) {
      emptyState.remove()
    }
  }

  showLoading() {
    this.loadingIndicatorTarget.classList.remove('hidden')
    this.activitiesListTarget.style.opacity = '0.5'
  }

  hideLoading() {
    this.loadingIndicatorTarget.classList.add('hidden')
    this.activitiesListTarget.style.opacity = '1'
  }

  showError(message) {
    // Simple error notification
    const notification = document.createElement('div')
    notification.className = 'fixed top-4 right-4 bg-red-500 text-white px-4 py-2 rounded shadow-lg z-50'
    notification.textContent = message
    
    document.body.appendChild(notification)
    
    setTimeout(() => {
      notification.remove()
    }, 5000)
  }
}
```

### Task 6: Add Activity Data to Dashboard Controller
**Implementation Notes:**
- Extend dashboard controller to serve activity data
- Format data for JavaScript consumption
- Include proper error handling

```ruby
# Add to app/controllers/admin/dashboard_controller.rb

def widget_data
  widget_type = params[:widget_type]
  
  case widget_type
  when 'metrics'
    # ...existing metrics code...
  when 'recent_activity'
    activities = current_admin.business.activities
                                      .includes(:actor, :trackable)
                                      .for_dashboard
    
    render json: {
      activities: activities.map do |activity|
        {
          id: activity.id,
          description: activity.description,
          category: activity.category,
          category_display: activity.category.humanize,
          priority: activity.priority,
          priority_display: activity.priority.humanize,
          priority_high: activity.priority.in?(['high', 'urgent']),
          icon_class: activity.icon_class,
          color_class: activity.color_class,
          time_ago: activity.time_ago,
          actor_name: activity.actor&.name,
          view_url: activity.trackable ? polymorphic_path([:admin, activity.trackable]) : nil
        }
      end
    }
  else
    render json: { error: 'Unknown widget type' }, status: :unprocessable_entity
  end
rescue StandardError => e
  Rails.logger.error "Dashboard widget error: #{e.message}"
  render json: { error: 'Unable to fetch widget data' }, status: :internal_server_error
end
```

## Acceptance Criteria
- [ ] Activities are tracked automatically for key business events
- [ ] Real-time filtering by category works smoothly
- [ ] Activity timeline displays in chronological order
- [ ] High priority activities are visually highlighted
- [ ] Refresh functionality updates data without page reload
- [ ] Mobile layout displays activities clearly
- [ ] Links to related records work correctly

## Testing Requirements
- Unit tests for Activity model and ActivityTrackingService
- Integration tests for activity creation triggers
- JavaScript functionality testing for filtering and refresh
- Performance tests for activity queries
- Mobile responsiveness testing
