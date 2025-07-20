# Implementation Task: Permission Management

## Overview
Create a comprehensive permission management system that handles permission definition, assignment, and validation with support for complex constraints.

## Technical Design

### Models
```ruby
class PermissionCategory < ApplicationRecord
  has_many :permissions
  
  validates :name, presence: true
  validates :key, presence: true, uniqueness: true
  
  scope :active, -> { where(status: 'active') }
  scope :ordered, -> { order(display_order: :asc) }
end

class PermissionConstraint < ApplicationRecord
  belongs_to :permission
  
  validates :constraint_type, inclusion: { in: %w[time location resource value count] }
  validates :operator, inclusion: { in: %w[equals not_equals greater_than less_than contains] }
  
  # Store constraint configuration
  store :configuration, coder: JSON
  
  scope :active, -> { where(status: 'active') }
end

class PermissionGroup < ApplicationRecord
  has_many :group_permissions
  has_many :permissions, through: :group_permissions
  
  validates :name, presence: true
  validates :key, presence: true, uniqueness: { scope: :business_id }
  
  # Store group configuration
  store :configuration, coder: JSON
end
```

### Service Objects
```ruby
class PermissionService
  def self.create_permission(params)
    Permission.transaction do
      # Create permission
      # Set up constraints
      # Add to categories
      # Validate configuration
    end
  end
  
  def self.validate_constraints(permission, context)
    # Load constraints
    # Evaluate conditions
    # Apply business rules
    # Return validation result
  end
end

class PermissionAssignmentService
  def self.assign_to_role(role, permissions, constraints = {})
    Role.transaction do
      # Validate assignments
      # Apply constraints
      # Update role
      # Handle inheritance
    end
  end
  
  def self.bulk_update_permissions(role, changes)
    # Process permission changes
    # Update assignments
    # Maintain consistency
    # Notify affected users
  end
end
```

### Permission Definition DSL
```ruby
PermissionDSL.define do
  category 'appointments' do
    permission 'view' do
      constraint :time, :future_only
      constraint :resource, :own_appointments
    end
    
    permission 'create' do
      constraint :count, max: 10, period: :day
      constraint :resource, :assigned_services
    end
  end
end
```

### Background Jobs
```ruby
class PermissionValidationJob < ApplicationJob
  def perform(role_id)
    # Validate all permissions
    # Check constraints
    # Update status
    # Notify violations
  end
end

class ConstraintCleanupJob < ApplicationJob
  def perform
    # Clean up expired constraints
    # Update permission status
    # Log changes
  end
end
```

## Views
1. Permission Management
   - Category organization
   - Constraint configuration
   - Group management
   - Bulk operations

2. Permission Assignment
   - Role selection
   - Permission search
   - Constraint setup
   - Preview changes

## API Endpoints
```ruby
# POST /api/v1/permissions
{
  "name": "string",
  "key": "string",
  "category": "string",
  "constraints": [{
    "type": "string",
    "configuration": {}
  }]
}

# POST /api/v1/roles/:id/permissions
{
  "permissions": ["string"],
  "constraints": {}
}
```

## Testing Strategy
1. Model Tests
   - Permission validation
   - Constraint evaluation
   - Category organization
   - Group management

2. Service Tests
   - Permission creation
   - Assignment handling
   - Constraint validation
   - Bulk operations

3. Integration Tests
   - Complete permission flow
   - Constraint application
   - API functionality

## Security Considerations
- Permission validation
- Constraint security
- Assignment authorization
- Audit logging
- Change tracking
- Access control

## Estimated Hours: 20

## Dependencies
- Core RBAC System
- Business Rules Engine
- Cache System
