# Feature: Access Audit Trail

## Overview
Implement a specialized audit tracking system that monitors and records all access-related events including login attempts, permission changes, and resource access attempts. This system provides enhanced security insights, allows detection of suspicious behavior, and helps meet regulatory compliance requirements for access control.

## Goals
- Track all authentication attempts (successful and failed)
- Monitor permission and role changes across the system
- Record security-sensitive operations
- Support security incident investigation
- Enable regulatory compliance for access control auditing

## User Stories
- As a security administrator, I want to see all failed login attempts to identify potential breaches
- As a business owner, I want to know when user permissions change to maintain proper access controls
- As a compliance officer, I want access records for sensitive data to meet regulatory requirements
- As an administrator, I want to track password resets and account recoveries
- As a security administrator, I want to identify suspicious access patterns and multiple failed login attempts

## Tasks

### Task 1: Create Security Event Model
**Description:** Develop a specialized model for tracking security and access-related events.

**Implementation Notes:**
- Create `SecurityEvent` model and migration
- Implement associations with users and businesses
- Add indexes for efficient querying

```ruby
# app/models/security_event.rb
class SecurityEvent < ApplicationRecord
  belongs_to :business, optional: true
  belongs_to :user, optional: true
  
  validates :event_type, :severity, presence: true
  
  enum event_type: {
    login_success: 0,
    login_failure: 1,
    logout: 2,
    password_reset_requested: 3,
    password_changed: 4,
    permissions_changed: 5,
    role_changed: 6,
    account_locked: 7,
    account_unlocked: 8,
    sensitive_access: 9,
    api_key_created: 10,
    api_key_revoked: 11,
    suspicious_activity: 12,
    two_factor_enabled: 13,
    two_factor_disabled: 14,
    account_created: 15,
    account_deleted: 16
  }
  
  enum severity: {
    info: 0,
    warning: 1,
    error: 2,
    critical: 3
  }
  
  serialize :metadata, Hash
  
  scope :recent, -> { where(created_at: 30.days.ago..) }
  scope :failures, -> { where(event_type: :login_failure) }
  scope :by_user, ->(user_id) { where(user_id: user_id) }
  scope :security_issues, -> { where(severity: [:warning, :error, :critical]) }
  
  def self.failed_login_count(ip_address, hours = 24)
    where(event_type: :login_failure)
      .where("metadata->>'ip_address' = ?", ip_address)
      .where("created_at >= ?", hours.hours.ago)
      .count
  end
end
```

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_security_events.rb
class CreateSecurityEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :security_events do |t|
      t.references :business, null: true, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.integer :event_type, null: false
      t.integer :severity, null: false, default: 0
      t.string :ip_address
      t.string :user_agent
      t.text :metadata
      
      t.timestamps null: false
    end
    
    add_index :security_events, [:business_id, :created_at]
    add_index :security_events, [:user_id, :created_at]
    add_index :security_events, [:event_type, :created_at]
    add_index :security_events, [:severity, :created_at]
    add_index :security_events, :ip_address
  end
