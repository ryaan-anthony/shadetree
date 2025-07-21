# Feature: Activity Monitoring

## Overview
Implement a comprehensive user activity monitoring system to track user sessions, page views, and business operations across the platform. This feature will enable business owners and administrators to gain insights into how the system is being used, monitor for suspicious activity, and understand user workflow patterns.

## Goals
- Track user sessions and activity throughout the platform
- Provide insights into feature usage and user workflow patterns
- Enable identification of suspicious or unusual activity
- Support troubleshooting of user-reported issues
- Create an accountability trail for user actions

## User Stories
- As a business owner, I want to see what actions my staff are taking in the system
- As an administrator, I want to view login patterns to identify potential security issues
- As a support representative, I want to trace a user's steps to help troubleshoot issues they report
- As a business owner, I want to monitor system usage to optimize training and procedures
- As an administrator, I want to identify underutilized features to improve adoption

## Tasks

### Task 1: Create Activity Log Model and Database Structure
**Description:** Design and implement the core data structures for tracking user activity.

**Implementation Notes:**
- Create `ActivityLog` model and migration
- Implement associations with users and businesses
- Add indexes for efficient querying and reporting

```ruby
# app/models/activity_log.rb
class ActivityLog < ApplicationRecord
  belongs_to :business
  belongs_to :user
  belongs_to :subject, polymorphic: true, optional: true
  
  validates :action_type, :controller, :action, presence: true
  validates :ip_address, :user_agent, presence: true
  
  enum action_type: {
    page_view: 0,
    form_submit: 1,
    file_upload: 2,
    export: 3,
    login: 4,
    logout: 5,
    api_call: 6,
    search: 7,
    email_send: 8,
    sms_send: 9
  }
  
  serialize :metadata, Hash
  
  scope :recent, -> { where(created_at: 7.days.ago..) }
  scope :by_user, ->(user_id) { where(user_id: user_id) }
  scope :by_action_type, ->(action_type) { where(action_type: action_type) }
  scope :login_activity, -> { where(action_type: ['login', 'logout']) }
  scope :by_date_range, ->(start_date, end_date) { 
    where(created_at: start_date.beginning_of_day..end_date.end_of_day) 
  }
  
  def self.user_journey(user, hours_back = 24)
    where(user: user)
      .where("created_at >= ?", hours_back.hours.ago)
      .order(created_at: :asc)
  end
  
  def path
    "#{controller}##{action}"
  end
end
```

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_activity_logs.rb
class CreateActivityLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :activity_logs do |t|
      t.references :business, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :subject, polymorphic: true, null: true
      
      t.integer :action_type, null: false, default: 0
      t.string :controller, null: false
      t.string :action, null: false
      t.string :ip_address, null: false
      t.text :user_agent, null: false
      t.text :url
      t.text :metadata
      
      t.timestamps null: false
    end
    
    add_index :activity_logs, [:business_id, :created_at]
    add_index :activity_logs, [:user_id, :created_at]
    add_index :activity_logs, [:action_type, :created_at]
  end
