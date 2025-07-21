# Feature: Dashboard Overview

## Overview
Create the main dashboard landing page that serves as the central hub for business owners to access all administrative functions and get a quick overview of their business status.

## User Stories
- As a business owner, I want to see a comprehensive overview when I log in so I can quickly understand my business status
- As a business owner, I want easy navigation to all admin functions from one central location
- As a staff member, I want to see relevant information based on my role and permissions

## Tasks

### 1. Create Admin Dashboard Controller
**File**: `app/controllers/admin/dashboard_controller.rb`

**Implementation Notes**:
```ruby
class Admin::DashboardController < Admin::BaseController
  before_action :set_business
  before_action :set_date_range
  
  def index
    @dashboard_data = build_dashboard_data
    @quick_actions = available_quick_actions
    @recent_activities = recent_business_activities
    @system_alerts = check_system_alerts
  end
  
  private
  
  def set_business
    @business = current_user.owned_business || current_user.business
  end
  
  def set_date_range
    @date_range = case params[:period]
                  when 'week'
                    7.days.ago..Time.current
                  when 'month'
                    30.days.ago..Time.current
                  when 'quarter'
                    90.days.ago..Time.current
                  else
                    30.days.ago..Time.current # Default to 30 days
                  end
  end
  
  def build_dashboard_data
    DashboardDataService.new(@business, @date_range).call
  end
  
  def available_quick_actions
    business_user = current_user.business_users.find_by(business: @business)
    QuickActionsService.new(business_user).available_actions
  end
  
  def recent_business_activities
    ActivityLog.where(business: @business)
               .business_activities
               .recent
               .includes(:user, :trackable)
               .limit(10)
  end
  
  def check_system_alerts
    SystemAlertsService.new(@business).check_alerts
  end
end
```

### 2. Create Dashboard Data Service
**File**: `app/services/dashboard_data_service.rb`

**Implementation Notes**:
```ruby
class DashboardDataService
  def initialize(business, date_range)
    @business = business
    @date_range = date_range
  end
  
  def call
    {
      overview: overview_metrics,
      financial: financial_metrics,
      operational: operational_metrics,
      growth: growth_metrics,
      alerts: alert_metrics
    }
  end
  
  private
  
  def overview_metrics
    {
      total_quotes: quotes_in_range.count,
      total_jobs: appointments_in_range.count,
      total_customers: unique_customers_in_range,
      active_staff: @business.business_users.active.count
    }
  end
  
  def financial_metrics
    quotes = quotes_in_range
    
    {
      total_revenue: calculate_total_revenue,
      pending_quotes_value: quotes.pending.sum(:total_amount),
      average_quote_value: quotes.average(:total_amount)&.round(2) || 0,
      conversion_rate: calculate_conversion_rate
    }
  end
  
  def operational_metrics
    {
      quotes_pending: quotes_in_range.pending.count,
      jobs_scheduled: appointments_in_range.scheduled.count,
      jobs_completed: appointments_in_range.completed.count,
      response_time: calculate_average_response_time
    }
  end
  
  def growth_metrics
    previous_range = calculate_previous_period
    
    {
      quotes_growth: calculate_growth_percentage(:quotes, previous_range),
      revenue_growth: calculate_growth_percentage(:revenue, previous_range),
      customer_growth: calculate_growth_percentage(:customers, previous_range)
    }
  end
  
  def alert_metrics
    {
      overdue_quotes: quotes_in_range.where('valid_until < ?', Date.current).count,
      upcoming_jobs: appointments_in_range.where(scheduled_date: Date.current..3.days.from_now).count,
      incomplete_profiles: calculate_incomplete_profiles
    }
  end
  
  def quotes_in_range
    @quotes_in_range ||= @business.quotes.where(created_at: @date_range)
  end
  
  def appointments_in_range
    @appointments_in_range ||= @business.appointments.where(created_at: @date_range)
  end
  
  def unique_customers_in_range
    quotes_in_range.select(:customer_email).distinct.count
  end
  
  def calculate_total_revenue
    # This would connect to actual payment/invoice data
    quotes_in_range.approved.sum(:total_amount)
  end
  
  def calculate_conversion_rate
    total_quotes = quotes_in_range.count
    return 0 if total_quotes.zero?
    
    approved_quotes = quotes_in_range.approved.count
    ((approved_quotes.to_f / total_quotes) * 100).round(1)
  end
  
  def calculate_average_response_time
    # Placeholder - would calculate time between quote request and quote sent
    24 # hours
  end
  
  def calculate_previous_period
    period_length = @date_range.end - @date_range.begin
    (@date_range.begin - period_length)..@date_range.begin
  end
  
  def calculate_growth_percentage(metric, previous_range)
    current_value = case metric
                   when :quotes
                     quotes_in_range.count
                   when :revenue
                     calculate_total_revenue
                   when :customers
                     unique_customers_in_range
                   end
    
    previous_value = case metric
                    when :quotes
                      @business.quotes.where(created_at: previous_range).count
                    when :revenue
                      @business.quotes.where(created_at: previous_range).approved.sum(:total_amount)
                    when :customers
                      @business.quotes.where(created_at: previous_range).select(:customer_email).distinct.count
                    end
    
    return 0 if previous_value.zero?
    
    ((current_value - previous_value).to_f / previous_value * 100).round(1)
  end
  
  def calculate_incomplete_profiles
    # Check for missing business information
    alerts = 0
    alerts += 1 unless @business.logo.attached?
    alerts += 1 if @business.description.blank?
    alerts += 1 if @business.business_hours.where(is_open: true).empty?
    alerts
  end
end
```