end
```

### Task 2: Implement Authentication Tracking
**Description:** Track all authentication-related events and failed login attempts.

**Implementation Notes:**
- Extend authentication system to log security events
- Track failed login attempts with IP address info
- Monitor for brute force attempts

```ruby
# app/controllers/concerns/security_events_tracking.rb
module SecurityEventsTracking
  extend ActiveSupport::Concern

  included do
    # For Devise or any other authentication system
    if respond_to?(:after_authentication_success)
      after_authentication_success :log_successful_login
    end
    
    if respond_to?(:after_authentication_failure)
      after_authentication_failure :log_failed_login
    end
  end
  
  def log_successful_login
    return unless user_signed_in?
    
    create_security_event(
      event_type: :login_success,
      severity: :info,
      user: current_user,
      business: current_business,
      metadata: {
        device_info: extract_device_info
      }
    )
  end
  
  def log_failed_login
    # Get attempted username/email from params
    login_identifier = params.dig(:user, :email) || params.dig(:user, :username) || params[:email] || params[:username]
    
    # Try to find the user that was attempted
    user = User.find_by(email: login_identifier) if login_identifier.present?
    business = user&.business
    
    # Check for excessive failed attempts
    failed_attempts = SecurityEvent.failed_login_count(request.remote_ip, 1)
    severity = if failed_attempts >= 10
                 :critical
               elsif failed_attempts >= 5
                 :error
               else
                 :warning
               end
    
    create_security_event(
      event_type: :login_failure,
      severity: severity,
      user: user,
      business: business,
      metadata: {
        login_identifier: login_identifier,
        failed_attempts: failed_attempts + 1,
        device_info: extract_device_info
      }
    )
    
    # Implement account lockout after too many failed attempts
    if user && severity == :critical
      user.lock_access! if user.respond_to?(:lock_access!)
      
      create_security_event(
        event_type: :account_locked,
        severity: :error,
        user: user,
        business: business,
        metadata: {
          reason: "Too many failed login attempts",
          threshold: 10,
          device_info: extract_device_info
        }
      )
    end
  end
  
  private
  
  def extract_device_info
    device = DeviceDetector.new(request.user_agent)
    
    {
      ip_address: request.remote_ip,
      browser: device.name,
      browser_version: device.full_version,
      os: device.os_name,
      os_version: device.os_full_version,
      device_type: device.device_type,
      device_name: device.device_name,
      is_mobile: device.device_type == 'smartphone' || device.device_type == 'tablet',
      is_bot: device.bot?
    }
  end
  
  def create_security_event(attributes = {})
    SecurityEvent.create!(
      attributes.merge(
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )
    )
  rescue => e
    Rails.logger.error "Failed to create security event: #{e.message}"
  end
end
```

```ruby
# app/controllers/users/sessions_controller.rb
class Users::SessionsController < Devise::SessionsController
  include SecurityEventsTracking
  
  # Extend the Devise SessionsController to hook into auth events
  def create
    self.resource = warden.authenticate!(auth_options)
    set_flash_message!(:notice, :signed_in)
    sign_in(resource_name, resource)
    
    # Log successful login
    log_successful_login
    
    respond_with resource, location: after_sign_in_path_for(resource)
  end
  
  def failure
    # Log failed login
    log_failed_login
    
    respond_to do |format|
      format.html { redirect_to new_user_session_path, alert: I18n.t('devise.failure.invalid') }
      format.json { render json: { success: false, message: I18n.t('devise.failure.invalid') }, status: :unauthorized }
    end
  end
end
```

### Task 3: Track Permission and Role Changes
**Description:** Monitor changes to user roles, permissions, and access levels.

**Implementation Notes:**
- Track user role assignments and changes
- Monitor permission modifications
- Log access control list updates

```ruby
# app/models/user.rb
class User < ApplicationRecord
  # ...existing code...
  
  after_update :log_role_changes, if: -> { saved_change_to_role? }
  after_update :log_permission_changes, if: -> { saved_changes.keys.any? { |k| k.to_s.include?('permission') || k.to_s.include?('access') } }
  
  private
  
  def log_role_changes
    old_role = previous_changes[:role].first
    new_role = previous_changes[:role].last
    
    SecurityEvent.create!(
      event_type: :role_changed,
      severity: :warning,
      user: self,
      business: business,
      ip_address: Current.request&.remote_ip,
      user_agent: Current.request&.user_agent,
      metadata: {
        changed_by_user_id: Current.user&.id,
        changed_by_user_name: Current.user&.name,
        previous_role: old_role,
        new_role: new_role
      }
    )
  end
  
  def log_permission_changes
    permission_changes = {}
    
    previous_changes.each do |attribute, values|
      next unless attribute.to_s.include?('permission') || attribute.to_s.include?('access')
      permission_changes[attribute] = { old: values.first, new: values.last }
    end
    
    return if permission_changes.empty?
    
    SecurityEvent.create!(
      event_type: :permissions_changed,
      severity: :warning,
      user: self,
      business: business,
      ip_address: Current.request&.remote_ip,
      user_agent: Current.request&.user_agent,
      metadata: {
        changed_by_user_id: Current.user&.id,
        changed_by_user_name: Current.user&.name,
        permission_changes: permission_changes
      }
    )
  end
