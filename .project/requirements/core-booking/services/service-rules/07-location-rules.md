# Implementation Task: Location Rules

## Overview
Create a system for managing service location requirements, coverage areas, and travel-based constraints.

## Technical Design

### Models
```ruby
class LocationRule < ServiceRule
  # Inherits from ServiceRule
  validates :rule_type, inclusion: { in: ['location'] }
  
  # Store location configuration
  store :location_config, accessors: [
    :coverage_rules,
    :travel_constraints,
    :booking_zones,
    :pricing_regions
  ], coder: JSON
end

class ServiceLocation < ApplicationRecord
  belongs_to :service
  belongs_to :location_type
  
  validates :service_type, inclusion: { in: %w[in_store mobile virtual hybrid] }
  
  # Store location requirements
  store :location_requirements, accessors: [
    :space_needed,
    :equipment_requirements,
    :setup_requirements,
    :accessibility_needs
  ], coder: JSON
end

class CoverageZone < ApplicationRecord
  belongs_to :business
  has_many :zone_restrictions
  
  # Store geographic data
  store :zone_data, accessors: [
    :boundaries,
    :excluded_areas,
    :service_restrictions,
    :travel_times
  ], coder: JSON
  
  scope :active, -> { where(status: 'active') }
  scope :by_service, ->(service) { joins(:zone_restrictions).where(zone_restrictions: { service_id: service.id }) }
end
```

### Service Objects
```ruby
class LocationRuleService
  def self.validate_location(service, location_data)
    # Check coverage zones
    # Validate requirements
    # Apply restrictions
    # Return validation result
  end
  
  def self.calculate_travel_constraints(service, location)
    # Check travel times
    # Calculate buffers
    # Apply restrictions
    # Return constraints
  end
end

class CoverageZoneService
  def self.check_availability(service, address)
    # Validate coverage
    # Check restrictions
    # Calculate travel time
    # Return availability
  end
  
  def self.optimize_zones(business)
    # Analyze service areas
    # Optimize boundaries
    # Update restrictions
    # Generate recommendations
  end
end
```

### Background Jobs
```ruby
class LocationValidationJob < ApplicationJob
  def perform(appointment_id)
    # Validate location
    # Check requirements
    # Update status
    # Send notifications
  end
end

class ZoneOptimizationJob < ApplicationJob
  def perform(business_id)
    # Analyze coverage
    # Optimize zones
    # Update restrictions
    # Generate report
  end
end
```

## Views
1. Location Rules
   - Coverage configuration
   - Travel constraints
   - Zone management
   - Restriction setup

2. Coverage Management
   - Zone mapping
   - Service areas
   - Travel times
   - Restriction overview

## API Endpoints
```ruby
# GET /api/v1/services/:id/coverage_check
{
  "address": {
    "street": "string",
    "city": "string",
    "state": "string",
    "zip": "string"
  }
}

# POST /api/v1/coverage_zones
{
  "zone_data": {
    "boundaries": [],
    "restrictions": {},
    "service_ids": ["uuid"]
  }
}
```

## Testing Strategy
1. Model Tests
   - Location validation
   - Zone management
   - Travel calculations
   - Restriction handling

2. Service Tests
   - Coverage checking
   - Travel constraints
   - Zone optimization
   - Requirement validation

3. Integration Tests
   - Complete location flow
   - Zone management
   - API functionality
   - Geocoding system

## Security Considerations
- Location data privacy
- Zone access control
- Address validation
- Rate limiting
- Audit logging
- Data accuracy

## Estimated Hours: 20

## Dependencies
- Rules Engine
- Geocoding System
