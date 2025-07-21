# Feature: Staff Activity Tracking

## Overview
Provide business owners and managers with visibility into staff activities, login patterns, and key performance metrics for better team management.

## User Stories
- As a business owner, I want to see staff activity so I can understand team productivity
- As a manager, I want to track staff performance metrics for reviews and scheduling
- As a staff member, I want to see my own activity summary

## Tasks

### 1. Create ActivityLog Model
**File**: `app/models/activity_log.rb`

**Implementation Notes**:
```ruby
class ActivityLog < ApplicationRecord
  belongs_to :user
  belongs_to :business
  belongs_to :trackable, polymorphic: true, optional: true
  
  validates :action, presence: true
  validates :occurred_at, presence: true
  
  enum action: {
    login: 0,
    logout: 1,
    quote_created: 10,
    quote_updated: 11,
    quote_sent: 12,
    appointment_scheduled: 20,
    appointment_updated: 21,
    appointment_completed: 22,
    payment_processed: 30,
    customer_contacted: 40,
    settings_updated: 50
  }
  
  scope :recent, -> { order(occurred_at: :desc) }
  scope :for_date_range, ->(start_date, end_date) {
    where(occurred_at: start_date.beginning_of_day..end_date.end_of_day)
  }
  scope :for_user, ->(user) { where(user: user) }
  scope :business_activities, -> { where(action: [:quote_created, :quote_updated, :quote_sent, :appointment_scheduled, :appointment_updated, :appointment_completed, :payment_processed]) }
  
  def action_description
    case action
    when 'login'
      'Signed in'
    when 'logout'
      'Signed out'
    when 'quote_created'
      "Created quote #{trackable&.id || 'N/A'}"
    when 'quote_sent'
      "Sent quote #{trackable&.id || 'N/A'}"
    when 'appointment_scheduled'
      "Scheduled appointment #{trackable&.id || 'N/A'}"
    when 'payment_processed'
      "Processed payment #{trackable&.id || 'N/A'}"
    else
      action.humanize
    end
  end
  
  def self.log_activity(user:, business:, action:, trackable: nil, details: nil)
    create!(
      user: user,
      business: business,
      action: action,
      trackable: trackable,
      details: details,
      occurred_at: Time.current
    )
  rescue => e
    Rails.logger.error "Failed to log activity: #{e.message}"
  end
end
```

### 2. Create StaffMetrics Service
**File**: `app/services/staff_metrics_service.rb`

**Implementation Notes**:
```ruby
class StaffMetricsService
  def initialize(business_user, date_range = 30.days.ago..Time.current)
    @business_user = business_user
    @user = business_user.user
    @business = business_user.business
    @date_range = date_range
  end
  
  def activity_summary
    {
      total_activities: total_activities_count,
      quotes_created: quotes_created_count,
      appointments_scheduled: appointments_scheduled_count,
      payments_processed: payments_processed_count,
      login_days: unique_login_days,
      average_daily_activities: average_daily_activities,
      most_active_day: most_active_day,
      recent_activities: recent_activities(10)
    }
  end
  
  def performance_metrics
    {
      quote_conversion_rate: calculate_quote_conversion_rate,
      average_quote_value: calculate_average_quote_value,
      appointments_completed: appointments_completed_count,
      customer_satisfaction: calculate_customer_satisfaction,
      response_time: calculate_average_response_time
    }
  end
  
  def weekly_activity_chart_data
    weeks = []
    current_week = @date_range.begin.beginning_of_week
    
    while current_week <= @date_range.end
      week_end = [current_week.end_of_week, @date_range.end].min
      week_activities = activity_logs.where(occurred_at: current_week..week_end).count
      
      weeks << {
        week: current_week.strftime("Week of %b %d"),
        activities: week_activities
      }
      
      current_week += 1.week
    end
    
    weeks
  end
  
  def daily_login_pattern
    activity_logs.where(action: 'login')
                 .group("EXTRACT(hour FROM occurred_at)")
                 .count
                 .transform_keys { |hour| "#{hour.to_i}:00" }
  end
  
  private
  
  def activity_logs
    @activity_logs ||= ActivityLog.where(
      user: @user,
      business: @business,
      occurred_at: @date_range
    )
  end
  
  def total_activities_count
    activity_logs.business_activities.count
  end
  
  def quotes_created_count
    activity_logs.where(action: 'quote_created').count
  end
  
  def appointments_scheduled_count
    activity_logs.where(action: 'appointment_scheduled').count
  end
  
  def payments_processed_count
    activity_logs.where(action: 'payment_processed').count
  end
  
  def appointments_completed_count
    activity_logs.where(action: 'appointment_completed').count
  end
  
  def unique_login_days
    activity_logs.where(action: 'login')
                 .group("DATE(occurred_at)")
                 .count
                 .keys
                 .size
  end
  
  def average_daily_activities
    days_in_range = (@date_range.end.to_date - @date_range.begin.to_date).to_i + 1
    return 0 if days_in_range == 0
    
    (total_activities_count.to_f / days_in_range).round(1)
  end
  
  def most_active_day
    daily_counts = activity_logs.business_activities
                               .group("EXTRACT(dow FROM occurred_at)")
                               .count
    
    return nil if daily_counts.empty?
    
    most_active_dow = daily_counts.max_by { |_, count| count }.first
    Date::DAYNAMES[most_active_dow.to_i]
  end
  
  def recent_activities(limit = 10)
    activity_logs.recent.limit(limit).includes(:trackable)
  end
  
  def calculate_quote_conversion_rate
    quotes_sent = activity_logs.where(action: 'quote_sent').count
    return 0 if quotes_sent == 0
    
    # This would need to be connected to actual quote acceptance data
    # For now, using a simplified calculation
    quotes_created = quotes_created_count
    return 0 if quotes_created == 0
    
    ((quotes_sent.to_f / quotes_created) * 100).round(1)
  end
  
  def calculate_average_quote_value
    # This would need to be connected to actual quote data
    # Placeholder calculation
    0
  end
  
  def calculate_customer_satisfaction
    # This would need to be connected to customer feedback data
    # Placeholder calculation
    0
  end
  
  def calculate_average_response_time
    # This would need to be connected to communication timestamps
    # Placeholder calculation
    0
  end
end
```