end
```

### Task 2: Implement Activity Tracking Controller Concern
**Description:** Create a reusable controller concern to automatically track user activity.

**Implementation Notes:**
- Create controller concern for activity tracking
- Automatically log page views, form submissions, and other interactions
- Filter sensitive data from logs

```ruby
# app/controllers/concerns/activity_tracking.rb
module ActivityTracking
  extend ActiveSupport::Concern
  
  included do
    after_action :log_page_view, only: [:index, :show, :new, :edit]
    after_action :log_form_submission, only: [:create, :update, :destroy]
    
    # Skip sensitive controllers
    skip_after_action :log_page_view, :log_form_submission, if: :skip_activity_logging?
  end
  
  private
  
  def log_page_view
    return unless current_user && current_business
    
    # Get the subject record for the action if applicable
    subject = extract_subject_from_params
    
    # Create the activity log
    create_activity_log(:page_view, subject)
  end
  
  def log_form_submission
    return unless current_user && current_business
    
    # Determine the action type based on the controller action
    action_type = case action_name
                  when 'create' then :form_submit
                  when 'update' then :form_submit
                  when 'destroy' then :form_submit
                  else :form_submit
                  end
    
    # Get the subject record
    subject = extract_subject_from_params
    
    # Create the activity log with relevant metadata
    create_activity_log(action_type, subject, {
      form_action: action_name,
      record_id: params[:id],
      status: response.status
    })
  end
  
  def create_activity_log(action_type, subject = nil, additional_metadata = {})
    # Skip logging for non-HTML requests (like AJAX calls) unless it's an API call
    return if !request.format.html? && action_type != :api_call
    
    # Basic metadata that's useful for all activity logs
    metadata = {
      query_params: sanitize_params(request.query_parameters),
      referrer: request.referrer
    }.merge(additional_metadata)
    
    ActivityLog.create!(
      business: current_business,
      user: current_user,
      subject: subject,
      action_type: action_type,
      controller: controller_name,
      action: action_name,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      url: request.original_url,
      metadata: metadata
    )
  rescue => e
    Rails.logger.error "Failed to log activity: #{e.message}"
  end
  
  def extract_subject_from_params
    # Try to determine the subject based on instance variables
    instance_var = instance_variables.find do |var|
      var_name = var.to_s.sub('@', '')
      var_name.singularize == controller_name.singularize && 
        instance_variable_get(var).respond_to?(:id)
    end
    
    instance_variable_get(instance_var) if instance_var
  end
  
  def sanitize_params(params_hash)
    # Create a copy to avoid modifying the original
    sanitized = params_hash.dup
    
    # Filter out sensitive parameters
    sensitive_params = %w(password password_confirmation token api_key credit_card)
    
    sensitive_params.each do |param|
      sanitized[param] = "[FILTERED]" if sanitized.key?(param)
    end
    
    sanitized
  end
  
  def skip_activity_logging?
    # Skip activity logging for certain controllers
    %w(activity_logs audit_logs sessions passwords).include?(controller_name)
  end
end
```

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  include AuditLogging
  include ActivityTracking
  
  # ...existing code...
end
```

### Task 3: Create User Session Tracking
**Description:** Implement comprehensive tracking of user login sessions.

**Implementation Notes:**
- Track user session start and end
- Log login successes and failures
- Record session metadata (browser, device, location)

```ruby
# app/controllers/sessions_controller.rb
class SessionsController < Devise::SessionsController
  # Assuming Devise is used for authentication
  after_action :log_successful_login, only: :create
  after_action :log_logout, only: :destroy
  
  protected
  
  def log_successful_login
    return unless current_user && current_business
    
    device_info = DeviceDetector.new(request.user_agent)
    
    ActivityLog.create!(
      business: current_business,
      user: current_user,
      action_type: :login,
      controller: controller_name,
      action: action_name,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      metadata: {
        browser: device_info.name,
        browser_version: device_info.full_version,
        device_type: device_info.device_type,
        os: device_info.os_name,
        os_version: device_info.os_full_version,
        location: request.location&.city || 'Unknown'
      }
    )
    
    # Update last login time on user
    current_user.update_column(:last_sign_in_at, Time.current)
  rescue => e
    Rails.logger.error "Failed to log login activity: #{e.message}"
  end
  
  def log_logout
    return unless current_user && current_business
    
    ActivityLog.create!(
      business: current_business,
      user: current_user,
      action_type: :logout,
      controller: controller_name,
      action: action_name,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      metadata: {
        session_duration: (Time.current - current_user.current_sign_in_at).to_i
      }
    )
  rescue => e
    Rails.logger.error "Failed to log logout activity: #{e.message}"
  end
end
```

### Task 4: Create Activity Dashboard for Admins
**Description:** Build a user-friendly dashboard for viewing and analyzing user activity.

**Implementation Notes:**
- Create admin controller for activity monitoring
- Implement filterable activity views
- Create visualizations for activity patterns
- Build user journey tracking interface

