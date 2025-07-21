# Feature: Change Audit Logging

## Overview
Implement a comprehensive audit logging system to track all data modifications across the platform. This system will record who changed what data, when they made the change, and what the old and new values were. This provides accountability, supports data integrity, and enables troubleshooting and compliance.

## Goals
- Track all significant data modifications across the platform
- Provide full visibility into who made changes and when
- Maintain a historical record of all data state transitions
- Support compliance requirements for data change records
- Enable troubleshooting of data issues through historical context

## User Stories
- As a business owner, I want to see when and who changed sensitive business data so I can maintain oversight
- As an administrator, I want to review historical changes to any record so I can understand its evolution
- As a support representative, I want to track changes to help troubleshoot customer issues
- As a business owner, I want proof of changes for liability protection and compliance
- As an administrator, I want to identify unauthorized or inappropriate data changes

## Tasks

### Task 1: Create Audit Log Models and Database Structure
**Description:** Build the core models and database structure to support comprehensive change tracking.

**Implementation Notes:**
- Create `AuditLog` model and migration
- Implement polymorphic association for tracking any entity
- Add indexes for efficient querying

```ruby
# app/models/audit_log.rb
class AuditLog < ApplicationRecord
  belongs_to :business
  belongs_to :user, optional: true
  belongs_to :auditable, polymorphic: true, optional: true
  
  validates :action, :table_name, presence: true
  
  enum action: { create: 0, update: 1, destroy: 2 }
  
  serialize :old_values, Hash
  serialize :new_values, Hash
  
  scope :recent, -> { where(created_at: 30.days.ago..) }
  scope :for_user, ->(user) { where(user: user) }
  scope :for_table, ->(table) { where(table_name: table) }
  scope :for_record, ->(record_id, record_type) { 
    where(auditable_id: record_id, auditable_type: record_type) 
  }
  
  def changes_summary
    return "Created #{auditable_type}" if create?
    return "Deleted #{auditable_type}" if destroy?
    
    changed_fields = []
    new_values.each do |field, value|
      old_value = old_values[field]
      if old_value != value
        changed_fields << field
      end
    end
    
    "Updated #{changed_fields.join(', ')} on #{auditable_type}"
  end
end
```

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_audit_logs.rb
class CreateAuditLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :audit_logs do |t|
      t.references :business, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.references :auditable, polymorphic: true, null: true
      t.string :table_name, null: false
      t.integer :action, null: false, default: 0
      t.text :old_values
      t.text :new_values
      t.string :ip_address
      t.string :user_agent
      t.timestamps null: false
    end
    
    add_index :audit_logs, [:business_id, :created_at]
    add_index :audit_logs, [:table_name, :created_at]
    add_index :audit_logs, [:auditable_id, :auditable_type]
  end
