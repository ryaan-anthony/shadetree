# Implementation Task: Audit & Compliance

## Overview
Create a comprehensive audit system that tracks all role and permission changes, providing compliance reporting and security monitoring.

## Technical Design

### Models
```ruby
class RoleAuditEvent < ApplicationRecord
  belongs_to :business
  belongs_to :user
  belongs_to :role, optional: true
  belongs_to :target_user, class_name: 'User', optional: true
  
  validates :event_type, inclusion: { 
    in: %w[role_created role_modified role_deleted assignment_created assignment_modified assignment_revoked]
  }
  
  # Store event details
  store :event_data, coder: JSON
  store :changes, coder: JSON
  
  scope :by_date_range, ->(start_date, end_date) { where(created_at: start_date..end_date) }
  scope :by_event_type, ->(type) { where(event_type: type) }
end

class ComplianceReport < ApplicationRecord
  belongs_to :business
  belongs_to :generated_by, class_name: 'User'
  has_one_attached :report_file
  
  validates :report_type, inclusion: { in: %w[full_audit role_review permission_review user_access] }
  validates :status, inclusion: { in: %w[pending generating completed failed] }
  
  # Store report parameters and results
  store :parameters, coder: JSON
  store :results, coder: JSON
end

class SecurityAlert < ApplicationRecord
  belongs_to :business
  belongs_to :role, optional: true
  belongs_to :user, optional: true
  
  validates :alert_type, inclusion: { in: %w[suspicious_assignment unauthorized_access role_conflict policy_violation] }
  validates :severity, inclusion: { in: %w[low medium high critical] }
  
  # Store alert details
  store :alert_data, coder: JSON
  store :resolution_data, coder: JSON
end
```

### Service Objects
```ruby
class AuditService
  def self.log_event(business, user, event_type, data = {})
    RoleAuditEvent.transaction do
      # Create audit event
      # Process event data
      # Check security policies
      # Trigger alerts if needed
    end
  end
  
  def self.generate_report(business, report_type, parameters = {})
    ComplianceReport.transaction do
      # Initialize report
      # Gather audit data
      # Generate report file
      # Store results
    end
  end
end

class ComplianceService
  def self.review_role_assignments(business)
    # Check role conflicts
    # Validate assignments
    # Review permissions
    # Generate findings
  end
  
  def self.check_security_policies(business)
    # Review security rules
    # Check compliance
    # Generate alerts
    # Return violations
  end
end
```

### Background Jobs
```ruby
class AuditRetentionJob < ApplicationJob
  def perform
    # Apply retention policies
    # Archive old events
    # Clean up attachments
    # Update statistics
  end
end

class ComplianceReportJob < ApplicationJob
  def perform(report_id)
    # Generate detailed report
    # Analyze patterns
    # Create visualizations
    # Store results
  end
end
```

## Report Templates
1. Full Audit Report
   - Role changes
   - Assignment history
   - Permission modifications
   - Security alerts

2. Role Review Report
   - Current assignments
   - Role hierarchies
   - Permission distribution
   - Conflict analysis

## API Endpoints
```ruby
# GET /api/v1/audit/events
{
  "start_date": "datetime",
  "end_date": "datetime",
  "event_types": ["string"],
  "user_id": "uuid"
}

# POST /api/v1/compliance/reports
{
  "report_type": "string",
  "parameters": {
    "date_range": {},
    "include_details": boolean,
    "format": "pdf|csv|json"
  }
}
```

## Testing Strategy
1. Model Tests
   - Event logging
   - Report generation
   - Alert handling
   - Data retention

2. Service Tests
   - Audit tracking
   - Compliance checking
   - Policy validation
   - Report creation

3. Integration Tests
   - Complete audit flow
   - Report generation
   - Alert processing
   - API functionality

## Security Considerations
- Audit data encryption
- Report access control
- Alert handling security
- Data retention compliance
- Access logging
- Information classification

## Estimated Hours: 20

## Dependencies
- Core RBAC System
- Role Assignment System
- Document Generation System
