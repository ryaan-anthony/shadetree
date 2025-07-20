# Implementation Task: Role Assignment

## Overview
Create a system for managing role assignments to users, including approval workflows, temporary assignments, and delegation capabilities.

## Technical Design

### Models
```ruby
class RoleAssignment < ApplicationRecord
  belongs_to :user
  belongs_to :role
  belongs_to :assigner, class_name: 'User'
  belongs_to :approver, class_name: 'User', optional: true
  
  validates :status, inclusion: { in: %w[pending active expired revoked] }
  validates :assignment_type, inclusion: { in: %w[permanent temporary delegated] }
  
  # Store assignment details
  store :assignment_details, accessors: [
    :expiration_date,
    :delegation_source,
    :approval_requirements,
    :assignment_notes
  ], coder: JSON
  
  scope :active, -> { where(status: 'active').where('expires_at IS NULL OR expires_at > ?', Time.current) }
  scope :requiring_approval, -> { where(status: 'pending', requires_approval: true) }
end

class RoleApproval < ApplicationRecord
  belongs_to :role_assignment
  belongs_to :approver, class_name: 'User'
  
  validates :status, inclusion: { in: %w[pending approved rejected] }
  validates :approval_type, inclusion: { in: %w[manual automatic delegated] }
  
  # Store approval metadata
  store :approval_metadata, coder: JSON
end

class RoleDelegation < ApplicationRecord
  belongs_to :delegator, class_name: 'User'
  belongs_to :delegate, class_name: 'User'
  belongs_to :role
  
  validates :status, inclusion: { in: %w[active expired revoked] }
  validates :delegation_type, inclusion: { in: %w[full partial] }
  
  # Store delegation rules
  store :delegation_rules, coder: JSON
end
```

### Service Objects
```ruby
class RoleAssignmentService
  def self.assign_role(user, role, assigner:, options: {})
    RoleAssignment.transaction do
      # Validate assignment rules
      # Create assignment record
      # Handle approval requirements
      # Process inheritance
      # Send notifications
    end
  end
  
  def self.process_approval(assignment, approver, decision)
    RoleApproval.transaction do
      # Validate approval authority
      # Process decision
      # Update assignment status
      # Handle notifications
    end
  end
  
  def self.handle_delegation(delegator, delegate, role, rules)
    RoleDelegation.transaction do
      # Validate delegation rules
      # Create delegation record
      # Set up temporary assignments
      # Send notifications
    end
  end
end

class AssignmentValidationService
  def self.validate_assignment(user, role)
    # Check business rules
    # Validate prerequisites
    # Check conflicts
    # Return validation result
  end
  
  def self.check_approval_requirements(assignment)
    # Load approval rules
    # Determine approvers
    # Check auto-approval rules
    # Return requirements
  end
end
```

### Background Jobs
```ruby
class AssignmentExpirationJob < ApplicationJob
  def perform
    # Check expiring assignments
    # Process expirations
    # Send notifications
    # Clean up related data
  end
end

class DelegationMonitorJob < ApplicationJob
  def perform
    # Monitor delegation usage
    # Check delegation rules
    # Handle violations
    # Update statistics
  end
end
```

## Views
1. Role Assignment
   - User selection
   - Role selection
   - Assignment options
   - Approval workflow

2. Assignment Management
   - Active assignments
   - Pending approvals
   - Delegation management
   - Bulk operations

## API Endpoints
```ruby
# POST /api/v1/role_assignments
{
  "user_id": "uuid",
  "role_id": "uuid",
  "assignment_type": "permanent|temporary|delegated",
  "options": {
    "expiration_date": "datetime",
    "requires_approval": boolean,
    "delegation_rules": {}
  }
}

# POST /api/v1/role_assignments/:id/approve
{
  "decision": "approve|reject",
  "reason": "string"
}
```

## Testing Strategy
1. Model Tests
   - Assignment validation
   - Approval workflow
   - Delegation rules
   - Expiration handling

2. Service Tests
   - Assignment creation
   - Approval processing
   - Delegation handling
   - Validation rules

3. Integration Tests
   - Complete assignment flow
   - Approval workflow
   - Delegation process
   - API functionality

## Security Considerations
- Assignment authorization
- Approval validation
- Delegation security
- Role hierarchy enforcement
- Audit logging
- Access control

## Estimated Hours: 20

## Dependencies
- Core RBAC System
- Permission Management
- Notification System
