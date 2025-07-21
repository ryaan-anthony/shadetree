# Epic: Audit & Activity Logs

## Overview
Provide comprehensive audit logging and activity monitoring capabilities to track who changed what and when throughout the platform. Enable business owners to monitor team activities, maintain compliance records, and troubleshoot issues with detailed change tracking.

## Goals
- Maintain complete audit trail for compliance and security
- Enable business owners to monitor staff activities and changes
- Provide detailed change tracking for sensitive business operations
- Support troubleshooting and issue resolution with activity logs
- Ensure accountability and transparency in business operations

## Success Metrics
- Audit log completeness rate = 100% for tracked actions
- Log query response time < 2 seconds
- Audit log retention compliance = 100%
- Activity monitoring adoption > 70% of business owners
- Issue resolution time reduction > 40% with audit trails

## User Stories
- As a business owner, I want to see who changed my pricing so I can maintain control over my business
- As a business owner, I want to track staff activities so I can monitor productivity and compliance
- As an admin, I want to see all quote modifications so I can ensure data integrity
- As a business owner, I want audit logs for compliance with industry regulations
- As a support agent, I want to see user activity to help troubleshoot issues

## Features

### Scale Phase (P3 - Enterprise Features)
1. [Change Audit Logging](audit-logs/01-change-tracking.md) - Track all data modifications with user attribution
2. [Activity Monitoring](audit-logs/02-activity-monitoring.md) - Monitor user sessions and business operations
3. [Access Audit Trail](audit-logs/03-access-tracking.md) - Track login attempts and permission changes
4. [Compliance Reporting](audit-logs/04-compliance-reports.md) - Generate audit reports for regulatory compliance

## Technical Architecture

### Core Models
```ruby
# Audit log for data changes
class AuditLog < ApplicationRecord
  belongs_to :business
  belongs_to :user, optional: true # System actions may not have user
  belongs_to :auditable, polymorphic: true
  
  validates :action, :table_name, presence: true
  
  enum action: { create: 0, update: 1, destroy: 2 }
  
  # JSON fields for change tracking
  validates :old_values, :new_values, presence: true
  
  scope :recent, -> { where(created_at: 30.days.ago..) }
  scope :for_user, ->(user) { where(user: user) }
  scope :for_table, ->(table) { where(table_name: table) }
  
  def changes_summary
    return "Created #{auditable_type}" if create?
    return "Deleted #{auditable_type}" if destroy?
    
    changed_fields = new_values.keys - old_values.keys
    "Updated #{changed_fields.join(', ')} on #{auditable_type}"
  end
end

# User activity tracking
class ActivityLog < ApplicationRecord
  belongs_to :business
  belongs_to :user
  
  validates :action_type, :controller, :action, presence: true
  
  enum action_type: {
    page_view: 0,
    form_submit: 1,
    file_upload: 2,
    export: 3,
    login: 4,
    logout: 5,
    api_call: 6
  }
  
  # Store request details
  validates :ip_address, :user_agent, presence: true
  
  scope :recent, -> { where(created_at: 7.days.ago..) }
  scope :by_action, ->(action) { where(action_type: action) }
  scope :login_attempts, -> { where(action_type: ['login', 'logout']) }
end

# Security event tracking
class SecurityEvent < ApplicationRecord
  belongs_to :business, optional: true
  belongs_to :user, optional: true
  
  validates :event_type, :severity, presence: true
  
  enum event_type: {
    failed_login: 0,
    permission_denied: 1,
    suspicious_activity: 2,
    data_breach_attempt: 3,
    role_change: 4,
    integration_error: 5
  }
  
  enum severity: { low: 0, medium: 1, high: 2, critical: 3 }
  
  scope :recent, -> { where(created_at: 24.hours.ago..) }
  scope :high_severity, -> { where(severity: ['high', 'critical']) }
end
```

