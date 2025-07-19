# Implementation Task: Dependency Constraints

## Overview
Create a system for managing booking dependencies, including service prerequisites, required intervals between services, and scheduling order constraints.

## Technical Design

### Models
```ruby
class DependencyConstraint < ApplicationRecord
  belongs_to :business
  belongs_to :service
  belongs_to :dependent_service, class_name: 'Service'
  
  validates :dependency_type, inclusion: { in: %w[required_before required_after mutually_exclusive concurrent] }
  validates :status, inclusion: { in: %w[active inactive override] }
  
  # Store dependency configuration
  store :dependency_config, accessors: [
    :time_interval,
    :interval_type,
    :flexibility,
    :conditions
  ], coder: JSON
end

class ServiceDependencyGroup < ApplicationRecord
  belongs_to :business
  has_many :dependency_constraints
  
  validates :group_type, inclusion: { in: %w[sequence package bundle custom] }
  
  # Store group configuration
  store :group_config, accessors: [
    :ordering_rules,
    :timing_rules,
    :override_conditions
  ], coder: JSON
end

class DependencyResolution < ApplicationRecord
  belongs_to :dependency_constraint
  belongs_to :primary_appointment
  belongs_to :dependent_appointment
  
  validates :resolution_type, inclusion: { in: %w[scheduled pending cancelled overridden] }
  
  # Store resolution details
  store :resolution_details, accessors: [
    :timing_met,
    :override_reason,
    :notifications
  ], coder: JSON
end
```

### Service Objects
```ruby
class DependencyConstraintService
  def self.validate_booking(service, datetime, context)
    # Check dependencies
    # Validate timing
    # Check conflicts
    # Return validation result
  end
  
  def self.suggest_dependent_slots(service, primary_datetime)
    # Find valid slots
    # Apply timing rules
    # Check availability
    # Return suggestions
  end
end

class DependencyResolutionService
  def self.resolve_dependencies(appointment)
    DependencyResolution.transaction do
      # Check requirements
      # Schedule dependents
      # Handle conflicts
      # Send notifications
    end
  end
  
  def self.handle_cancellation(appointment)
    # Check dependent bookings
    # Process cancellations
    # Update resolutions
    # Notify affected parties
  end
end
```

### Background Jobs
```ruby
class DependencyValidationJob < ApplicationJob
  def perform(appointment_id)
    # Validate dependencies
    # Check resolutions
    # Update status
    # Send notifications
  end
end

class DependencyResolutionJob < ApplicationJob
  def perform(resolution_id)
    # Process resolution
    # Schedule appointments
    # Handle conflicts
    # Update status
  end
end
```

## Views
1. Dependency Configuration
   - Service relationships
   - Timing rules
   - Group management
   - Override settings

2. Resolution Interface
   - Dependency status
   - Scheduling assistance
   - Conflict resolution
   - Override handling

## API Endpoints
```ruby
# GET /api/v1/services/:id/dependencies
{
  "include_resolutions": boolean,
  "status": ["string"]
}

# POST /api/v1/appointments/:id/validate_dependencies
{
  "datetime": "string",
  "context": {}
}
```

## Testing Strategy
1. Model Tests
   - Dependency validation
   - Resolution handling
   - Group management
   - Status transitions

2. Service Tests
   - Dependency checking
   - Resolution process
   - Scheduling logic
   - Conflict handling

3. Integration Tests
   - Complete dependency flow
   - Scheduling integration
   - API functionality
   - Notification system

## Security Considerations
- Dependency validation
- Resolution authorization
- Schedule access control
- Rate limiting
- Audit logging
- Data integrity

## Estimated Hours: 24

## Dependencies
- Time Constraints
- Capacity Constraints