```ruby
# app/controllers/admin/activity_logs_controller.rb
class Admin::ActivityLogsController < Admin::BaseController
  before_action :require_admin
  before_action :set_user, only: [:user_activity]
  
  def index
    @activity_logs = current_business.activity_logs
      .includes(:user)
      .order(created_at: :desc)
    
    if params[:user_id].present?
      @activity_logs = @activity_logs.where(user_id: params[:user_id])
    end
    
    if params[:action_type].present?
      @activity_logs = @activity_logs.where(action_type: params[:action_type])
    end
    
    if params[:date_from].present?
      @activity_logs = @activity_logs.where("created_at >= ?", Date.parse(params[:date_from]).beginning_of_day)
    end
    
    if params[:date_to].present?
      @activity_logs = @activity_logs.where("created_at <= ?", Date.parse(params[:date_to]).end_of_day)
    end
    
    @activity_logs = @activity_logs.paginate(page: params[:page], per_page: 30)
    
    # Prepare data for filter dropdowns
    @users = current_business.users.order(name: :asc)
    @action_types = ActivityLog.action_types.keys.map do |action_type|
      [action_type.humanize, action_type]
    end
  end
  
  def show
    @activity_log = current_business.activity_logs.find(params[:id])
  end
  
  def user_activity
    @date_range = params[:range] || 'week'
    
    case @date_range
    when 'day'
      @start_date = Date.today
      @end_date = Date.today
    when 'week'
      @start_date = Date.today.beginning_of_week
      @end_date = Date.today.end_of_week
    when 'month'
      @start_date = Date.today.beginning_of_month
      @end_date = Date.today.end_of_month
    when 'custom'
      @start_date = params[:start_date] ? Date.parse(params[:start_date]) : Date.today - 7.days
      @end_date = params[:end_date] ? Date.parse(params[:end_date]) : Date.today
    end
    
    @activity_logs = current_business.activity_logs
      .where(user: @user)
      .where(created_at: @start_date.beginning_of_day..@end_date.end_of_day)
      .order(created_at: :desc)
      .paginate(page: params[:page], per_page: 30)
    
    @activity_summary = @activity_logs.group(:action_type).count
    @login_count = @activity_logs.login_activity.where(action_type: :login).count
    
    @activity_by_day = @activity_logs
      .group("DATE(created_at)")
      .count
      .transform_keys { |k| k.to_date.to_s }
  end
  
  def login_activity
    @login_logs = current_business.activity_logs
      .login_activity
      .includes(:user)
      .order(created_at: :desc)
    
    if params[:user_id].present?
      @login_logs = @login_logs.where(user_id: params[:user_id])
    end
    
    if params[:date_from].present?
      @login_logs = @login_logs.where("created_at >= ?", Date.parse(params[:date_from]).beginning_of_day)
    end
    
    if params[:date_to].present?
      @login_logs = @login_logs.where("created_at <= ?", Date.parse(params[:date_to]).end_of_day)
    end
    
    @login_logs = @login_logs.paginate(page: params[:page], per_page: 30)
    
    # Group logins by day for visualization
    @logins_by_day = @login_logs
      .where(action_type: :login)
      .group("DATE(created_at)")
      .count
      .transform_keys { |k| k.to_date.to_s }
    
    # Get unique user count with logins during period
    @unique_users = @login_logs.select(:user_id).distinct.count
    
    # Prepare data for filter dropdowns
    @users = current_business.users.order(name: :asc)
  end
  
  private
  
  def set_user
    @user = current_business.users.find(params[:user_id])
  end
end
```

