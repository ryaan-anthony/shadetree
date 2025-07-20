# Implementation Task: Role Templates

## Overview
Create a template system for common role configurations that can be quickly applied and customized for different businesses.

## Technical Design

### Models
```ruby
class RoleTemplate < ApplicationRecord
  has_many :template_permissions
  has_many :permissions, through: :template_permissions
  
  validates :name, presence: true
  validates :key, presence: true, uniqueness: true
  
  # Store template configuration
  store :configuration, accessors: [
    :description,
    :suggested_hierarchy,
    :customization_options
  ], coder: JSON
  
  scope :active, -> { where(status: 'active') }
  scope :by_category, ->(category) { where(category: category) }
end

class TemplatePermission < ApplicationRecord
  belongs_to :role_template
  belongs_to :permission
  
  # Store default constraints for this permission in template
  store :default_constraints, coder: JSON
end

class RoleCustomization < ApplicationRecord
  belongs_to :role
  belongs_to :role_template
  
  # Store customizations applied to template
  store :customizations, coder: JSON
  
  validates :customization_type, inclusion: { in: %w[extension override hybrid] }
end
```

### Service Objects
```ruby
class RoleTemplateService
  def self.apply_template(business, template_key, customizations = {})
    Role.transaction do
      # Load template
      # Apply customizations
      # Create roles
      # Set up permissions
      # Configure hierarchy
    end
  end
  
  def self.update_from_template(role)
    Role.transaction do
      # Check template updates
      # Preserve customizations
      # Apply changes
      # Validate consistency
    end
  end
end

class CustomizationService
  def self.customize_template(template, params)
    # Validate customizations
    # Apply changes
    # Generate configuration
    # Validate result
  end
  
  def self.merge_customizations(base_config, custom_config)
    # Merge configurations
    # Resolve conflicts
    # Validate result
    # Return merged config
  end
end
```

### Default Templates
```ruby
STANDARD_TEMPLATES = {
  service_business: {
    admin: {
      permissions: ['*'],
      children: [:manager, :staff]
    },
    manager: {
      permissions: ['staff.*', 'appointments.*', 'services.*'],
      children: [:staff]
    },
    staff: {
      permissions: ['appointments.view', 'appointments.manage_own']
    }
  }
}
```

## Views
1. Template Selection
   - Category browsing
   - Template preview
   - Customization options

2. Template Customization
   - Permission adjustment
   - Hierarchy configuration
   - Role naming

## API Endpoints
```ruby
# POST /api/v1/roles/apply_template
{
  "template_key": "string",
  "customizations": {
    "roles": {},
    "permissions": {},
    "hierarchy": {}
  }
}

# PATCH /api/v1/roles/template_customization
{
  "role_id": "uuid",
  "customizations": {}
}
```

## Testing Strategy
1. Model Tests
   - Template validation
   - Customization storage
   - Default configurations

2. Service Tests
   - Template application
   - Customization merging
   - Update handling

3. Integration Tests
   - Complete template workflow
   - Customization application
   - API functionality

## Security Considerations
- Template validation
- Customization sanitization
- Permission boundaries
- Role hierarchy validation
- Audit logging

## Estimated Hours: 16

## Dependencies
- Core RBAC System
- Permission Management
- Business Configuration System