end
```

```ruby
# app/controllers/admin/users_controller.rb
class Admin::UsersController < Admin::BaseController
  before_action :require_admin
  before_action :set_user, only: [:show, :edit, :update, :destroy]
  
  # ...existing code...
  
  def update
    was_successful = @user.update(user_params)
    
    # Log access to sensitive operations
    if was_successful && permission_params_present?
      SecurityEvent.create!(
        event_type: :permissions_changed,
        severity: :warning,
        user: @user,
        business: current_business,
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: {
          changed_by_user_id: current_user.id,
          changed_by_user_name: current_user.name,
          changes: user_params.to_h
        }
      )
    end
    
    # ...existing response code...
  end
  
  private
  
  def permission_params_present?
    (user_params.keys & %w[role admin permissions access_level]).any?
  end
end
```

### Task 4: Build Security Events Dashboard
**Description:** Create an interface for monitoring and analyzing security events.

**Implementation Notes:**
- Implement security events controller and views
- Add search and filtering functionality
- Create visualizations for security events
- Build alert system for critical security events

```ruby
# app/controllers/admin/security_events_controller.rb
class Admin::SecurityEventsController < Admin::BaseController
  before_action :require_admin
  
  def index
    @security_events = current_business.security_events
      .includes(:user)
      .order(created_at: :desc)
    
    if params[:user_id].present?
      @security_events = @security_events.where(user_id: params[:user_id])
    end
    
    if params[:event_type].present?
      @security_events = @security_events.where(event_type: params[:event_type])
    end
    
    if params[:severity].present?
      @security_events = @security_events.where(severity: params[:severity])
    end
    
    if params[:date_from].present?
      @security_events = @security_events.where("created_at >= ?", Date.parse(params[:date_from]).beginning_of_day)
    end
    
    if params[:date_to].present?
      @security_events = @security_events.where("created_at <= ?", Date.parse(params[:date_to]).end_of_day)
    end
    
    if params[:ip_address].present?
      @security_events = @security_events.where(ip_address: params[:ip_address])
    end
    
    @security_events = @security_events.paginate(page: params[:page], per_page: 30)
    
    # Stats for dashboard widgets
    @events_by_type = current_business.security_events
      .where("created_at >= ?", 30.days.ago)
      .group(:event_type)
      .count
      
    @events_by_severity = current_business.security_events
      .where("created_at >= ?", 30.days.ago)
      .group(:severity)
      .count
      
    @users_with_most_failures = current_business.security_events
      .where(event_type: :login_failure)
      .where("created_at >= ?", 7.days.ago)
      .group(:user_id)
      .count
      .sort_by { |_, count| -count }
      .first(5)
      .map { |user_id, count| [User.find_by(id: user_id)&.name || 'Unknown', count] }
  end
  
  def show
    @security_event = current_business.security_events.find(params[:id])
  end
  
  def failed_logins
    @failed_logins = current_business.security_events
      .failures
      .includes(:user)
      .order(created_at: :desc)
      .paginate(page: params[:page], per_page: 30)
    
    # Group by IP address
    @grouped_failures = @failed_logins.group(:ip_address).count
    
    # Get top failure sources
    @top_failure_ips = @grouped_failures.sort_by { |_, count| -count }.first(10)
    
    # Group by day for chart
    @failures_by_day = @failed_logins
      .group("DATE(created_at)")
      .count
      .transform_keys { |k| k.to_date.to_s }
  end
  
  def permission_changes
    @permission_events = current_business.security_events
      .where(event_type: [:permissions_changed, :role_changed])
      .includes(:user)
      .order(created_at: :desc)
      .paginate(page: params[:page], per_page: 30)
  end