```erb
<!-- app/views/admin/activity_logs/index.html.erb -->
<div class="container mx-auto px-4 py-6">
  <h1 class="text-2xl font-bold mb-6">User Activity Monitor</h1>
  
  <div class="bg-white rounded-lg shadow mb-6 p-4">
    <h2 class="text-lg font-semibold mb-4">Filter Activity</h2>
    
    <%= form_with url: admin_activity_logs_path, method: :get, class: "space-y-4", local: true do |f| %>
      <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div>
          <%= f.label :user_id, "User", class: "block text-sm font-medium text-gray-700 mb-1" %>
          <%= f.select :user_id, 
            options_from_collection_for_select(@users, 'id', 'name', params[:user_id]), 
            { include_blank: "All Users" }, 
            class: "w-full border-gray-300 rounded-md shadow-sm focus:border-indigo-300 focus:ring focus:ring-indigo-200 focus:ring-opacity-50" %>
        </div>
        
        <div>
          <%= f.label :action_type, "Activity Type", class: "block text-sm font-medium text-gray-700 mb-1" %>
          <%= f.select :action_type, 
            options_for_select(@action_types, params[:action_type]), 
            { include_blank: "All Activities" }, 
            class: "w-full border-gray-300 rounded-md shadow-sm focus:border-indigo-300 focus:ring focus:ring-indigo-200 focus:ring-opacity-50" %>
        </div>
        
        <div>
          <%= f.label :controller, "Section", class: "block text-sm font-medium text-gray-700 mb-1" %>
          <%= f.select :controller, 
            options_for_select(current_business.activity_logs.select(:controller).distinct.pluck(:controller).map { |c| [c.humanize, c] }, params[:controller]), 
            { include_blank: "All Sections" }, 
            class: "w-full border-gray-300 rounded-md shadow-sm focus:border-indigo-300 focus:ring focus:ring-indigo-200 focus:ring-opacity-50" %>
        </div>
      </div>
      
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div>
          <%= f.label :date_from, "From Date", class: "block text-sm font-medium text-gray-700 mb-1" %>
          <%= f.date_field :date_from, value: params[:date_from], class: "w-full border-gray-300 rounded-md shadow-sm focus:border-indigo-300 focus:ring focus:ring-indigo-200 focus:ring-opacity-50" %>
        </div>
        
        <div>
          <%= f.label :date_to, "To Date", class: "block text-sm font-medium text-gray-700 mb-1" %>
          <%= f.date_field :date_to, value: params[:date_to], class: "w-full border-gray-300 rounded-md shadow-sm focus:border-indigo-300 focus:ring focus:ring-indigo-200 focus:ring-opacity-50" %>
        </div>
      </div>
      
      <div>
        <%= f.submit "Apply Filters", class: "bg-indigo-600 hover:bg-indigo-700 text-white font-semibold py-2 px-4 rounded" %>
        <%= link_to "Reset", admin_activity_logs_path, class: "ml-2 text-indigo-600 hover:text-indigo-800" %>
        <%= link_to "Login Activity", login_activity_admin_activity_logs_path, class: "ml-4 text-indigo-600 hover:text-indigo-800" %>
      </div>
    <% end %>
  </div>
  
  <div class="bg-white rounded-lg shadow overflow-hidden">
    <table class="min-w-full divide-y divide-gray-200">
      <thead class="bg-gray-50">
        <tr>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Time</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">User</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Activity</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Location</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">IP Address</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"></th>
        </tr>
      </thead>
      <tbody class="bg-white divide-y divide-gray-200">
        <% @activity_logs.each do |log| %>
          <tr>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
              <%= log.created_at.strftime("%b %d, %Y %H:%M:%S") %>
            </td>
            <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
              <%= link_to log.user.name, user_activity_admin_activity_logs_path(user_id: log.user.id), class: "text-indigo-600 hover:text-indigo-900" %>
            </td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
              <%= activity_badge(log.action_type) %> 
              <span class="ml-2"><%= log.controller.humanize %> - <%= log.action.humanize %></span>
            </td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
              <%= log.metadata&.dig("location") || "Unknown" %>
            </td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
              <%= log.ip_address %>
            </td>
            <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
              <%= link_to "Details", admin_activity_log_path(log), class: "text-indigo-600 hover:text-indigo-900" %>
            </td>
          </tr>
        <% end %>
        
        <% if @activity_logs.empty? %>
          <tr>
            <td colspan="6" class="px-6 py-4 text-center text-sm text-gray-500">
              No activity logs found with the current filters.
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
    
    <div class="px-4 py-3 border-t border-gray-200">
      <%= will_paginate @activity_logs, class: "pagination" %>
    </div>
  </div>
</div>
```

