# Feature: Recent Activity Feed

## Overview
Create a real-time activity feed that displays recent business activities, system events, and important notifications to keep users informed of what's happening across their business.

## User Stories
- As a business owner, I want to see recent business activities so I can stay informed about operations
- As a staff member, I want to see activities relevant to my role and responsibilities
- As a manager, I want to monitor team activities and system events

## Tasks

### 1. Create Activity Feed Service
**File**: `app/services/activity_feed_service.rb`

**Implementation Notes**:
```ruby
class ActivityFeedService
  def initialize(business, user, options = {})
    @business = business
    @user = user
    @business_user = user.business_users.find_by(business: business)
    @limit = options[:limit] || 20
    @filter = options[:filter] || 'all'
  end
  
  def recent_activities
    activities = base_activity_query
    activities = apply_filters(activities)
    activities = apply_permissions(activities)
    
    activities.recent
             .includes(:user, :trackable)
             .limit(@limit)
             .map { |activity| format_activity(activity) }
  end
  
  def activity_summary
    {
      total_activities: total_activities_count,
      activities_by_type: activities_by_type_count,
      most_active_users: most_active_users,
      peak_activity_hours: peak_activity_hours
    }
  end
  
  def real_time_updates(since:)
    base_activity_query
      .where('occurred_at > ?', since)
      .recent
      .includes(:user, :trackable)
      .limit(10)
      .map { |activity| format_activity(activity) }
  end
  
  private
  
  def base_activity_query
    ActivityLog.where(business: @business)
  end
  
  def apply_filters(activities)
    case @filter
    when 'quotes'
      activities.where(action: ['quote_created', 'quote_updated', 'quote_sent', 'quote_approved', 'quote_rejected'])
    when 'jobs'
      activities.where(action: ['appointment_scheduled', 'appointment_updated', 'appointment_completed', 'appointment_cancelled'])
    when 'payments'
      activities.where(action: ['payment_processed', 'payment_failed', 'invoice_sent'])
    when 'customers'
      activities.where(action: ['customer_contacted', 'quote_created', 'appointment_scheduled'])
    when 'system'
      activities.where(action: ['login', 'logout', 'settings_updated'])
    when 'my_activities'
      activities.where(user: @user)
    else
      activities.business_activities
    end
  end
  
  def apply_permissions(activities)
    # Filter activities based on user permissions
    unless @business_user&.can_view_all_quotes?
      # Restrict to user's own activities or public activities
      activities = activities.where(
        'user_id = ? OR action IN (?)', 
        @user.id, 
        public_activity_types
      )
    end
    
    activities
  end
  
  def public_activity_types
    %w[appointment_completed payment_received settings_updated]
  end
  
  def format_activity(activity)
    {
      id: activity.id,
      type: activity.action,
      title: activity_title(activity),
      description: activity_description(activity),
      user: {
        name: activity.user.name,
        avatar_url: activity.user.avatar.attached? ? activity.user.avatar : nil
      },
      timestamp: activity.occurred_at,
      trackable: format_trackable(activity.trackable),
      details: activity.details,
      icon: activity_icon(activity.action),
      color: activity_color(activity.action),
      url: activity_url(activity)
    }
  end
  
  def activity_title(activity)
    case activity.action
    when 'quote_created'
      "New quote created"
    when 'quote_sent'
      "Quote sent to customer"
    when 'quote_approved'
      "Quote approved by customer"
    when 'quote_rejected'
      "Quote declined by customer"
    when 'appointment_scheduled'
      "Job scheduled"
    when 'appointment_completed'
      "Job completed"
    when 'appointment_cancelled'
      "Job cancelled"
    when 'payment_processed'
      "Payment received"
    when 'payment_failed'
      "Payment failed"
    when 'customer_contacted'
      "Customer contacted"
    when 'settings_updated'
      "Business settings updated"
    when 'login'
      "User signed in"
    when 'logout'
      "User signed out"
    else
      activity.action.humanize
    end
  end
  
  def activity_description(activity)
    case activity.action
    when 'quote_created', 'quote_sent', 'quote_approved', 'quote_rejected'
      if activity.trackable
        "Quote ##{activity.trackable.quote_number} for #{activity.trackable.customer_name}"
      else
        "Quote details not available"
      end
    when 'appointment_scheduled', 'appointment_completed', 'appointment_cancelled'
      if activity.trackable
        "#{activity.trackable.service_name} on #{activity.trackable.scheduled_date.strftime('%m/%d/%Y')}"
      else
        "Job details not available"
      end
    when 'payment_processed'
      if activity.trackable
        "#{number_to_currency(activity.trackable.amount)} payment received"
      else
        "Payment amount not available"
      end
    when 'customer_contacted'
      activity.details['customer_name'] || "Customer contact"
    when 'settings_updated'
      activity.details['section'] ? "#{activity.details['section'].humanize} settings" : "Business settings"
    else
      activity.details['description'] || ""
    end
  end
  
  def format_trackable(trackable)
    return nil unless trackable
    
    {
      type: trackable.class.name,
      id: trackable.id,
      display_name: trackable_display_name(trackable)
    }
  end
  
  def trackable_display_name(trackable)
    case trackable.class.name
    when 'Quote'
      "Quote ##{trackable.quote_number}"
    when 'Appointment'
      "Job - #{trackable.service_name}"
    when 'Payment'
      "Payment - #{number_to_currency(trackable.amount)}"
    when 'Customer'
      trackable.name
    else
      trackable.to_s
    end
  end
  
  def activity_icon(action)
    {
      'quote_created' => 'document-plus',
      'quote_sent' => 'mail',
      'quote_approved' => 'check-circle',
      'quote_rejected' => 'x-circle',
      'appointment_scheduled' => 'calendar',
      'appointment_completed' => 'check',
      'appointment_cancelled' => 'x',
      'payment_processed' => 'currency-dollar',
      'payment_failed' => 'exclamation-triangle',
      'customer_contacted' => 'phone',
      'settings_updated' => 'cog',
      'login' => 'login',
      'logout' => 'logout'
    }[action] || 'information-circle'
  end
  
  def activity_color(action)
    {
      'quote_created' => 'blue',
      'quote_sent' => 'blue',
      'quote_approved' => 'green',
      'quote_rejected' => 'red',
      'appointment_scheduled' => 'purple',
      'appointment_completed' => 'green',
      'appointment_cancelled' => 'red',
      'payment_processed' => 'green',
      'payment_failed' => 'red',
      'customer_contacted' => 'yellow',
      'settings_updated' => 'gray',
      'login' => 'gray',
      'logout' => 'gray'
    }[action] || 'gray'
  end
  
  def activity_url(activity)
    return nil unless activity.trackable
    
    case activity.trackable.class.name
    when 'Quote'
      Rails.application.routes.url_helpers.admin_quote_path(activity.trackable)
    when 'Appointment'
      Rails.application.routes.url_helpers.admin_appointment_path(activity.trackable)
    when 'Payment'
      Rails.application.routes.url_helpers.admin_payment_path(activity.trackable)
    when 'Customer'
      Rails.application.routes.url_helpers.admin_customer_path(activity.trackable)
    else
      nil
    end
  rescue
    nil
  end
  
  def total_activities_count
    base_activity_query.business_activities.count
  end
  
  def activities_by_type_count
    base_activity_query.business_activities
                       .group(:action)
                       .count
                       .transform_keys(&:humanize)
  end
  
  def most_active_users
    base_activity_query.business_activities
                       .joins(:user)
                       .group('users.name')
                       .count
                       .sort_by { |_, count| -count }
                       .first(5)
                       .to_h
  end
  
  def peak_activity_hours
    base_activity_query.business_activities
                       .group("EXTRACT(hour FROM occurred_at)")
                       .count
                       .transform_keys { |hour| "#{hour.to_i}:00" }
                       .sort_by { |_, count| -count }
                       .first(3)
                       .to_h
  end
  
  private
  
  def number_to_currency(amount)
    ActionController::Base.helpers.number_to_currency(amount)
  end
end
```

