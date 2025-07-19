# Implementation Task: Core Service Models

## Overview
Create the foundational data models for managing service definitions, categories, variations, and configurations.

## Technical Design

### Models
```ruby
class ServiceCategory < ApplicationRecord
  belongs_to :business
  has_many :services
  has_many :subcategories, class_name: 'ServiceCategory', foreign_key: 'parent_id'
  belongs_to :parent, class_name: 'ServiceCategory', optional: true
  
  validates :name, presence: true
  validates :key, presence: true, uniqueness: { scope: :business_id }
  
  scope :root_categories, -> { where(parent_id: nil) }
  scope :active, -> { where(status: 'active') }
end

class Service < ApplicationRecord
  belongs_to :business
  belongs_to :category, class_name: 'ServiceCategory'
  has_many :service_variations
  has_many :service_requirements
  has_many :service_resources
  
  validates :name, presence: true
  validates :key, presence: true, uniqueness: { scope: :business_id }
  validates :duration_minutes, presence: true, numericality: { greater_than: 0 }
  
  # Store service configuration
  store :settings, accessors: [
    :description,
    :booking_notice,
    :cancellation_policy,
    :online_booking_enabled,
    :capacity
  ], coder: JSON
  
  scope :active, -> { where(status: 'active') }
  scope :bookable, -> { where(online_booking_enabled: true) }
end

class ServiceVariation < ApplicationRecord
  belongs_to :service
  has_many :variation_options
  
  validates :name, presence: true
  validates :variation_type, inclusion: { in: %w[choice addon modifier] }
  
  # Store variation configuration
  store :settings, accessors: [
    :required,
    :min_selections,
    :max_selections,
    :display_order
  ], coder: JSON
end

class ServiceRequirement < ApplicationRecord
  belongs_to :service
  
  validates :requirement_type, inclusion: { in: %w[form document waiver consultation] }
  validates :name, presence: true
  
  # Store requirement configuration
  store :settings, accessors: [
    :required,
    :form_fields,
    :validation_rules,
    :display_order
  ], coder: JSON
end

class ServiceResource < ApplicationRecord
  belongs_to :service
  belongs_to :resource_type
  
  validates :quantity_required, presence: true, numericality: { greater_than: 0 }
  
  # Store resource requirements
  store :requirements, accessors: [
    :skills_required,
    :equipment_needed,
    :space_required
  ], coder: JSON
end
```

### Service Objects
```ruby
class ServiceDefinitionService
  def self.create_service(business, params)
    Service.transaction do
      # Create service
      # Set up variations
      # Configure requirements
      # Allocate resources
      # Initialize pricing
    end
  end
  
  def self.update_service_config(service, config_changes)
    Service.transaction do
      # Update configuration
      # Handle dependency changes
      # Update availability
      # Notify affected systems
    end
  end
end

class ServiceCatalogService
  def self.organize_catalog(business, structure)
    ServiceCategory.transaction do
      # Update category structure
      # Reorder services
      # Update navigation
      # Rebuild cache
    end
  end
  
  def self.get_service_availability(service, date_range)
    # Check resource availability
    # Apply booking rules
    # Consider capacity
    # Return available slots
  end
end
```

### Background Jobs
```ruby
class ServiceCatalogCacheJob < ApplicationJob
  def perform(business_id)
    # Cache service catalog
    # Build category tree
    # Cache availability
    # Update search index
  end
end

class ServiceConfigurationJob < ApplicationJob
  def perform(service_id, changes)
    # Process configuration changes
    # Update related services
    # Rebuild dependencies
    # Update availability
  end
end
```

## Testing Strategy
1. Model Tests
   - Service validation
   - Category relationships
   - Variation configurations
   - Resource allocation

2. Service Tests
   - Service creation
   - Catalog organization
   - Availability calculation
   - Configuration updates

3. Integration Tests
   - Complete service setup
   - Category management
   - Resource allocation
   - API functionality

## Security Considerations
- Service access control
- Resource validation
- Configuration security
- Rate limiting
- Audit logging

## Estimated Hours: 24

## Dependencies
- Business Account System
- Resource Management System