```erb
<!-- app/views/admin/activity_logs/user_activity.html.erb -->
<div class="container mx-auto px-4 py-6">
  <div class="flex justify-between items-center mb-6">
    <h1 class="text-2xl font-bold">User Activity: <%= @user.name %></h1>
    <%= link_to "← Back to All Activity", admin_activity_logs_path, class: "text-indigo-600 hover:text-indigo-800" %>
  </div>
  
  <div class="bg-white rounded-lg shadow mb-6">
    <div class="p-4 border-b border-gray-200">
      <h2 class="text-lg font-semibold">Activity Summary</h2>
    </div>
    <div class="p-4">
      <div class="grid grid-cols-1 md:grid-cols-4 gap-4">
        <div class="bg-white p-4 rounded-lg border border-gray-200">
          <h3 class="text-sm text-gray-500 uppercase">Total Activities</h3>
          <p class="text-2xl font-bold"><%= @activity_logs.total_entries %></p>
        </div>
        
        <div class="bg-white p-4 rounded-lg border border-gray-200">
          <h3 class="text-sm text-gray-500 uppercase">Logins</h3>
          <p class="text-2xl font-bold"><%= @login_count %></p>
        </div>
        
        <div class="bg-white p-4 rounded-lg border border-gray-200">
          <h3 class="text-sm text-gray-500 uppercase">Last Active</h3>
          <p class="text-2xl font-bold"><%= @activity_logs.first&.created_at&.strftime("%b %d, %H:%M") || "N/A" %></p>
        </div>
        
        <div class="bg-white p-4 rounded-lg border border-gray-200">
          <h3 class="text-sm text-gray-500 uppercase">Date Range</h3>
          <p class="text-md font-bold"><%= @start_date.strftime("%b %d") %> - <%= @end_date.strftime("%b %d, %Y") %></p>
        </div>
      </div>
      
      <div class="mt-6">
        <h3 class="text-lg font-medium mb-2">Activity by Type</h3>
        <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-5 gap-4">
          <% ActivityLog.action_types.keys.each do |action_type| %>
            <div class="bg-gray-50 p-3 rounded-md">
              <h4 class="text-sm font-medium text-gray-700"><%= action_type.humanize %></h4>
              <p class="text-xl font-bold mt-1"><%= @activity_summary[action_type] || 0 %></p>
            </div>
          <% end %>
        </div>
      </div>
      
      <div class="mt-6">
        <h3 class="text-lg font-medium mb-2">Activity Timeline</h3>
        <div class="bg-white p-4 rounded-lg border border-gray-200 h-60">
          <!-- Placeholder for a chart that would render the activity by day -->
          <canvas id="activityChart" width="400" height="200"></canvas>
        </div>
        
        <script>
          document.addEventListener('DOMContentLoaded', function() {
            const ctx = document.getElementById('activityChart').getContext('2d');
            const activityData = <%= raw @activity_by_day.to_json %>;
            
            const labels = Object.keys(activityData).sort();
            const data = labels.map(date => activityData[date] || 0);
            
            new Chart(ctx, {
              type: 'line',
              data: {
                labels: labels,
                datasets: [{
                  label: 'Activities',
                  data: data,
                  backgroundColor: 'rgba(79, 70, 229, 0.2)',
                  borderColor: 'rgba(79, 70, 229, 1)',
                  borderWidth: 2,
                  tension: 0.3,
                  fill: true
                }]
              },
              options: {
                scales: {
                  y: {
                    beginAtZero: true,
                    ticks: {
                      precision: 0
                    }
                  }
                },
                plugins: {
                  legend: {
                    display: false
                  }
                }
              }
            });
          });
        </script>
      </div>
    </div>
  </div>
  
  <div class="bg-white rounded-lg shadow">
    <div class="p-4 border-b border-gray-200 flex justify-between items-center">
      <h2 class="text-lg font-semibold">Activity Detail</h2>
      
      <div class="flex space-x-2">
        <%= link_to "Day", user_activity_admin_activity_logs_path(user_id: @user.id, range: 'day'), class: "px-3 py-1 rounded #{@date_range == 'day' ? 'bg-indigo-100 text-indigo-800' : 'bg-gray-100 text-gray-800'}" %>
        <%= link_to "Week", user_activity_admin_activity_logs_path(user_id: @user.id, range: 'week'), class: "px-3 py-1 rounded #{@date_range == 'week' ? 'bg-indigo-100 text-indigo-800' : 'bg-gray-100 text-gray-800'}" %>
        <%= link_to "Month", user_activity_admin_activity_logs_path(user_id: @user.id, range: 'month'), class: "px-3 py-1 rounded #{@date_range == 'month' ? 'bg-indigo-100 text-indigo-800' : 'bg-gray-100 text-gray-800'}" %>
        <%= link_to "Custom", user_activity_admin_activity_logs_path(user_id: @user.id, range: 'custom'), class: "px-3 py-1 rounded #{@date_range == 'custom' ? 'bg-indigo-100 text-indigo-800' : 'bg-gray-100 text-gray-800'}" %>
      </div>
    </div>
    
    <% if @date_range == 'custom' %>
      <div class="p-4 bg-gray-50 border-b border-gray-200">
        <%= form_with url: user_activity_admin_activity_logs_path(user_id: @user.id, range: 'custom'), method: :get, class: "flex flex-wrap items-center space-x-4", local: true do |f| %>
          <div>
            <%= f.label :start_date, "From:", class: "mr-2 text-sm font-medium text-gray-700" %>
            <%= f.date_field :start_date, value: @start_date, class: "border-gray-300 rounded-md shadow-sm focus:border-indigo-300 focus:ring focus:ring-indigo-200 focus:ring-opacity-50" %>
          </div>
          
          <div>
            <%= f.label :end_date, "To:", class: "mr-2 text-sm font-medium text-gray-700" %>
            <%= f.date_field :end_date, value: @end_date, class: "border-gray-300 rounded-md shadow-sm focus:border-indigo-300 focus:ring focus:ring-indigo-200 focus:ring-opacity-50" %>
          </div>
          
          <%= f.hidden_field :range, value: 'custom' %>
          <%= f.hidden_field :user_id, value: @user.id %>
          
          <%= f.submit "Apply", class: "bg-indigo-600 hover:bg-indigo-700 text-white font-medium py-1 px-3 rounded" %>
        <% end %>
      </div>
    <% end %>
    
    <div class="overflow-x-auto">
      <table class="min-w-full divide-y divide-gray-200">
        <thead class="bg-gray-50">
          <tr>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Time</th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Activity</th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Location</th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Details</th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"></th>
          </tr>
        </thead>
        <tbody class="bg-white divide-y divide-gray-200">
          <% @activity_logs.each do |log| %>
            <tr>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                <%= log.created_at.strftime("%H:%M:%S") %>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                <%= activity_badge(log.action_type) %> 
                <span class="ml-2"><%= log.controller.humanize %> - <%= log.action.humanize %></span>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                <%= log.metadata&.dig("location") || "Unknown" %>
              </td>
              <td class="px-6 py-4 text-sm text-gray-500 max-w-xs truncate">
                <%= log.url %>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                <%= link_to "Details", admin_activity_log_path(log), class: "text-indigo-600 hover:text-indigo-900" %>
              </td>
            </tr>
          <% end %>
          
          <% if @activity_logs.empty? %>
            <tr>
              <td colspan="5" class="px-6 py-4 text-center text-sm text-gray-500">
                No activity logs found for this period.
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    
    <div class="px-4 py-3 border-t border-gray-200">
      <%= will_paginate @activity_logs, class: "pagination" %>
    </div>
  </div>
</div>
```