### 3. Activity Tracking Controller
**File**: `app/controllers/admin/activity_tracking_controller.rb`

**Implementation Notes**:
```ruby
class Admin::ActivityTrackingController < Admin::BaseController
  before_action :set_business
  before_action :ensure_can_view_activity
  before_action :set_date_range
  
  def index
    @business_users = @business.business_users.active.includes(:user)
    @recent_activities = recent_business_activities
    @activity_summary = business_activity_summary
  end
  
  def staff
    @business_user = @business.business_users.find(params[:staff_id])
    @metrics_service = StaffMetricsService.new(@business_user, @date_range)
    @activity_summary = @metrics_service.activity_summary
    @performance_metrics = @metrics_service.performance_metrics
    @weekly_chart_data = @metrics_service.weekly_activity_chart_data
    @login_pattern = @metrics_service.daily_login_pattern
  end
  
  def team_summary
    @team_metrics = @business.business_users.active.map do |business_user|
      metrics_service = StaffMetricsService.new(business_user, @date_range)
      {
        business_user: business_user,
        summary: metrics_service.activity_summary,
        performance: metrics_service.performance_metrics
      }
    end
  end
  
  def export
    @activities = ActivityLog.where(business: @business, occurred_at: @date_range)
                            .includes(:user, :trackable)
                            .order(:occurred_at)
    
    respond_to do |format|
      format.csv do
        headers['Content-Disposition'] = "attachment; filename=\"staff_activity_#{Date.current}.csv\""
        headers['Content-Type'] = 'text/csv'
      end
    end
  end
  
  private
  
  def set_business
    @business = current_user.owned_business || current_user.business
  end
  
  def ensure_can_view_activity
    business_user = current_user.business_users.find_by(business: @business)
    unless business_user&.can_view_reports?
      redirect_to admin_dashboard_path, alert: 'Not authorized to view activity reports'
    end
  end
  
  def set_date_range
    @start_date = params[:start_date]&.to_date || 30.days.ago.to_date
    @end_date = params[:end_date]&.to_date || Date.current
    @date_range = @start_date.beginning_of_day..@end_date.end_of_day
  end
  
  def recent_business_activities
    ActivityLog.where(business: @business, occurred_at: @date_range)
               .business_activities
               .includes(:user, :trackable)
               .recent
               .limit(20)
  end
  
  def business_activity_summary
    activities = ActivityLog.where(business: @business, occurred_at: @date_range)
    
    {
      total_activities: activities.business_activities.count,
      total_logins: activities.where(action: 'login').count,
      quotes_created: activities.where(action: 'quote_created').count,
      appointments_scheduled: activities.where(action: 'appointment_scheduled').count,
      payments_processed: activities.where(action: 'payment_processed').count,
      active_staff: activities.select(:user_id).distinct.count
    }
  end
end
```