end
```

```erb
<!-- app/views/admin/security_events/index.html.erb -->
<div class="container mx-auto px-4 py-6">
  <div class="flex items-center justify-between mb-6">
    <h1 class="text-2xl font-bold">Security Events</h1>
    
    <div>
      <%= link_to "Failed Logins", failed_logins_admin_security_events_path, class: "mr-4 text-indigo-600 hover:text-indigo-800" %>
      <%= link_to "Permission Changes", permission_changes_admin_security_events_path, class: "text-indigo-600 hover:text-indigo-800" %>
    </div>
  </div>
  
  <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
    <div class="bg-white p-4 rounded-lg shadow">
      <h3 class="text-sm text-gray-500 uppercase font-medium">Critical Events</h3>
      <p class="text-2xl font-bold text-red-600"><%= @events_by_severity['critical'] || 0 %></p>
    </div>
    
    <div class="bg-white p-4 rounded-lg shadow">
      <h3 class="text-sm text-gray-500 uppercase font-medium">Error Events</h3>
      <p class="text-2xl font-bold text-orange-600"><%= @events_by_severity['error'] || 0 %></p>
    </div>
    
    <div class="bg-white p-4 rounded-lg shadow">
      <h3 class="text-sm text-gray-500 uppercase font-medium">Warning Events</h3>
      <p class="text-2xl font-bold text-yellow-600"><%= @events_by_severity['warning'] || 0 %></p>
    </div>
    
    <div class="bg-white p-4 rounded-lg shadow">
      <h3 class="text-sm text-gray-500 uppercase font-medium">Failed Logins</h3>
      <p class="text-2xl font-bold text-blue-600"><%= @events_by_type['login_failure'] || 0 %></p>
    </div>
  </div>
  
  <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
    <div class="bg-white p-4 rounded-lg shadow">
      <h2 class="font-semibold text-lg mb-4">Events by Type</h2>
      <div class="h-64">
        <canvas id="eventsTypeChart"></canvas>
      </div>
    </div>
    
    <div class="bg-white p-4 rounded-lg shadow">
      <h2 class="font-semibold text-lg mb-4">Users with Failed Logins</h2>
      <% if @users_with_most_failures.any? %>
        <div class="overflow-hidden">
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">User</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Failed Attempts</th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
              <% @users_with_most_failures.each do |name, count| %>
                <tr>
                  <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900"><%= name %></td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500"><%= count %></td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% else %>
        <p class="text-gray-500 text-center py-8">No failed login data to display</p>
      <% end %>
    </div>
  </div>
  
  <div class="bg-white rounded-lg shadow mb-6 p-4">
    <h2 class="text-lg font-semibold mb-4">Filter Security Events</h2>
    
    <%= form_with url: admin_security_events_path, method: :get, class: "space-y-4", local: true do |f| %>
      <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div>
          <%= f.label :event_type, "Event Type", class: "block text-sm font-medium text-gray-700 mb-1" %>
          <%= f.select :event_type, 
            options_for_select(SecurityEvent.event_types.map { |k, v| [k.humanize, k] }, params[:event_type]), 
            { include_blank: "All Events" }, 
            class: "w-full border-gray-300 rounded-md shadow-sm focus:border-indigo-300 focus:ring focus:ring-indigo-200 focus:ring-opacity-50" %>
        </div>
        
        <div>
          <%= f.label :severity, "Severity", class: "block text-sm font-medium text-gray-700 mb-1" %>
          <%= f.select :severity, 
            options_for_select([
              ['Info', 'info'],
              ['Warning', 'warning'],
              ['Error', 'error'],
              ['Critical', 'critical']
            ], params[:severity]), 
            { include_blank: "All Severities" }, 
            class: "w-full border-gray-300 rounded-md shadow-sm focus:border-indigo-300 focus:ring focus:ring-indigo-200 focus:ring-opacity-50" %>
        </div>
        
        <div>
          <%= f.label :user_id, "User", class: "block text-sm font-medium text-gray-700 mb-1" %>
          <%= f.select :user_id, 
            options_from_collection_for_select(current_business.users, 'id', 'name', params[:user_id]), 
            { include_blank: "All Users" }, 
            class: "w-full border-gray-300 rounded-md shadow-sm focus:border-indigo-300 focus:ring focus:ring-indigo-200 focus:ring-opacity-50" %>
        </div>
      </div>
      
      <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div>
          <%= f.label :date_from, "From Date", class: "block text-sm font-medium text-gray-700 mb-1" %>
          <%= f.date_field :date_from, value: params[:date_from], class: "w-full border-gray-300 rounded-md shadow-sm focus:border-indigo-300 focus:ring focus:ring-indigo-200 focus:ring-opacity-50" %>
        </div>
        
        <div>
          <%= f.label :date_to, "To Date", class: "block text-sm font-medium text-gray-700 mb-1" %>
          <%= f.date_field :date_to, value: params[:date_to], class: "w-full border-gray-300 rounded-md shadow-sm focus:border-indigo-300 focus:ring focus:ring-indigo-200 focus:ring-opacity-50" %>
        </div>
        
        <div>
          <%= f.label :ip_address, "IP Address", class: "block text-sm font-medium text-gray-700 mb-1" %>
          <%= f.text_field :ip_address, value: params[:ip_address], placeholder: "e.g. 192.168.1.1", class: "w-full border-gray-300 rounded-md shadow-sm focus:border-indigo-300 focus:ring focus:ring-indigo-200 focus:ring-opacity-50" %>
        </div>
      </div>
      
      <div>
        <%= f.submit "Apply Filters", class: "bg-indigo-600 hover:bg-indigo-700 text-white font-semibold py-2 px-4 rounded" %>
        <%= link_to "Reset", admin_security_events_path, class: "ml-2 text-indigo-600 hover:text-indigo-800" %>
      </div>
    <% end %>
  </div>
  
  <div class="bg-white rounded-lg shadow overflow-hidden">
    <table class="min-w-full divide-y divide-gray-200">
      <thead class="bg-gray-50">
        <tr>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Time</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Event</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Severity</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">User</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">IP Address</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"></th>
        </tr>
      </thead>
      <tbody class="bg-white divide-y divide-gray-200">
        <% @security_events.each do |event| %>
          <tr>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
              <%= event.created_at.strftime("%b %d, %Y %H:%M:%S") %>
            </td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
              <%= event.event_type.humanize %>
            </td>
            <td class="px-6 py-4 whitespace-nowrap">
              <%= severity_badge(event.severity) %>
            </td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
              <% if event.user %>
                <%= link_to event.user.name, admin_user_path(event.user), class: "text-indigo-600 hover:text-indigo-900" %>
              <% else %>
                <span class="text-gray-500">N/A</span>
              <% end %>
            </td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
              <%= event.ip_address %>
            </td>
            <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
              <%= link_to "Details", admin_security_event_path(event), class: "text-indigo-600 hover:text-indigo-900" %>
            </td>
          </tr>
        <% end %>
        
        <% if @security_events.empty? %>
          <tr>
            <td colspan="6" class="px-6 py-4 text-center text-sm text-gray-500">
              No security events found with the current filters.
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
    
    <div class="px-4 py-3 border-t border-gray-200">
      <%= will_paginate @security_events, class: "pagination" %>
    </div>
  </div>