### 2. Create Activity Feed Component
**File**: `app/components/activity_feed_component.rb`

**Implementation Notes**:
```ruby
class ActivityFeedComponent < ViewComponent::Base
  def initialize(business:, user:, options: {})
    @business = business
    @user = user
    @options = options
    @feed_service = ActivityFeedService.new(business, user, options)
  end
  
  private
  
  attr_reader :business, :user, :options, :feed_service
  
  def activities
    @activities ||= feed_service.recent_activities
  end
  
  def activity_summary
    @activity_summary ||= feed_service.activity_summary
  end
  
  def icon_path(icon_name)
    case icon_name
    when 'document-plus'
      'M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z'
    when 'mail'
      'M3 8l7.89 4.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z'
    when 'check-circle'
      'M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z'
    when 'x-circle'
      'M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z'
    when 'calendar'
      'M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z'
    when 'check'
      'M5 13l4 4L19 7'
    when 'currency-dollar'
      'M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1'
    when 'phone'
      'M3 5a2 2 0 012-2h3.28a1 1 0 01.948.684l1.498 4.493a1 1 0 01-.502 1.21l-2.257 1.13a11.042 11.042 0 005.516 5.516l1.13-2.257a1 1 0 011.21-.502l4.493 1.498a1 1 0 01.684.949V19a2 2 0 01-2 2h-1C9.716 21 3 14.284 3 6V5z'
    when 'cog'
      'M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z'
    else
      'M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z'
    end
  end
  
  def color_classes(color)
    {
      'blue' => { bg: 'bg-blue-100', icon: 'text-blue-600', border: 'border-blue-200' },
      'green' => { bg: 'bg-green-100', icon: 'text-green-600', border: 'border-green-200' },
      'red' => { bg: 'bg-red-100', icon: 'text-red-600', border: 'border-red-200' },
      'purple' => { bg: 'bg-purple-100', icon: 'text-purple-600', border: 'border-purple-200' },
      'yellow' => { bg: 'bg-yellow-100', icon: 'text-yellow-600', border: 'border-yellow-200' },
      'gray' => { bg: 'bg-gray-100', icon: 'text-gray-600', border: 'border-gray-200' }
    }[color] || color_classes('gray')
  end
  
  def relative_time(timestamp)
    time_ago_in_words(timestamp)
  end
  
  def filter_options
    [
      ['All Activities', 'all'],
      ['Quotes', 'quotes'],
      ['Jobs', 'jobs'],
      ['Payments', 'payments'],
      ['Customers', 'customers'],
      ['My Activities', 'my_activities'],
      ['System', 'system']
    ]
  end
end
```