end
```

### Task 2: Implement Auditable Concern for Models
**Description:** Create a reusable concern to easily add audit logging capability to any model.

**Implementation Notes:**
- Create an Auditable concern
- Implement callbacks for tracking changes
- Add configuration for customizing tracked attributes

```ruby
# app/models/concerns/auditable.rb
module Auditable
  extend ActiveSupport::Concern
  
  included do
    after_create :log_create
    before_update :store_old_values
    after_update :log_update
    before_destroy :log_destroy
    
    class_attribute :audited_attributes
    class_attribute :excluded_attributes
    
    self.excluded_attributes = %w(updated_at created_at)
  end
  
  class_methods do
    def audited(*args)
      self.audited_attributes = args.map(&:to_s)
    end
    
    def skip_auditing(*args)
      self.excluded_attributes += args.map(&:to_s)
    end
  end
  
  private
  
  def store_old_values
    @old_values = attributes_for_audit
  end
  
  def log_create
    return unless auditing_enabled?
    
    AuditLog.create!(
      business: auditable_business,
      user: current_user,
      auditable: self,
      table_name: self.class.table_name,
      action: :create,
      old_values: {},
      new_values: attributes_for_audit,
      ip_address: Current.ip_address,
      user_agent: Current.user_agent
    )
  end
  
  def log_update
    return unless auditing_enabled?
    return unless values_changed?
    
    AuditLog.create!(
      business: auditable_business,
      user: current_user,
      auditable: self,
      table_name: self.class.table_name,
      action: :update,
      old_values: @old_values,
      new_values: attributes_for_audit,
      ip_address: Current.ip_address,
      user_agent: Current.user_agent
    )
  end
  
  def log_destroy
    return unless auditing_enabled?
    
    AuditLog.create!(
      business: auditable_business,
      user: current_user,
      auditable: self,
      table_name: self.class.table_name,
      action: :destroy,
      old_values: attributes_for_audit,
      new_values: {},
      ip_address: Current.ip_address,
      user_agent: Current.user_agent
    )
  end
  
  def attributes_for_audit
    if self.class.audited_attributes.present?
      attrs = attributes.slice(*self.class.audited_attributes)
    else
      attrs = attributes.except(*self.class.excluded_attributes)
    end
    
    # Handle any special serialization or normalization
    self.class.columns_hash.each_key do |key|
      next unless attrs.key?(key)
      
      if self.class.columns_hash[key].type == :datetime && attrs[key].present?
        attrs[key] = attrs[key].utc.to_s
      elsif self.class.columns_hash[key].type == :jsonb || self.class.columns_hash[key].type == :json
        attrs[key] = attrs[key].to_json if attrs[key].present?
      end
    end
    
    attrs
  end
  
  def values_changed?
    return false if @old_values.blank?
    
    current_values = attributes_for_audit
    
    @old_values.each do |key, old_value|
      return true if current_values[key] != old_value
    end
    
    false
  end
  
  def current_user
    Current.user
  end
  
  def auditable_business
    respond_to?(:business) ? business : (Current.user&.business || Current.business)
  end
  
  def auditing_enabled?
    Rails.application.config.auditing_enabled
  end
end
```

```ruby
# app/models/current.rb
class Current < ActiveSupport::CurrentAttributes
  attribute :user, :business
  attribute :ip_address, :user_agent
end
```

```ruby
# config/initializers/auditing.rb
Rails.application.config.auditing_enabled = true

# Disable in test environment by default
Rails.application.config.auditing_enabled = false if Rails.env.test?
```

### Task 3: Create Audit Log Controller and Views
**Description:** Build the admin interface to view, search, and filter audit logs.

**Implementation Notes:**
- Create admin controller for audit logs
- Implement search and filtering functionality
- Build views with pagination and filtering controls

```ruby
# app/controllers/admin/audit_logs_controller.rb
class Admin::AuditLogsController < Admin::BaseController
  before_action :require_admin
  
  def index
    @audit_logs = current_business.audit_logs
      .includes(:user)
      .order(created_at: :desc)
    
    if params[:user_id].present?
      @audit_logs = @audit_logs.where(user_id: params[:user_id])
    end
    
    if params[:table_name].present?
      @audit_logs = @audit_logs.where(table_name: params[:table_name])
    end
    
    if params[:action_type].present?
      @audit_logs = @audit_logs.where(action: params[:action_type])
    end
    
    if params[:date_from].present?
      @audit_logs = @audit_logs.where("created_at >= ?", Date.parse(params[:date_from]).beginning_of_day)
    end
    
    if params[:date_to].present?
      @audit_logs = @audit_logs.where("created_at <= ?", Date.parse(params[:date_to]).end_of_day)
    end
    
    @audit_logs = @audit_logs.paginate(page: params[:page], per_page: 25)
    
    @table_names = current_business.audit_logs.distinct.pluck(:table_name)
    @users = current_business.users
  end
  
  def show
    @audit_log = current_business.audit_logs.find(params[:id])
    
    # If audit log is for a record that still exists, fetch the current record
    if @audit_log.auditable_id.present? && @audit_log.auditable_type.present?
      @record = @audit_log.auditable_type.constantize.find_by(id: @audit_log.auditable_id)
    end
  end
  
  def record_history
    @auditable_type = params[:auditable_type]
    @auditable_id = params[:auditable_id]
    
    @audit_logs = current_business.audit_logs
      .where(auditable_type: @auditable_type, auditable_id: @auditable_id)
      .includes(:user)
      .order(created_at: :desc)
      .paginate(page: params[:page], per_page: 25)
      
    @record = @auditable_type.constantize.find_by(id: @auditable_id)
  end