### 3. Create Quick Actions Service
**File**: `app/services/quick_actions_service.rb`

**Implementation Notes**:
```ruby
class QuickActionsService
  def initialize(business_user)
    @business_user = business_user
    @business = business_user.business
  end
  
  def available_actions
    actions = []
    
    # Core actions available to all users
    actions << create_quote_action if can_create_quotes?
    actions << schedule_appointment_action if can_schedule_appointments?
    actions << view_customers_action if can_view_customers?
    
    # Management actions
    actions << manage_services_action if can_manage_services?
    actions << view_reports_action if can_view_reports?
    actions << manage_staff_action if can_manage_staff?
    actions << business_settings_action if can_manage_settings?
    
    actions.compact
  end
  
  private
  
  def create_quote_action
    {
      title: 'Create Quote',
      description: 'Generate a new quote for a customer',
      icon: 'document-plus',
      url: new_admin_quote_path,
      color: 'blue',
      count: pending_quote_requests_count
    }
  end
  
  def schedule_appointment_action
    {
      title: 'Schedule Job',
      description: 'Schedule a new appointment',
      icon: 'calendar-plus',
      url: new_admin_appointment_path,
      color: 'green',
      count: unscheduled_jobs_count
    }
  end
  
  def view_customers_action
    {
      title: 'Customer List',
      description: 'View and manage customers',
      icon: 'users',
      url: admin_customers_path,
      color: 'purple',
      count: total_customers_count
    }
  end
  
  def manage_services_action
    {
      title: 'Manage Services',
      description: 'Update service catalog and pricing',
      icon: 'cog',
      url: admin_services_path,
      color: 'yellow',
      count: active_services_count
    }
  end
  
  def view_reports_action
    {
      title: 'View Reports',
      description: 'Business analytics and insights',
      icon: 'chart-bar',
      url: admin_reports_path,
      color: 'indigo'
    }
  end
  
  def manage_staff_action
    {
      title: 'Manage Staff',
      description: 'Staff roles and permissions',
      icon: 'user-group',
      url: admin_staff_path,
      color: 'pink',
      count: pending_invitations_count
    }
  end
  
  def business_settings_action
    {
      title: 'Business Settings',
      description: 'Configure business preferences',
      icon: 'adjustments',
      url: edit_admin_business_path,
      color: 'gray'
    }
  end
  
  # Permission checks
  def can_create_quotes?
    @business_user.can_manage_quotes?
  end
  
  def can_schedule_appointments?
    @business_user.can_manage_appointments?
  end
  
  def can_view_customers?
    @business_user.can_view_customer_data?
  end
  
  def can_manage_services?
    @business_user.can_manage_services?
  end
  
  def can_view_reports?
    @business_user.can_view_reports?
  end
  
  def can_manage_staff?
    @business_user.can_manage_staff?
  end
  
  def can_manage_settings?
    @business_user.can_manage_business_settings?
  end
  
  # Count methods
  def pending_quote_requests_count
    @business.quote_requests.pending.count
  end
  
  def unscheduled_jobs_count
    @business.quotes.approved.joins(:quote_items)
             .where(appointments: { id: nil }).count
  end
  
  def total_customers_count
    @business.customers.count
  end
  
  def active_services_count
    @business.services.active.count
  end
  
  def pending_invitations_count
    @business.staff_invitations.pending.count
  end
end
```