### 4. Activity Tracking Concern
**File**: `app/controllers/concerns/activity_trackable.rb`

**Implementation Notes**:
```ruby
module ActivityTrackable
  extend ActiveSupport::Concern
  
  included do
    after_action :track_activity, only: [:create, :update, :destroy]
    before_action :track_login, only: [:show, :index], if: :should_track_login?
  end
  
  private
  
  def track_activity
    return unless current_user && current_business && response.successful?
    
    action = determine_activity_action
    return unless action
    
    trackable = determine_trackable_object
    
    ActivityLog.log_activity(
      user: current_user,
      business: current_business,
      action: action,
      trackable: trackable,
      details: activity_details
    )
  end
  
  def track_login
    return unless current_user && current_business
    return if session[:login_tracked]
    
    ActivityLog.log_activity(
      user: current_user,
      business: current_business,
      action: 'login'
    )
    
    session[:login_tracked] = true
  end
  
  def should_track_login?
    # Only track login once per session
    !session[:login_tracked]
  end
  
  def determine_activity_action
    case controller_name
    when 'quotes'
      case action_name
      when 'create' then 'quote_created'
      when 'update' then 'quote_updated'
      when 'send_quote' then 'quote_sent'
      end
    when 'appointments'
      case action_name
      when 'create' then 'appointment_scheduled'
      when 'update' then 'appointment_updated'
      when 'complete' then 'appointment_completed'
      end
    when 'payments'
      case action_name
      when 'create' then 'payment_processed'
      end
    end
  end
  
  def determine_trackable_object
    # Try to find the main object being acted upon
    instance_variable_get("@#{controller_name.singularize}") ||
    instance_variable_get("@#{params[:id] ? controller_name.singularize : nil}")
  end
  
  def activity_details
    {
      controller: controller_name,
      action: action_name,
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    }
  end
end
```

### 5. Activity Tracking Index View
**File**: `app/views/admin/activity_tracking/index.html.erb`