end
```

```erb
<!-- app/views/admin/audit_logs/index.html.erb -->
<div class="container mx-auto px-4 py-6">
  <h1 class="text-2xl font-bold mb-6">Audit Logs</h1>
  
  <div class="bg-white rounded-lg shadow mb-6 p-4">
    <h2 class="text-lg font-semibold mb-4">Filter Logs</h2>
    
    <%= form_with url: admin_audit_logs_path, method: :get, class: "space-y-4", local: true do |f| %>
      <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div>
          <%= f.label :table_name, "Table", class: "block text-sm font-medium text-gray-700 mb-1" %>
          <%= f.select :table_name, 
            options_for_select(@table_names, params[:table_name]), 
            { include_blank: "All Tables" }, 
            class: "w-full border-gray-300 rounded-md shadow-sm focus:border-indigo-300 focus:ring focus:ring-indigo-200 focus:ring-opacity-50" %>
        </div>
        
        <div>
          <%= f.label :user_id, "User", class: "block text-sm font-medium text-gray-700 mb-1" %>
          <%= f.select :user_id, 
            options_from_collection_for_select(@users, 'id', 'name', params[:user_id]), 
            { include_blank: "All Users" }, 
            class: "w-full border-gray-300 rounded-md shadow-sm focus:border-indigo-300 focus:ring focus:ring-indigo-200 focus:ring-opacity-50" %>
        </div>
        
        <div>
          <%= f.label :action_type, "Action", class: "block text-sm font-medium text-gray-700 mb-1" %>
          <%= f.select :action_type, 
            options_for_select([['Create', 'create'], ['Update', 'update'], ['Delete', 'destroy']], params[:action_type]), 
            { include_blank: "All Actions" }, 
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
        <%= link_to "Reset", admin_audit_logs_path, class: "ml-2 text-indigo-600 hover:text-indigo-800" %>
      </div>
    <% end %>
  </div>
  
  <div class="bg-white rounded-lg shadow overflow-hidden">
    <table class="min-w-full divide-y divide-gray-200">
      <thead class="bg-gray-50">
        <tr>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Time</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">User</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Action</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Table</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Record</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Changes</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"></th>
        </tr>
      </thead>
      <tbody class="bg-white divide-y divide-gray-200">
        <% @audit_logs.each do |log| %>
          <tr>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
              <%= log.created_at.strftime("%b %d, %Y %H:%M:%S") %>
            </td>
            <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
              <%= log.user&.name || "System" %>
            </td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
              <%= action_badge(log.action) %>
            </td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
              <%= log.table_name.humanize %>
            </td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
              <% if log.auditable_id.present? %>
                #<%= log.auditable_id %>
              <% else %>
                N/A
              <% end %>
            </td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
              <%= log.changes_summary %>
            </td>
            <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
              <%= link_to "View", admin_audit_log_path(log), class: "text-indigo-600 hover:text-indigo-900" %>
            </td>
          </tr>
        <% end %>
        
        <% if @audit_logs.empty? %>
          <tr>
            <td colspan="7" class="px-6 py-4 text-center text-sm text-gray-500">
              No audit logs found with the current filters.
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
    
    <div class="px-4 py-3 border-t border-gray-200">
      <%= will_paginate @audit_logs, class: "pagination" %>
    </div>
  </div>