### Audit Logging Service
```ruby
class AuditLogger
  def self.log_change(record, user, action)
    return unless should_audit?(record)
    
    business = determine_business(record)
    
    AuditLog.create!(
      business: business,
      user: user,
      auditable: record,
      action: action,
      table_name: record.class.table_name,
      old_values: record.changes.transform_values(&:first),
      new_values: record.changes.transform_values(&:second),
      ip_address: Current.ip_address,
      user_agent: Current.user_agent
    )
  end
  
  def self.log_activity(user, business, request_details)
    ActivityLog.create!(
      business: business,
      user: user,
      action_type: determine_action_type(request_details),
      controller: request_details[:controller],
      action: request_details[:action],
      path: request_details[:path],
      params: sanitize_params(request_details[:params]),
      ip_address: request_details[:ip],
      user_agent: request_details[:user_agent],
      response_time: request_details[:response_time]
    )
  end
  
  def self.log_security_event(event_type, details = {})
    SecurityEvent.create!(
      business: details[:business],
      user: details[:user],
      event_type: event_type,
      severity: determine_severity(event_type),
      description: details[:description],
      metadata: details[:metadata],
      ip_address: details[:ip_address] || Current.ip_address
    )
  end
  
  private
  
  def self.should_audit?(record)
    # Define which models should be audited
    audited_models = %w[
      Quote Business Service User BusinessUser
      Integration NotificationRule CustomField
    ]
    
    audited_models.include?(record.class.name)
  end
  
  def self.determine_business(record)
    return record if record.is_a?(Business)
    return record.business if record.respond_to?(:business)
    return record.user.businesses.first if record.respond_to?(:user)
    nil
  end
  
  def self.sanitize_params(params)
    # Remove sensitive data from logged parameters
    params.except('password', 'password_confirmation', 'authenticity_token')
  end
end
```

### Activity Monitoring Middleware
```ruby
class ActivityTrackingMiddleware
  def initialize(app)
    @app = app
  end
  
  def call(env)
    request = ActionDispatch::Request.new(env)
    
    # Skip tracking for certain paths
    return @app.call(env) if skip_tracking?(request.path)
    
    start_time = Time.current
    status, headers, response = @app.call(env)
    end_time = Time.current
    
    # Log activity if user is authenticated
    if (user = extract_user_from_session(request.session))
      log_request_activity(request, user, end_time - start_time)
    end
    
    [status, headers, response]
  end
  
  private
  
  def skip_tracking?(path)
    skip_paths = ['/assets/', '/health', '/ping', '/favicon.ico']
    skip_paths.any? { |skip_path| path.start_with?(skip_path) }
  end
  
  def extract_user_from_session(session)
    return nil unless session['user_id']
    User.find_by(id: session['user_id'])
  end
  
  def log_request_activity(request, user, response_time)
    business = determine_current_business(request, user)
    
    AuditLogger.log_activity(user, business, {
      controller: extract_controller(request),
      action: extract_action(request),
      path: request.path,
      params: request.params,
      ip: request.remote_ip,
      user_agent: request.user_agent,
      response_time: response_time
    })
  rescue => e
    Rails.logger.error "Activity logging failed: #{e.message}"
  end
end
```

### Audit Trail Query Service
```ruby
class AuditTrailService
  def initialize(business)
    @business = business
  end
  
  def activity_summary(user: nil, days: 30)
    logs = base_activity_query(days)
    logs = logs.for_user(user) if user
    
    {
      total_activities: logs.count,
      by_action_type: logs.group(:action_type).count,
      by_user: logs.joins(:user).group('users.name').count,
      recent_activities: logs.includes(:user).order(created_at: :desc).limit(50)
    }
  end
  
  def change_history(record, limit: 50)
    AuditLog.where(
      business: @business,
      auditable: record
    ).includes(:user).order(created_at: :desc).limit(limit)
  end
  
  def security_events(severity: nil, days: 7)
    events = SecurityEvent.where(
      business: @business,
      created_at: days.days.ago..Time.current
    )
    
    events = events.where(severity: severity) if severity
    events.includes(:user).order(created_at: :desc)
  end
  
  def compliance_report(start_date, end_date)
    {
      audit_logs: audit_logs_for_period(start_date, end_date),
      security_events: security_events_for_period(start_date, end_date),
      user_activities: user_activities_for_period(start_date, end_date),
      data_changes: data_changes_summary(start_date, end_date)
    }
  end
  
  private
  
  def base_activity_query(days)
    ActivityLog.where(
      business: @business,
      created_at: days.days.ago..Time.current
    )
  end
  
  def audit_logs_for_period(start_date, end_date)
    @business.audit_logs
      .where(created_at: start_date..end_date)
      .includes(:user, :auditable)
      .order(created_at: :desc)
  end
end
```

