# Implementation Task: Time Constraints

## Overview
Create a system for managing time-based booking constraints including advance notice, booking windows, and time slot restrictions.

## Technical Design

### Models
```ruby
class TimeConstraint < ApplicationRecord
  belongs_to :business
  belongs_to :service, optional: true
  
  validates :constraint_type, inclusion: { in: %w[advance_notice booking_window slot_duration buffer_time blackout] }
  validates :status, inclusion: { in: %w[active inactive temporary] }
  
  # Store constraint configuration
  store :time_config, accessors: [
    :minimum_notice,
    :maximum_advance,
    :slot_duration,
    :buffer_before,
    :buffer_after
  ], coder: JSON
end

class BookingWindow < ApplicationRecord
  belongs_to :time_constraint
  
  validates :window_type, inclusion: { in: %w[rolling fixed seasonal custom] }
  
  # Store window configuration
  store :window_config, accessors: [
    :start_rule,
    :end_rule,
    :exceptions,
    :recurrence_rule
  ], coder: JSON
  
  scope :active, -> { where('start_date <= ? AND end_date >= ?', Date.current, Date.current) }
end

class TimeSlotRule < ApplicationRecord
  belongs_to :time_constraint
  
  validates :rule_type, inclusion: { in: %w[fixed_slots dynamic_slots custom_slots] }
  
  # Store slot configuration
  store :slot_config, accessors: [
    :duration_rules,
    :interval_rules,
    :merge_rules,
    :split_rules
  ], coder: JSON
end
```

### Service Objects
```ruby
class TimeConstraintService
  def self.validate_booking_time(service, datetime)
    # Check advance notice
    # Validate booking window
    # Apply slot rules
    # Return validation result
  end
  
  def self.find_available_slots(service, date_range)
    # Apply time constraints
    # Generate valid slots
    # Handle exceptions
    # Return available times
  end
end

class BookingWindowService
  def self.calculate_window(service)
    # Get active windows
    # Apply business rules
    # Handle exceptions
    # Return valid range
  end
  
  def self.validate_exceptions(window, date_range)
    # Check blackout dates
    # Apply seasonal rules
    # Handle holidays
    # Return exceptions
  end
end
```

### Background Jobs
```ruby
class TimeConstraintValidationJob < ApplicationJob
  def perform(service_id)
    # Validate constraints
    # Check conflicts
    # Update availability
    # Send notifications
  end
end

class SlotGenerationJob < ApplicationJob
  def perform(service_id, date_range)
    # Generate time slots
    # Apply constraints
    # Update availability
    # Cache results
  end
end
```

## Views
1. Time Constraint Configuration
   - Advance notice setup
   - Window configuration
   - Slot management
   - Exception handling

2. Calendar Interface
   - Constraint visualization
   - Window preview
   - Slot editor
   - Exception calendar

## API Endpoints
```ruby
# GET /api/v1/services/:id/time_constraints
{
  "constraint_types": ["string"],
  "include_windows": boolean
}

# POST /api/v1/services/:id/validate_time
{
  "datetime": "string",
  "include_details": boolean
}
```

## Testing Strategy
1. Model Tests
   - Constraint validation
   - Window calculation
   - Slot generation
   - Exception handling

2. Service Tests
   - Time validation
   - Slot finding
   - Window management
   - Rule application

3. Integration Tests
   - Complete constraint flow
   - Calendar integration
   - API functionality
   - Cache behavior

## Security Considerations
- Time manipulation prevention
- Constraint validation
- Window authorization
- Rate limiting
- Audit logging
- Cache security

## Estimated Hours: 20

## Dependencies
- Service Rules Engine
- Calendar System