</div>

<script>
  document.addEventListener('DOMContentLoaded', function() {
    // Events by type chart
    const eventTypesCtx = document.getElementById('eventsTypeChart').getContext('2d');
    const eventTypesData = <%= raw @events_by_type.to_json %>;
    
    const labels = Object.keys(eventTypesData).map(key => key.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase()));
    const data = Object.values(eventTypesData);
    
    new Chart(eventTypesCtx, {
      type: 'bar',
      data: {
        labels: labels,
        datasets: [{
          label: 'Count',
          data: data,
          backgroundColor: [
            'rgba(54, 162, 235, 0.2)',
            'rgba(255, 99, 132, 0.2)',
            'rgba(255, 206, 86, 0.2)',
            'rgba(75, 192, 192, 0.2)',
            'rgba(153, 102, 255, 0.2)',
            'rgba(255, 159, 64, 0.2)'
          ],
          borderColor: [
            'rgba(54, 162, 235, 1)',
            'rgba(255, 99, 132, 1)',
            'rgba(255, 206, 86, 1)',
            'rgba(75, 192, 192, 1)',
            'rgba(153, 102, 255, 1)',
            'rgba(255, 159, 64, 1)'
          ],
          borderWidth: 1
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
        }
      }
    });
  });
</script>
```

```ruby
# app/helpers/admin/security_events_helper.rb
module Admin::SecurityEventsHelper
  def severity_badge(severity)
    case severity.to_sym
    when :info
      content_tag :span, "Info", class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800"
    when :warning
      content_tag :span, "Warning", class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-yellow-100 text-yellow-800"
    when :error
      content_tag :span, "Error", class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-orange-100 text-orange-800"
    when :critical
      content_tag :span, "Critical", class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-800"
    else
      content_tag :span, severity.to_s.humanize, class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800"
    end
  end