</div>
```

```erb
<!-- app/views/admin/audit_logs/show.html.erb -->
<div class="container mx-auto px-4 py-6">
  <div class="flex justify-between items-center mb-6">
    <h1 class="text-2xl font-bold">Audit Log Details</h1>
    <%= link_to "← Back to Audit Logs", admin_audit_logs_path, class: "text-indigo-600 hover:text-indigo-800" %>
  </div>
  
  <div class="bg-white rounded-lg shadow overflow-hidden mb-6">
    <div class="p-6">
      <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div>
          <h2 class="text-lg font-medium text-gray-900 mb-2">General Information</h2>
          <dl class="grid grid-cols-1 sm:grid-cols-2 gap-x-4 gap-y-2">
            <dt class="text-sm font-medium text-gray-500">Action</dt>
            <dd class="text-sm text-gray-900"><%= action_badge(@audit_log.action) %></dd>
            
            <dt class="text-sm font-medium text-gray-500">User</dt>
            <dd class="text-sm text-gray-900"><%= @audit_log.user&.name || "System" %></dd>
            
            <dt class="text-sm font-medium text-gray-500">Date/Time</dt>
            <dd class="text-sm text-gray-900"><%= @audit_log.created_at.strftime("%B %d, %Y %H:%M:%S") %></dd>
            
            <dt class="text-sm font-medium text-gray-500">Table</dt>
            <dd class="text-sm text-gray-900"><%= @audit_log.table_name.humanize %></dd>
            
            <dt class="text-sm font-medium text-gray-500">IP Address</dt>
            <dd class="text-sm text-gray-900"><%= @audit_log.ip_address || "Not recorded" %></dd>
          </dl>
        </div>
        
        <div>
          <h2 class="text-lg font-medium text-gray-900 mb-2">Record Information</h2>
          <% if @audit_log.auditable_id.present? %>
            <dl class="grid grid-cols-1 sm:grid-cols-2 gap-x-4 gap-y-2">
              <dt class="text-sm font-medium text-gray-500">Record Type</dt>
              <dd class="text-sm text-gray-900"><%= @audit_log.auditable_type.demodulize.humanize %></dd>
              
              <dt class="text-sm font-medium text-gray-500">Record ID</dt>
              <dd class="text-sm text-gray-900">#<%= @audit_log.auditable_id %></dd>
              
              <dt class="text-sm font-medium text-gray-500">Current Status</dt>
              <dd class="text-sm text-gray-900">
                <% if @record.present? %>
                  <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
                    Exists
                  </span>
                <% else %>
                  <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-800">
                    Deleted
                  </span>
                <% end %>
              </dd>
            </dl>
            
            <div class="mt-4">
              <%= link_to "View Record History", record_history_admin_audit_logs_path(auditable_type: @audit_log.auditable_type, auditable_id: @audit_log.auditable_id), class: "text-indigo-600 hover:text-indigo-800 text-sm font-medium" %>
              
              <% if @record.present? && respond_to?(:polymorphic_path, @record) %>
                <%= link_to "View Current Record", polymorphic_path([:admin, @record]), class: "ml-4 text-indigo-600 hover:text-indigo-800 text-sm font-medium" %>
              <% end %>
            </div>
          <% else %>
            <p class="text-sm text-gray-500">This audit log is not associated with a specific record.</p>
          <% end %>
        </div>
      </div>
      
      <div class="mt-6">
        <h2 class="text-lg font-medium text-gray-900 mb-2">Changes</h2>
        
        <% if @audit_log.create? %>
          <div class="bg-green-50 border border-green-200 rounded-md p-4">
            <h3 class="text-sm font-medium text-green-800 mb-2">Record Created</h3>
            <div class="overflow-x-auto">
              <table class="min-w-full divide-y divide-gray-200">
                <thead>
                  <tr>
                    <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Field</th>
                    <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Value</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-gray-200">
                  <% @audit_log.new_values.each do |field, value| %>
                    <tr>
                      <td class="px-4 py-2 text-sm font-medium text-gray-900"><%= field.humanize %></td>
                      <td class="px-4 py-2 text-sm text-gray-500"><%= format_audit_value(value) %></td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>
        <% elsif @audit_log.destroy? %>
          <div class="bg-red-50 border border-red-200 rounded-md p-4">
            <h3 class="text-sm font-medium text-red-800 mb-2">Record Deleted</h3>
            <div class="overflow-x-auto">
              <table class="min-w-full divide-y divide-gray-200">
                <thead>
                  <tr>
                    <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Field</th>
                    <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Value at Deletion</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-gray-200">
                  <% @audit_log.old_values.each do |field, value| %>
                    <tr>
                      <td class="px-4 py-2 text-sm font-medium text-gray-900"><%= field.humanize %></td>
                      <td class="px-4 py-2 text-sm text-gray-500"><%= format_audit_value(value) %></td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>
        <% else %>
          <div class="bg-yellow-50 border border-yellow-200 rounded-md p-4">
            <h3 class="text-sm font-medium text-yellow-800 mb-2">Record Updated</h3>
            <div class="overflow-x-auto">
              <table class="min-w-full divide-y divide-gray-200">
                <thead>
                  <tr>
                    <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Field</th>
                    <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Previous Value</th>
                    <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">New Value</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-gray-200">
                  <% @audit_log.new_values.each do |field, new_value| %>
                    <% old_value = @audit_log.old_values[field] %>
                    <% if old_value != new_value %>
                      <tr>
                        <td class="px-4 py-2 text-sm font-medium text-gray-900"><%= field.humanize %></td>
                        <td class="px-4 py-2 text-sm text-gray-500"><%= format_audit_value(old_value) %></td>
                        <td class="px-4 py-2 text-sm text-gray-500"><%= format_audit_value(new_value) %></td>
                      </tr>
                    <% end %>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>
        <% end %>
      </div>
    </div>
  </div>