### 4. Create Dashboard Layout View
**File**: `app/views/admin/dashboard/index.html.erb`

**Implementation Notes**:
```erb
<div class="max-w-7xl mx-auto py-6 px-4 sm:px-6 lg:px-8">
  <!-- Page Header -->
  <div class="md:flex md:items-center md:justify-between mb-8">
    <div class="flex-1 min-w-0">
      <h1 class="text-2xl font-bold leading-7 text-gray-900 sm:text-3xl sm:truncate">
        Welcome back, <%= current_user.name %>
      </h1>
      <p class="mt-1 text-sm text-gray-500">
        Here's what's happening with <%= @business.name %> today.
      </p>
    </div>
    <div class="mt-4 flex md:mt-0 md:ml-4">
      <!-- Period Selector -->
      <div class="relative inline-block text-left mr-3">
        <%= form_with url: admin_dashboard_path, method: :get, local: true, class: "inline" do |form| %>
          <%= form.select :period,
                         [['Last 7 days', 'week'], ['Last 30 days', 'month'], ['Last 90 days', 'quarter']],
                         { selected: params[:period] || 'month' },
                         { class: "border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500 text-sm",
                           onchange: "this.form.submit();" } %>
        <% end %>
      </div>
      
      <!-- Refresh Button -->
      <%= link_to admin_dashboard_path, class: "inline-flex items-center px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500" do %>
        <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
        </svg>
        Refresh
      <% end %>
    </div>
  </div>

  <!-- System Alerts -->
  <% if @system_alerts.any? %>
    <div class="mb-6">
      <% @system_alerts.each do |alert| %>
        <div class="rounded-md bg-yellow-50 p-4 mb-3">
          <div class="flex">
            <div class="flex-shrink-0">
              <svg class="h-5 w-5 text-yellow-400" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd" />
              </svg>
            </div>
            <div class="ml-3">
              <h3 class="text-sm font-medium text-yellow-800"><%= alert[:title] %></h3>
              <div class="mt-2 text-sm text-yellow-700">
                <p><%= alert[:message] %></p>
              </div>
              <% if alert[:action_url] %>
                <div class="mt-4">
                  <%= link_to alert[:action_text], alert[:action_url], 
                              class: "text-sm bg-yellow-50 text-yellow-800 rounded-md px-2 py-1 hover:bg-yellow-100" %>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>
    </div>
  <% end %>

  <!-- Overview Stats -->
  <div class="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-4 mb-8">
    <!-- Total Quotes -->
    <div class="bg-white overflow-hidden shadow rounded-lg">
      <div class="p-5">
        <div class="flex items-center">
          <div class="flex-shrink-0">
            <svg class="h-6 w-6 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
            </svg>
          </div>
          <div class="ml-5 w-0 flex-1">
            <dl>
              <dt class="text-sm font-medium text-gray-500 truncate">Total Quotes</dt>
              <dd class="flex items-baseline">
                <div class="text-2xl font-semibold text-gray-900">
                  <%= @dashboard_data[:overview][:total_quotes] %>
                </div>
                <% if @dashboard_data[:growth][:quotes_growth] != 0 %>
                  <div class="ml-2 flex items-baseline text-sm font-semibold <%= @dashboard_data[:growth][:quotes_growth] > 0 ? 'text-green-600' : 'text-red-600' %>">
                    <svg class="self-center flex-shrink-0 h-5 w-5 <%= @dashboard_data[:growth][:quotes_growth] > 0 ? 'text-green-500' : 'text-red-500' %>" fill="currentColor" viewBox="0 0 20 20">
                      <% if @dashboard_data[:growth][:quotes_growth] > 0 %>
                        <path fill-rule="evenodd" d="M5.293 9.707a1 1 0 010-1.414l4-4a1 1 0 011.414 0l4 4a1 1 0 01-1.414 1.414L11 7.414V15a1 1 0 11-2 0V7.414L6.707 9.707a1 1 0 01-1.414 0z" clip-rule="evenodd" />
                      <% else %>
                        <path fill-rule="evenodd" d="M14.707 10.293a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 111.414-1.414L9 12.586V5a1 1 0 012 0v7.586l2.293-2.293a1 1 0 011.414 0z" clip-rule="evenodd" />
                      <% end %>
                    </svg>
                    <span class="sr-only"><%= @dashboard_data[:growth][:quotes_growth] > 0 ? 'Increased' : 'Decreased' %> by</span>
                    <%= @dashboard_data[:growth][:quotes_growth].abs %>%
                  </div>
                <% end %>
              </dd>
            </dl>
          </div>
        </div>
      </div>
    </div>

    <!-- Total Revenue -->
    <div class="bg-white overflow-hidden shadow rounded-lg">
      <div class="p-5">
        <div class="flex items-center">
          <div class="flex-shrink-0">
            <svg class="h-6 w-6 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1" />
            </svg>
          </div>
          <div class="ml-5 w-0 flex-1">
            <dl>
              <dt class="text-sm font-medium text-gray-500 truncate">Total Revenue</dt>
              <dd class="flex items-baseline">
                <div class="text-2xl font-semibold text-gray-900">
                  <%= number_to_currency(@dashboard_data[:financial][:total_revenue]) %>
                </div>
                <% if @dashboard_data[:growth][:revenue_growth] != 0 %>
                  <div class="ml-2 flex items-baseline text-sm font-semibold <%= @dashboard_data[:growth][:revenue_growth] > 0 ? 'text-green-600' : 'text-red-600' %>">
                    <%= @dashboard_data[:growth][:revenue_growth] > 0 ? '↗' : '↘' %>
                    <%= @dashboard_data[:growth][:revenue_growth].abs %>%
                  </div>
                <% end %>
              </dd>
            </dl>
          </div>
        </div>
      </div>
    </div>

    <!-- Jobs Completed -->
    <div class="bg-white overflow-hidden shadow rounded-lg">
      <div class="p-5">
        <div class="flex items-center">
          <div class="flex-shrink-0">
            <svg class="h-6 w-6 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4" />
            </svg>
          </div>
          <div class="ml-5 w-0 flex-1">
            <dl>
              <dt class="text-sm font-medium text-gray-500 truncate">Jobs Completed</dt>
              <dd class="text-2xl font-semibold text-gray-900">
                <%= @dashboard_data[:operational][:jobs_completed] %>
              </dd>
            </dl>
          </div>
        </div>
      </div>
    </div>

    <!-- Conversion Rate -->
    <div class="bg-white overflow-hidden shadow rounded-lg">
      <div class="p-5">
        <div class="flex items-center">
          <div class="flex-shrink-0">
            <svg class="h-6 w-6 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 7h8m0 0v8m0-8l-8 8-4-4-6 6" />
            </svg>
          </div>
          <div class="ml-5 w-0 flex-1">
            <dl>
              <dt class="text-sm font-medium text-gray-500 truncate">Conversion Rate</dt>
              <dd class="text-2xl font-semibold text-gray-900">
                <%= @dashboard_data[:financial][:conversion_rate] %>%
              </dd>
            </dl>
          </div>
        </div>
      </div>
    </div>
  </div>

  <!-- Quick Actions and Recent Activity Grid -->
  <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">
    <!-- Quick Actions Section -->
    <div class="lg:col-span-1">
      <%= render 'shared/quick_actions_panel', actions: @quick_actions %>
    </div>

    <!-- Recent Activity and Metrics -->
    <div class="lg:col-span-2 space-y-6">
      <%= render 'shared/key_metrics_display', metrics: @dashboard_data %>
      <%= render 'shared/recent_activity_feed', activities: @recent_activities %>
    </div>
  </div>
</div>
```

## Acceptance Criteria
- [ ] Dashboard loads within 2 seconds with all essential data
- [ ] Displays key business metrics with growth indicators
- [ ] Shows role-appropriate quick actions based on user permissions
- [ ] Responsive design works on all device sizes
- [ ] Period selector allows filtering of time-based metrics
- [ ] System alerts are prominently displayed when present
- [ ] Navigation to all admin functions is easily accessible

## Testing Requirements
- Controller tests for dashboard data assembly
- Service tests for dashboard data calculations
- View tests for proper metric display
- Integration tests for permission-based action visibility
- Performance tests to ensure 2-second load time requirement