**Implementation Notes**:
```erb
<div class="max-w-7xl mx-auto py-8">
  <div class="flex justify-between items-center mb-6">
    <h1 class="text-2xl font-bold text-gray-900">Staff Activity</h1>
    <div class="flex space-x-3">
      <%= link_to "Team Summary", team_summary_admin_activity_tracking_path,
                  class: "bg-blue-600 hover:bg-blue-700 text-white font-medium py-2 px-4 rounded-md" %>
      <%= link_to "Export Data", export_admin_activity_tracking_path(format: :csv, start_date: @start_date, end_date: @end_date),
                  class: "bg-green-600 hover:bg-green-700 text-white font-medium py-2 px-4 rounded-md" %>
    </div>
  </div>
  
  <!-- Date Range Filter -->
  <div class="bg-white shadow rounded-lg p-4 mb-6">
    <%= form_with url: admin_activity_tracking_path, method: :get, local: true, 
                  class: "flex items-center space-x-4" do |form| %>
      <div>
        <%= form.label :start_date, "From:", class: "block text-sm font-medium text-gray-700" %>
        <%= form.date_field :start_date, value: @start_date,
                           class: "mt-1 border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500" %>
      </div>
      <div>
        <%= form.label :end_date, "To:", class: "block text-sm font-medium text-gray-700" %>
        <%= form.date_field :end_date, value: @end_date,
                           class: "mt-1 border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500" %>
      </div>
      <div class="pt-6">
        <%= form.submit "Update", class: "bg-blue-600 hover:bg-blue-700 text-white font-medium py-2 px-4 rounded-md" %>
      </div>
    <% end %>
  </div>
  
  <!-- Activity Summary Cards -->
  <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
    <div class="bg-white overflow-hidden shadow rounded-lg">
      <div class="p-5">
        <div class="flex items-center">
          <div class="flex-shrink-0">
            <div class="w-8 h-8 bg-blue-500 rounded-md flex items-center justify-center">
              <span class="text-white text-sm font-bold">A</span>
            </div>
          </div>
          <div class="ml-5 w-0 flex-1">
            <dl>
              <dt class="text-sm font-medium text-gray-500 truncate">Total Activities</dt>
              <dd class="text-lg font-medium text-gray-900"><%= @activity_summary[:total_activities] %></dd>
            </dl>
          </div>
        </div>
      </div>
    </div>
    
    <div class="bg-white overflow-hidden shadow rounded-lg">
      <div class="p-5">
        <div class="flex items-center">
          <div class="flex-shrink-0">
            <div class="w-8 h-8 bg-green-500 rounded-md flex items-center justify-center">
              <span class="text-white text-sm font-bold">Q</span>
            </div>
          </div>
          <div class="ml-5 w-0 flex-1">
            <dl>
              <dt class="text-sm font-medium text-gray-500 truncate">Quotes Created</dt>
              <dd class="text-lg font-medium text-gray-900"><%= @activity_summary[:quotes_created] %></dd>
            </dl>
          </div>
        </div>
      </div>
    </div>
    
    <div class="bg-white overflow-hidden shadow rounded-lg">
      <div class="p-5">
        <div class="flex items-center">
          <div class="flex-shrink-0">
            <div class="w-8 h-8 bg-purple-500 rounded-md flex items-center justify-center">
              <span class="text-white text-sm font-bold">S</span>
            </div>
          </div>
          <div class="ml-5 w-0 flex-1">
            <dl>
              <dt class="text-sm font-medium text-gray-500 truncate">Appointments</dt>
              <dd class="text-lg font-medium text-gray-900"><%= @activity_summary[:appointments_scheduled] %></dd>
            </dl>
          </div>
        </div>
      </div>
    </div>
    
    <div class="bg-white overflow-hidden shadow rounded-lg">
      <div class="p-5">
        <div class="flex items-center">
          <div class="flex-shrink-0">
            <div class="w-8 h-8 bg-yellow-500 rounded-md flex items-center justify-center">
              <span class="text-white text-sm font-bold">$</span>
            </div>
          </div>
          <div class="ml-5 w-0 flex-1">
            <dl>
              <dt class="text-sm font-medium text-gray-500 truncate">Payments</dt>
              <dd class="text-lg font-medium text-gray-900"><%= @activity_summary[:payments_processed] %></dd>
            </dl>
          </div>
        </div>
      </div>
    </div>
  </div>
  
  <!-- Staff List with Individual Activity -->
  <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
    <!-- Staff Members -->
    <div class="bg-white shadow rounded-lg">
      <div class="px-6 py-4 border-b border-gray-200">
        <h2 class="text-lg font-medium text-gray-900">Staff Activity</h2>
      </div>
      <div class="p-6">
        <div class="space-y-4">
          <% @business_users.each do |business_user| %>
            <div class="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
              <div class="flex items-center">
                <div class="h-8 w-8 rounded-full bg-gray-300 flex items-center justify-center">
                  <span class="text-sm font-medium text-gray-700">
                    <%= business_user.user.name.first.upcase %>
                  </span>
                </div>
                <div class="ml-3">
                  <div class="text-sm font-medium text-gray-900"><%= business_user.user.name %></div>
                  <div class="text-xs text-gray-500"><%= business_user.role.titleize %></div>
                </div>
              </div>
              <div class="text-right">
                <%= link_to "View Details", staff_admin_activity_tracking_path(staff_id: business_user.id),
                            class: "text-blue-600 hover:text-blue-900 text-sm font-medium" %>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    
    <!-- Recent Activities -->
    <div class="bg-white shadow rounded-lg">
      <div class="px-6 py-4 border-b border-gray-200">
        <h2 class="text-lg font-medium text-gray-900">Recent Activities</h2>
      </div>
      <div class="p-6">
        <div class="space-y-3">
          <% @recent_activities.each do |activity| %>
            <div class="flex items-center justify-between py-2">
              <div class="flex items-center">
                <div class="h-6 w-6 rounded-full bg-blue-100 flex items-center justify-center">
                  <span class="text-xs font-medium text-blue-600">
                    <%= activity.user.name.first.upcase %>
                  </span>
                </div>
                <div class="ml-3">
                  <div class="text-sm text-gray-900"><%= activity.action_description %></div>
                  <div class="text-xs text-gray-500"><%= activity.user.name %></div>
                </div>
              </div>
              <div class="text-xs text-gray-500">
                <%= time_ago_in_words(activity.occurred_at) %> ago
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
  </div>
</div>
```

## Acceptance Criteria
- [ ] All staff activities are automatically logged
- [ ] Managers can view team activity summaries
- [ ] Individual staff performance metrics are calculated
- [ ] Activity data can be filtered by date range
- [ ] Activity logs can be exported for reporting
- [ ] Login patterns and productivity metrics are tracked

## Testing Requirements
- Activity logging tests for all tracked actions
- Metrics calculation tests
- Authorization tests for activity viewing
- Export functionality tests
- Performance tests for large activity datasets
