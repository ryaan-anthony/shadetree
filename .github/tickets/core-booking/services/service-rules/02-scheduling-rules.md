# Implementation Task: Scheduling Rules

## Overview
Create a specialized rule system for handling scheduling constraints, including time restrictions, capacity limits, and booking windows.

## Technical Design

### Models
```ruby
class SchedulingRule < ServiceRule
  # Inherits from ServiceRule
  validates :rule_type, inclusion: { in: ['scheduling'] }
  
  # Store scheduling-specific configuration
  store :scheduling_config, accessors: [
    :advance_notice,
    :capacity_limits,
    :booking_window,
    :buffer_requirements
  ], coder: JSON
end

class TimeRestriction < ApplicationRecord
  belongs_to :scheduling_rule
  
  validates :restriction_type, inclusion: { in: %w[blackout recurring seasonal custom] }
  
  # Store time configuration
  store :time_config, accessors: [
    :days_of_week,
    :time_ranges,
    :date_ranges,
    :exceptions
  ], coder: JSON
  
  scope :active, -> { where('start_date <= ? AND end_date >= ?', Date.current, Date.current) }
end

class CapacityConfig < ApplicationRecord
  belongs_to :scheduling_rule
  
  validates :capacity_type, inclusion: { in: %w[concurrent total daily custom] }
  
  # Store capacity settings
  store :limits, accessors: [
    :max_concurrent,
    :max_daily,
    :max_weekly,
    :custom_limits
  ], coder: JSON
end
```

### Service Objects
```ruby
class SchedulingRuleService
  def self.validate_booking(service, datetime, context)
    # Check time restrictions
    # Validate capacity
    # Apply buffer rules
    # Check dependencies
  end
  
  def self.find_available_slots(service, date_range)
    # Apply scheduling rules
    # Calculate availability
    # Handle restrictions
    # Return valid slots
  end
end

class TimeRestrictionService
  def self.check_restrictions(datetime, restrictions)
    # Evaluate time rules
    # Check blackout periods
    # Apply exceptions
    # Return availability
  end
  
  def self.calculate_next_available(restrictions)
    # Find next valid time
    # Consider all restrictions
    # Handle recurring rules
    # Return next slot
  end
end

class CapacityService
  def self.check_capacity(service, datetime)
    # Load capacity config
    # Check current bookings
    # Apply limits
    # Return availability
  end
end
```

### Background Jobs
```ruby
class CapacityRecalculationJob < ApplicationJob
  def perform(service_id, date_range)
    # Recalculate capacity
    # Update availability
    # Handle conflicts
    # Notify if needed
  end
end

class TimeRestrictionSyncJob < ApplicationJob
  def perform
    # Sync calendar restrictions
    # Update blackout periods
    # Process exceptions
    # Update availability
  end
end
```

## Views
1. Scheduling Rules
   - Time restriction setup
   - Capacity configuration
   - Buffer management
   - Exception handling

2. Calendar View
   - Restriction visualization
   - Capacity indicators
   - Conflict warnings
   - Override options

## API Endpoints
```ruby
# GET /api/v1/services/:id/availability
{
  "date_range": {
    "start": "datetime",
    "end": "datetime"
  },
  "constraints": {}
}

# POST /api/v1/services/:id/scheduling_rules
{
  "rule_type": "scheduling",
  "scheduling_config": {
    "advance_notice": "string",
    "capacity_limits": {},
    "restrictions": []
  }
}
```

## Testing Strategy
1. Model Tests
   - Rule validation
   - Time calculations
   - Capacity tracking
   - Buffer handling

2. Service Tests
   - Availability checks
   - Restriction processing
   - Capacity management
   - Conflict resolution

3. Integration Tests
   - Complete scheduling flow
   - Calendar integration
   - API functionality
   - Edge cases

## Security Considerations
- Time zone handling
- Capacity verification
- Rule authorization
- Rate limiting
- Audit logging
- Data validation

## Estimated Hours: 20

## Dependencies
- Rules Engine
- Calendar Management System