## Integration Points
- All Admin Portal features (audit all business-critical changes)
- User Authentication (login/logout activity tracking)
- Business Profile Management (profile change auditing)
- Quote Management (quote modification tracking)
- Staff Management (role change auditing)

## Security Considerations
- Encrypt sensitive audit log data
- Implement secure log storage with tamper detection
- Ensure audit logs cannot be modified by users
- Implement log retention policies for compliance
- Monitor audit system health and availability

## Scale Phase Scope (P3 Priority)
**Included in Scale Phase:**
- Comprehensive change tracking for all business data
- User activity monitoring and session tracking
- Security event logging and alerting
- Compliance reporting capabilities

**Future Enhancements:**
- Real-time audit alerting for suspicious activities
- Advanced audit analytics and anomaly detection
- Integration with external SIEM systems
- Automated compliance report generation

## Technical Implementation Notes
```ruby
# ActiveRecord concern for automatic audit logging
module Auditable
  extend ActiveSupport::Concern
  
  included do
    after_create :log_create_audit
    after_update :log_update_audit
    after_destroy :log_destroy_audit
  end
  
  private
  
  def log_create_audit
    AuditLogger.log_change(self, Current.user, :create)
  end
  
  def log_update_audit
    AuditLogger.log_change(self, Current.user, :update) if saved_changes.any?
  end
  
  def log_destroy_audit
    AuditLogger.log_change(self, Current.user, :destroy)
  end
end

# Usage in models
class Quote < ApplicationRecord
  include Auditable
  # ... rest of model
end

# Controller for audit trail viewing
class Admin::AuditController < Admin::BaseController
  def index
    @audit_service = AuditTrailService.new(current_business)
    @summary = @audit_service.activity_summary(days: params[:days]&.to_i || 30)
    @recent_changes = current_business.audit_logs
      .includes(:user, :auditable)
      .order(created_at: :desc)
      .limit(20)
  end
  
  def show
    record_type = params[:type].camelize.constantize
    record = current_business.send(params[:type].pluralize).find(params[:id])
    
    @audit_service = AuditTrailService.new(current_business)
    @change_history = @audit_service.change_history(record)
  end
end
```

## Migration for Audit Tables
```ruby
class CreateAuditLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :audit_logs do |t|
      t.references :business, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.references :auditable, polymorphic: true, null: false
      t.integer :action, null: false
      t.string :table_name, null: false
      t.json :old_values
      t.json :new_values
      t.string :ip_address
      t.text :user_agent
      
      t.timestamps
    end
    
    add_index :audit_logs, [:business_id, :created_at]
    add_index :audit_logs, [:auditable_type, :auditable_id]
    add_index :audit_logs, [:business_id, :user_id]
    add_index :audit_logs, [:business_id, :table_name]
  end
end

class CreateActivityLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :activity_logs do |t|
      t.references :business, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :action_type, null: false
      t.string :controller
      t.string :action
      t.string :path
      t.json :params
      t.string :ip_address
      t.text :user_agent
      t.decimal :response_time, precision: 8, scale: 3
      
      t.timestamps
    end
    
    add_index :activity_logs, [:business_id, :created_at]
    add_index :activity_logs, [:business_id, :user_id]
    add_index :activity_logs, [:business_id, :action_type]
  end
end
```

## Dependencies
- Current request context (for IP address, user agent)
- User authentication system
- Background job processing (for async log processing)
- Database indexing strategy for performance

## Estimate
- All Features: 18 story points (2 weeks)
- Note: This is a Scale Phase epic, not included in MVP