```ruby
# app/helpers/admin/activity_logs_helper.rb
module Admin::ActivityLogsHelper
  def activity_badge(action_type)
    case action_type.to_sym
    when :page_view
      content_tag :span, "View", class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800"
    when :form_submit
      content_tag :span, "Form", class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800"
    when :file_upload
      content_tag :span, "Upload", class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-yellow-100 text-yellow-800"
    when :export
      content_tag :span, "Export", class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-purple-100 text-purple-800"
    when :login
      content_tag :span, "Login", class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800"
    when :logout
      content_tag :span, "Logout", class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-800"
    when :api_call
      content_tag :span, "API", class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-indigo-100 text-indigo-800"
    when :search
      content_tag :span, "Search", class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-pink-100 text-pink-800"
    else
      content_tag :span, action_type.to_s.humanize, class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800"
    end
  end
end
```

## Security Considerations
- Filter sensitive data from activity logs
- Implement strict access controls to activity data
- Consider GDPR and other privacy implications of tracking
- Establish data retention policies
- Ensure user notification of monitoring where required
- Secure IP address data as personally identifiable information

## Testing Strategy
- Unit tests for the ActivityTracking concern
- Integration tests for automatic activity capturing
- Controller tests to ensure proper logging
- View tests for admin monitoring interface

## Rollout Plan
1. Deploy initial activity tracking infrastructure
2. Enable login/logout tracking first
3. Gradually enable page view tracking
4. Add form submission tracking
5. Introduce admin monitoring dashboard
6. Document usage for business owners