</div>
```

### Task 4: Implement Controller Concerns for Capturing Context
**Description:** Create mechanism to capture HTTP request context for audit logging.

**Implementation Notes:**
- Create a controller concern for capturing audit context
- Add middleware to set IP and user agent information
- Ensure context is available to background jobs

```ruby
# app/controllers/concerns/audit_logging.rb
module AuditLogging
  extend ActiveSupport::Concern
  
  included do
    before_action :set_audit_context
  end
  
  private
  
  def set_audit_context
    Current.user = current_user
    Current.business = current_business
    Current.ip_address = request.remote_ip
    Current.user_agent = request.user_agent
  end
end
```

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  include AuditLogging
  
  # ...existing code...
end
```

```ruby
# app/helpers/admin/audit_logs_helper.rb
module Admin::AuditLogsHelper
  def action_badge(action)
    case action.to_sym
    when :create
      content_tag :span, "Created", class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800"
    when :update
      content_tag :span, "Updated", class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-yellow-100 text-yellow-800"
    when :destroy
      content_tag :span, "Deleted", class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-800"
    else
      content_tag :span, action.to_s.humanize, class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800"
    end
  end
  
  def format_audit_value(value)
    case value
    when NilClass
      content_tag :span, "nil", class: "text-gray-400 italic"
    when TrueClass
      content_tag :span, "true", class: "text-green-600 font-medium"
    when FalseClass
      content_tag :span, "false", class: "text-red-600 font-medium"
    when String
      if value.blank?
        content_tag :span, "(empty string)", class: "text-gray-400 italic"
      else
        value
      end
    else
      value.to_s
    end
  end
end
```

## Security Considerations
- Ensure sensitive data like passwords are not logged
- Implement proper access controls to audit log data
- Consider data volume and storage implications
- Ensure IP addresses are handled in compliance with privacy laws
- Add data retention policies for audit log data

## Testing Strategy
- Unit tests for the Auditable concern
- Integration tests for audit logging in various models
- Controller tests to verify context capture
- View tests for the admin interface

## Rollout Plan
1. Add audit logging to critical models (Users, Business, Pricing)
2. Deploy with monitoring for performance impact
3. Gradually enable on remaining models
4. Add admin interface for audit log review
5. Document audit log capabilities for business owners
