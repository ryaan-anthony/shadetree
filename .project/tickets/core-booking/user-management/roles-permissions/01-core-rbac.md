# Implementation Task: Core RBAC System

## Overview
Implement a flexible role-based access control system that supports hierarchical roles, granular permissions, and inheritance.

## Technical Design

### Models
```ruby
class Role < ApplicationRecord
  belongs_to :business
  belongs_to :parent_role, class_name: 'Role', optional: true
  has_many :child_roles, class_name: 'Role', foreign_key: 'parent_role_id'
  
  has_many :role_permissions
  has_many :permissions, through: :role_permissions
  
  has_many :user_roles
  has_many :users, through: :user_roles
  
  validates :name, presence: true
  validates :key, presence: true, uniqueness: { scope: :business_id }
  
  # Store role metadata like description, custom fields
  store :metadata, coder: JSON
  
  scope :root_roles, -> { where(parent_role: nil) }
end

class Permission < ApplicationRecord
  has_many :role_permissions
  has_many :roles, through: :role_permissions
  
  validates :name, presence: true
  validates :key, presence: true, uniqueness: true
  validates :resource_type, presence: true
  
  # Store permission constraints
  store :constraints, coder: JSON
  
  scope :by_resource, ->(type) { where(resource_type: type) }
end

class RolePermission < ApplicationRecord
  belongs_to :role
  belongs_to :permission
  
  # Store any overrides to default permission constraints
  store :constraint_overrides, coder: JSON
end

class UserRole < ApplicationRecord
  belongs_to :user
  belongs_to :role
  belongs_to :assigned_by, class_name: 'User'
  
  validates :status, inclusion: { in: %w[active suspended revoked] }
  
  # Store assignment metadata like expiration, conditions
  store :assignment_metadata, coder: JSON
end
```

### Service Objects
```ruby
class RbacService
  def self.check_permission(user, permission_key, resource = nil)
    # Check user roles
    # Evaluate permission constraints
    # Handle inheritance
    # Apply business rules
  end
  
  def self.assign_role(user, role, assigned_by:, metadata: {})
    UserRole.transaction do
      # Validate assignment
      # Create user role
      # Handle inheritance
      # Trigger notifications
    end
  end
  
  def self.calculate_effective_permissions(user)
    # Get all user roles
    # Resolve inheritance
    # Merge permissions
    # Apply constraints
  end
end

class RoleService
  def self.create_role(business, params)
    Role.transaction do
      # Create role
      # Set up inheritance
      # Assign permissions
      # Validate consistency
    end
  end
  
  def self.update_role_permissions(role, permission_changes)
    Role.transaction do
      # Update permissions
      # Handle inheritance impacts
      # Revalidate assignments
      # Log changes
    end
  end
end
```

### Middleware
```ruby
class RbacMiddleware
  def initialize(app)
    @app = app
  end
  
  def call(env)
    # Load user permissions
    # Cache authorization context
    # Pass through request
    # Clear context
  end
end
```

### Policy Objects
```ruby
class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def show?
    RbacService.check_permission(user, "#{record.class.name.downcase}:read", record)
  end

  def create?
    RbacService.check_permission(user, "#{record.class.name.downcase}:create")
  end
end
```

## Database Migrations
```ruby
class CreateRbacTables < ActiveRecord::Migration[7.1]
  def change
    create_table :roles do |t|
      t.references :business
      t.references :parent_role, null: true
      t.string :name, null: false
      t.string :key, null: false
      t.jsonb :metadata, default: {}
      t.timestamps
      
      t.index [:business_id, :key], unique: true
    end
    
    create_table :permissions do |t|
      t.string :name, null: false
      t.string :key, null: false
      t.string :resource_type
      t.jsonb :constraints, default: {}
      t.timestamps
      
      t.index :key, unique: true
    end
    
    create_table :role_permissions do |t|
      t.references :role
      t.references :permission
      t.jsonb :constraint_overrides, default: {}
      t.timestamps
      
      t.index [:role_id, :permission_id], unique: true
    end
    
    create_table :user_roles do |t|
      t.references :user
      t.references :role
      t.references :assigned_by
      t.string :status, default: 'active'
      t.jsonb :assignment_metadata, default: {}
      t.timestamps
      
      t.index [:user_id, :role_id], unique: true
    end
  end
end
```

## Testing Strategy
1. Model Tests
   - Role inheritance
   - Permission constraints
   - Validation rules
   - Relationship integrity

2. Service Tests
   - Permission checking
   - Role assignment
   - Inheritance resolution
   - Constraint evaluation

3. Integration Tests
   - Complete RBAC workflow
   - Policy enforcement
   - Cache behavior
   - API endpoints

## Security Considerations
- Role assignment validation
- Permission constraint security
- Cache invalidation
- Audit logging
- Access control enforcement
- Privilege escalation prevention

## Estimated Hours: 24

## Dependencies
- Core User Models
- Business Account System
- Caching System
