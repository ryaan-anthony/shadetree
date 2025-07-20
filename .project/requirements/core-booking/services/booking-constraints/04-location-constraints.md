# Implementation Task: Location Constraints

## Overview
Create a system for managing location-based booking constraints including service areas, travel times, and location-specific capacity limits.

## Technical Design

### Models
```ruby
class LocationConstraint < ApplicationRecord
  belongs_to :business
  belongs_to :service, optional: true
  
  validates :constraint_type, inclusion: { in: %w[service_area travel_time venue_capacity location_specific] }
  validates :status, inclusion: { in: %w[active inactive temporary] }
  
  # Store location configuration
  store :location_config, accessors: [
    :boundaries,
    :travel_rules,
    :capacity_limits,
    :restrictions
  ], coder: JSON
end

class ServiceArea < ApplicationRecord
  belongs_to :location_constraint
  has_many :area_exceptions
  
  # Store geographic data
  store :area_config, accessors: [
    :polygon_data,
    :zip_codes,
    :region_rules,
    :travel_matrix
  ], coder: JSON
  
  scope :active, -> { where(status: 'active') }
end

class TravelTimeConstraint < ApplicationRecord
  belongs_to :location_constraint
  
  validates :calculation_method, inclusion: { in: %w[fixed_time distance_based real_time custom] }
  
  # Store travel configuration
  store :travel_config, accessors: [
    :buffer_time,
    :traffic_factors,
    :route_preferences
  ], coder: JSON
end
```

### Service Objects
```ruby
class LocationConstraintService
  def self.validate_location(service, location_data)
    # Check service area
    # Calculate travel time
    # Validate capacity
    # Return validation result
  end
  
  def self.find_available_locations(service, datetime)
    # Get valid locations
    # Apply constraints
    # Check availability
    # Return options
  end
end

class TravelTimeService
  def self.calculate_travel_time(from_location, to_location)
    # Get route options
    # Calculate duration
    # Apply factors
    # Return estimate
  end
  
  def self.optimize_route(appointments)
    # Sort locations
    # Calculate optimal route
    # Apply constraints
    # Return schedule
  end
end
```

### Background Jobs
```ruby
class LocationValidationJob < ApplicationJob
  def perform(appointment_id)
    # Validate location
    # Check constraints
    # Update status
    # Send notifications
  end
end

class RouteOptimizationJob < ApplicationJob
  def perform(provider_id, date)
    # Get appointments
    # Optimize route
    # Update schedule
    # Send updates
  end
end
```

## Views
1. Location Configuration
   - Service area setup
   - Travel settings
   - Capacity management
   - Exception handling

2. Route Management
   - Route visualization
   - Travel estimates
   - Schedule optimization
   - Conflict resolution

## API Endpoints
```ruby
# GET /api/v1/services/:id/service_areas
{
  "location": {
    "latitude": number,
    "longitude": number
  }
}

# POST /api/v1/appointments/validate_location
{
  "service_id": "uuid",
  "location": {},
  "datetime": "string"
}
```

## Testing Strategy
1. Model Tests
   - Area validation
   - Travel calculation
   - Capacity checking
   - Exception handling

2. Service Tests
   - Location validation
   - Route optimization
   - Travel estimation
   - Constraint application

3. Integration Tests
   - Complete location flow
   - Route planning
   - API functionality
   - Geocoding integration

## Security Considerations
- Location data privacy
- Route access control
- Address validation
- Rate limiting
- Audit logging
- Data accuracy

## Estimated Hours: 20

## Dependencies
- Time Constraints
- Geocoding System
