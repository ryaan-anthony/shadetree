# Implementation Task: Service Builder Interface

## Overview
Create an intuitive interface for businesses to define and configure their services, including variations, requirements, and resources.

## Technical Design

### Models
```ruby
class ServiceBuilder < ApplicationRecord
  belongs_to :business
  belongs_to :service, optional: true
  
  # Store builder state
  store :current_state, accessors: [
    :step,
    :draft_data,
    :validation_errors,
    :completion_status
  ], coder: JSON
  
  validates :builder_type, inclusion: { in: %w[new_service clone_service modify_service] }
  validates :status, inclusion: { in: %w[draft in_progress completed abandoned] }
end

class ServiceTemplate < ApplicationRecord
  belongs_to :business, optional: true
  has_many :template_variations
  
  validates :template_type, inclusion: { in: %w[system custom] }
  validates :industry_type, presence: true
  
  # Store template configuration
  store :template_config, coder: JSON
  
  scope :system_templates, -> { where(template_type: 'system') }
  scope :by_industry, ->(type) { where(industry_type: type) }
end
```

### Service Objects
```ruby
class ServiceBuilderService
  def self.initialize_builder(business, type, options = {})
    ServiceBuilder.transaction do
      # Create builder instance
      # Load template if specified
      # Initialize draft data
      # Set up validation rules
    end
  end
  
  def self.update_step(builder, step_data)
    # Validate step data
    # Update builder state
    # Run step-specific logic
    # Return validation results
  end
  
  def self.complete_builder(builder)
    Service.transaction do
      # Validate all steps
      # Create or update service
      # Handle variations
      # Process requirements
    end
  end
end

class ServiceValidationService
  def self.validate_step(builder, step, data)
    # Load step rules
    # Validate data
    # Check dependencies
    # Return validation result
  end
  
  def self.validate_complete(builder)
    # Check all required steps
    # Validate business rules
    # Check resource availability
    # Return completion status
  end
end
```

### Views
1. Service Builder Steps
   - Basic Information
   - Variations Setup
   - Requirements Config
   - Resource Allocation
   - Pricing Setup

2. Template Selection
   - Industry Templates
   - Custom Templates
   - Clone Existing

## API Endpoints
```ruby
# POST /api/v1/service_builder
{
  "builder_type": "string",
  "template_id": "uuid",
  "options": {}
}

# PATCH /api/v1/service_builder/:id/step
{
  "step": "string",
  "data": {}
}
```

## State Machine
```ruby
class ServiceBuilderStateMachine
  include Statesman::Machine
  
  state :draft, initial: true
  state :basic_info
  state :variations
  state :requirements
  state :resources
  state :pricing
  state :review
  state :completed
  
  transition from: :draft, to: [:basic_info]
  transition from: :basic_info, to: [:variations, :requirements]
  transition from: :variations, to: [:requirements, :resources]
  transition from: :requirements, to: [:resources, :pricing]
  transition from: :resources, to: [:pricing, :review]
  transition from: :pricing, to: [:review]
  transition from: :review, to: [:completed]
end
```

## Testing Strategy
1. Model Tests
   - Builder state management
   - Template handling
   - Validation rules

2. Service Tests
   - Builder initialization
   - Step processing
   - Completion handling
   - Template application

3. Integration Tests
   - Complete builder flow
   - Template usage
   - API functionality
   - State transitions

## Security Considerations
- Step validation
- Template access control
- Builder state security
- Rate limiting
- Data validation

## Estimated Hours: 20

## Dependencies
- Core Service Models
- Template System
