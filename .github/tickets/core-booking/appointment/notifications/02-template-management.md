# Implementation Task: Template Management

## Overview
Create a template management system that allows businesses to customize notification templates with dynamic content, branding, and multi-language support.

## Technical Design

### Models
```ruby
class NotificationTemplateGroup < ApplicationRecord
  belongs_to :business
  has_many :templates, class_name: 'NotificationTemplate'
  
  validates :group_type, inclusion: { in: %w[appointment service marketing system] }
  
  # Store group configuration
  store :group_config, accessors: [
    :default_branding,
    :variable_defaults,
    :approval_required,
    :languages
  ], coder: JSON
end

class TemplateVersion < ApplicationRecord
  belongs_to :notification_template
  belongs_to :created_by, class_name: 'User'
  
  # Store version content
  store :version_content, accessors: [
    :template_data,
    :changes_made,
    :approval_status,
    :testing_results
  ], coder: JSON
end

class TemplateTranslation < ApplicationRecord
  belongs_to :notification_template
  
  validates :locale, presence: true
  validates :status, inclusion: { in: %w[active draft reviewing] }
  
  # Store translation content
  store :translation_content, accessors: [
    :subject,
    :body,
    :variables,
    :metadata
  ], coder: JSON
end
```

### Service Objects
```ruby
class TemplateManagementService
  def self.create_template(group, params)
    NotificationTemplate.transaction do
      # Create template
      # Set up versions
      # Handle translations
      # Initialize variables
    end
  end
  
  def self.update_template(template, params)
    # Create new version
    # Update content
    # Handle approvals
    # Notify stakeholders
  end
end

class TemplateMigrationService
  def self.migrate_templates(business, template_updates)
    # Validate changes
    # Create versions
    # Update templates
    # Handle dependencies
  end
  
  def self.validate_migration(templates)
    # Check dependencies
    # Validate variables
    # Test rendering
    # Return validation
  end
end
```

### Background Jobs
```ruby
class TemplateValidationJob < ApplicationJob
  def perform(template_id)
    # Validate template
    # Test variables
    # Check translations
    # Update status
  end
end

class TemplateExportJob < ApplicationJob
  def perform(group_id, format)
    # Export templates
    # Generate package
    # Create documentation
    # Send notification
  end
end
```

## Template Editor Interface
```ruby
# app/components/template_editor_component.rb
class TemplateEditorComponent < ViewComponent::Base
  def initialize(template:, mode: :edit)
    @template = template
    @mode = mode
    @variables = load_available_variables
    @preview_data = generate_preview_data
  end
  
  private
  
  def load_available_variables
    TemplateVariableService.load_variables_for_template(@template)
  end
end
```

## Testing Strategy
1. Model Tests
   - Template versioning
   - Translation handling
   - Variable validation
   - Group management

2. Service Tests
   - Template creation
   - Version management
   - Migration handling
   - Preview generation

3. Integration Tests
   - Complete template flow
   - Translation workflow
   - Variable processing
   - Preview system

## Security Considerations
- Template sanitization
- Variable validation
- Access control
- Version tracking
- Audit logging
- Content security

## Estimated Hours: 20

## Dependencies
- Notification Engine
- Business Branding System