### 3. Create Activity Feed View Template
**File**: `app/components/activity_feed_component.html.erb`

**Implementation Notes**:
```erb
<div class="bg-white shadow rounded-lg">
  <div class="px-6 py-4 border-b border-gray-200">
    <div class="flex items-center justify-between">
      <h3 class="text-lg font-medium text-gray-900">Recent Activity</h3>
      
      <!-- Activity Filter -->
      <div class="flex items-center space-x-3">
        <%= form_with url: admin_dashboard_path, method: :get, local: true, class: "inline" do |form| %>
          <%= form.select :activity_filter, 
                         filter_options, 
                         { selected: options[:filter] || 'all' },
                         { class: "text-sm border-gray-300 rounded-md focus:ring-blue-500 focus:border-blue-500",
                           onchange: "this.form.submit();" } %>
        <% end %>
        
        <!-- Refresh Button -->
        <button type="button" 
                class="text-gray-400 hover:text-gray-600 transition-colors"
                data-action="click->activity-feed#refresh"
                title="Refresh">
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
          </svg>
        </button>
      </div>
    </div>
  </div>
  
  <div class="p-6">
    <% if activities.any? %>
      <!-- Activity Timeline -->
      <div class="flow-root" data-activity-feed-target="timeline">
        <ul class="-mb-8">
          <% activities.each_with_index do |activity, index| %>
            <% colors = color_classes(activity[:color]) %>
            
            <li>
              <div class="relative pb-8">
                <!-- Timeline connector line (except for last item) -->
                <% unless index == activities.length - 1 %>
                  <span class="absolute top-5 left-5 -ml-px h-full w-0.5 bg-gray-200" aria-hidden="true"></span>
                <% end %>
                
                <div class="relative flex items-start space-x-3">
                  <!-- Activity Icon -->
                  <div class="relative">
                    <div class="h-10 w-10 rounded-full <%= colors[:bg] %> flex items-center justify-center ring-8 ring-white">
                      <svg class="h-5 w-5 <%= colors[:icon] %>" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="<%= icon_path(activity[:icon]) %>" />
                      </svg>
                    </div>
                  </div>
                  
                  <!-- Activity Content -->
                  <div class="min-w-0 flex-1">
                    <div class="border border-gray-200 rounded-lg p-4 hover:bg-gray-50 transition-colors">
                      <div class="flex items-center justify-between">
                        <div class="flex items-center space-x-2">
                          <p class="text-sm font-medium text-gray-900">
                            <%= activity[:title] %>
                          </p>
                          <% if activity[:trackable] %>
                            <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800">
                              <%= activity[:trackable][:type] %>
                            </span>
                          <% end %>
                        </div>
                        <time class="text-xs text-gray-500" datetime="<%= activity[:timestamp].iso8601 %>">
                          <%= relative_time(activity[:timestamp]) %> ago
                        </time>
                      </div>
                      
                      <div class="mt-2">
                        <p class="text-sm text-gray-600">
                          <%= activity[:description] %>
                        </p>
                        
                        <!-- User Attribution -->
                        <div class="flex items-center mt-2 space-x-2">
                          <div class="flex-shrink-0">
                            <% if activity[:user][:avatar_url] %>
                              <img class="h-6 w-6 rounded-full" src="<%= activity[:user][:avatar_url] %>" alt="<%= activity[:user][:name] %>">
                            <% else %>
                              <div class="h-6 w-6 rounded-full bg-gray-300 flex items-center justify-center">
                                <span class="text-xs font-medium text-gray-700">
                                  <%= activity[:user][:name].first.upcase %>
                                </span>
                              </div>
                            <% end %>
                          </div>
                          <span class="text-xs text-gray-500">by <%= activity[:user][:name] %></span>
                          
                          <!-- Action Link -->
                          <% if activity[:url] %>
                            <%= link_to "View", activity[:url], 
                                        class: "text-xs text-blue-600 hover:text-blue-800 ml-auto" %>
                          <% end %>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </li>
          <% end %>
        </ul>
      </div>
      
      <!-- Load More Button -->
      <div class="mt-6 text-center">
        <button type="button" 
                class="text-sm text-gray-500 hover:text-gray-700 transition-colors"
                data-action="click->activity-feed#loadMore">
          Load More Activities
        </button>
      </div>
      
    <% else %>
      <!-- Empty State -->
      <div class="text-center py-8">
        <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"/>
        </svg>
        <p class="text-sm text-gray-500 mt-2">No recent activity</p>
        <p class="text-xs text-gray-400">Activities will appear here as they happen</p>
      </div>
    <% end %>
  </div>
  
  <!-- Activity Summary Footer -->
  <div class="bg-gray-50 px-6 py-3 border-t border-gray-200">
    <div class="flex items-center justify-between text-xs text-gray-500">
      <span><%= activity_summary[:total_activities] %> total activities</span>
      <div class="flex items-center space-x-4">
        <span>Most active: <%= activity_summary[:most_active_users].first&.first || 'N/A' %></span>
        <span>Peak hour: <%= activity_summary[:peak_activity_hours].first&.first || 'N/A' %></span>
      </div>
    </div>
  </div>
</div>

<script data-turbo-track="reload">
  // Stimulus controller for Activity Feed
  class ActivityFeedController extends Stimulus.Controller {
    static targets = ["timeline"]
    
    connect() {
      // Set up auto-refresh every 30 seconds
      this.refreshInterval = setInterval(() => {
        this.refresh();
      }, 30000);
    }
    
    disconnect() {
      if (this.refreshInterval) {
        clearInterval(this.refreshInterval);
      }
    }
    
    refresh() {
      // Fetch latest activities via AJAX
      const currentFilter = new URLSearchParams(window.location.search).get('activity_filter') || 'all';
      
      fetch(`${window.location.pathname}?activity_filter=${currentFilter}&format=json`, {
        headers: {
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })
      .then(response => response.json())
      .then(data => {
        if (data.activities && data.activities.length > 0) {
          this.updateTimeline(data.activities);
        }
      })
      .catch(error => {
        console.error('Failed to refresh activities:', error);
      });
    }
    
    loadMore() {
      // Implementation for loading more activities
      const timeline = this.timelineTarget;
      const lastActivityId = timeline.querySelector('li:last-child')?.dataset.activityId;
      
      if (lastActivityId) {
        const currentFilter = new URLSearchParams(window.location.search).get('activity_filter') || 'all';
        
        fetch(`${window.location.pathname}?activity_filter=${currentFilter}&before=${lastActivityId}&format=json`)
        .then(response => response.json())
        .then(data => {
          if (data.activities && data.activities.length > 0) {
            this.appendActivities(data.activities);
          }
        })
        .catch(error => {
          console.error('Failed to load more activities:', error);
        });
      }
    }
    
    updateTimeline(activities) {
      // Add new activities to the top of the timeline
      // This would require more complex DOM manipulation
      // For now, just show a simple notification
      this.showNotification(`${activities.length} new activities`);
    }
    
    appendActivities(activities) {
      // Add activities to the bottom of the timeline
      // Implementation would involve creating and appending DOM elements
    }
    
    showNotification(message) {
      // Simple notification - could be enhanced with a toast component
      const notification = document.createElement('div');
      notification.className = 'fixed top-4 right-4 bg-blue-500 text-white px-4 py-2 rounded-md shadow-lg z-50';
      notification.textContent = message;
      document.body.appendChild(notification);
      
      setTimeout(() => {
        notification.remove();
      }, 3000);
    }
  }
  
  Stimulus.register("activity-feed", ActivityFeedController);
</script>
```