end
```

### Task 5: Implement Security Alerts and Notifications
**Description:** Create a notification system for critical security events.

**Implementation Notes:**
- Implement real-time alerts for critical security events
- Send email notifications for serious security incidents
- Create in-app notifications for security events
- Set up configurable alert thresholds

```ruby
# app/models/concerns/security_alertable.rb
module SecurityAlertable
  extend ActiveSupport::Concern
  
  class_methods do
    def security_thresholds
      {
        login_failure: { count: 5, window: 1.hour, level: :warning },
        critical_events: { count: 1, window: 24.hours, level: :critical }
      }
    end
  end
  
  def send_security_alert(event)
    return unless should_send_alert?(event)
    
    case event.severity
    when 'critical'
      SecurityAlertMailer.critical_alert(event).deliver_later
      notify_security_team(event)
    when 'error'
      SecurityAlertMailer.error_alert(event).deliver_later if event.event_type == 'login_failure' && excessive_failed_logins?(event)
    end
    
    create_in_app_notification(event)
  end
  
  private
  
  def should_send_alert?(event)
    return true if event.severity == 'critical'
    
    case event.event_type
    when 'login_failure'
      excessive_failed_logins?(event)
    when 'permissions_changed', 'role_changed'
      true
    else
      false
    end
  end
  
  def excessive_failed_logins?(event)
    threshold = self.class.security_thresholds[:login_failure]
    
    return false unless threshold
    
    ip_address = event.ip_address
    
    count = SecurityEvent.where(
      event_type: :login_failure,
      ip_address: ip_address,
      created_at: threshold[:window].ago..
    ).count
    
    count >= threshold[:count]
  end
  
  def notify_security_team(event)
    # This could send an SMS, Slack notification, or other immediate alert
    SecurityNotificationService.new(event).deliver
  end
  
  def create_in_app_notification(event)
    notification_text = case event.event_type
                         when 'login_failure'
                           "Multiple failed login attempts detected"
                         when 'permissions_changed'
                           "User permissions were changed"
                         when 'role_changed'
                           "User role was changed"
                         else
                           "Security event: #{event.event_type.humanize}"
                         end
                         
    admin_users = User.where(business_id: event.business_id).admins
    
    admin_users.each do |admin|
      Notification.create!(
        user: admin,
        notification_type: :security_alert,
        title: "Security Alert: #{event.severity.upcase}",
        message: notification_text,
        metadata: {
          security_event_id: event.id,
          event_type: event.event_type,
          severity: event.severity
        }
      )
    end
  end
end
```

```ruby
# app/models/security_event.rb
class SecurityEvent < ApplicationRecord
  include SecurityAlertable
  
  # ... existing code ...
  
  after_create :process_security_alerts
  
  private
  
  def process_security_alerts
    send_security_alert(self)
  end
end
```

```ruby
# app/mailers/security_alert_mailer.rb
class SecurityAlertMailer < ApplicationMailer
  def critical_alert(event)
    @event = event
    @business = event.business
    
    admin_emails = User.where(business_id: @business.id).admins.pluck(:email)
    
    mail(
      to: admin_emails,
      subject: "[CRITICAL] Security Alert - #{@event.event_type.humanize}"
    )
  end
  
  def error_alert(event)
    @event = event
    @business = event.business
    
    admin_emails = User.where(business_id: @business.id).admins.pluck(:email)
    
    mail(
      to: admin_emails,
      subject: "[WARNING] Security Alert - #{@event.event_type.humanize}"
    )
  end
end
```

## Security Considerations
- Ensure sensitive information is not logged (passwords, tokens)
- Protect access to security event data
- Consider storage and retention implications
- Ensure IP addresses are stored in compliance with privacy laws
- Implement appropriate data retention and archiving policies

## Testing Strategy
- Unit tests for SecurityEvent model
- Integration tests for authentication hooks
- End-to-end tests for security event generation
- Performance tests for high-volume logging

## Rollout Plan
1. Implement core security event tracking
2. Add login failure monitoring
3. Deploy permission change tracking
4. Add security alert notifications
5. Enable real-time security monitoring dashboard