### 4. Create Shared Recent Activity Partial
**File**: `app/views/shared/_recent_activity_feed.html.erb`

**Implementation Notes**:
```erb
<%= render ActivityFeedComponent.new(
      business: @business,
      user: current_user,
      options: { 
        filter: params[:activity_filter] || 'all',
        limit: 15
      }
    ) %>
```

### 5. Update Dashboard Controller for Real-time Updates
**File**: Enhancement to `app/controllers/admin/dashboard_controller.rb`

**Implementation Notes**:
```ruby
class Admin::DashboardController < Admin::BaseController
  # ...existing code...
  
  def index
    # ...existing code...
    
    respond_to do |format|
      format.html
      format.json { render json: activity_feed_json }
    end
  end
  
  private
  
  # ...existing code...
  
  def activity_feed_json
    feed_service = ActivityFeedService.new(@business, current_user, {
      filter: params[:activity_filter] || 'all',
      limit: params[:limit] || 15
    })
    
    {
      activities: feed_service.recent_activities,
      summary: feed_service.activity_summary,
      timestamp: Time.current.iso8601
    }
  end
end
```

## Acceptance Criteria
- [ ] Displays recent business activities in chronological order
- [ ] Shows role-appropriate activities based on user permissions
- [ ] Provides filtering options for different activity types
- [ ] Updates automatically every 30 seconds with new activities
- [ ] Includes user attribution and timestamps for all activities
- [ ] Provides links to related objects when applicable
- [ ] Shows activity summary statistics
- [ ] Handles empty states gracefully
- [ ] Load more functionality works correctly
- [ ] Real-time updates work without full page refresh

## Testing Requirements
- Service tests for activity feed filtering and formatting
- Component tests for activity display
- Controller tests for JSON API responses
- JavaScript tests for auto-refresh functionality
- Permission tests for activity visibility
- Performance tests for activity queries with large datasets
