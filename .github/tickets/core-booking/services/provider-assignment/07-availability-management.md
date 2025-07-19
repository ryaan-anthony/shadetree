# Implementation Task: Availability Management

## Overview
Create a comprehensive system for managing provider availability, including schedules, time off, and real-time availability tracking.

## Technical Design

### Models
```ruby
class ProviderAvailability < ApplicationRecord
  belongs_to :user
  belongs_to :business
  
  # Store availability patterns
  store :regular_hours, accessors: [
    :weekly_schedule,
    :break_periods,
    :buffer_times
  ], coder: JSON
  
  # Store exceptions
  store :exceptions, accessors: [
    :time_off,
    :special_hours,
    :blocked_periods
  ], coder: JSON
end

class TimeOffRequest < ApplicationRecord
  belongs_to :user
  belongs_to :approved_by, class_name: 'User', optional: true
  
  validates :request_type, inclusion: { in: %w[vacation sick personal training block] }
  validates :status, inclusion: { in: %w[pending approved denied cancelled] }
  
  # Store request details
  store :request_details, accessors: [
    :reason,
    :coverage_plan,
    :recurrence_rule
  ], coder: JSON
end

class AvailabilityOverride < ApplicationRecord
  belongs_to :user
  belongs_to :created_by, class_name: 'User'
  
  validates :override_type, inclusion: { in: %w[extend reduce block special] }
  
  # Store override details
  store :override_details, accessors: [
    :reason,
    :approval_chain,
    :notifications
  ], coder: JSON
end
```

### Service Objects
```ruby
class AvailabilityService
  def self.check_availability(provider, datetime)
    # Check regular hours
    # Apply exceptions
    # Consider overrides
    # Return status
  end
  
  def self.find_available_slots(provider, date_range)
    # Calculate available times
    # Apply constraints
    # Handle conflicts
    # Return slots
  end
end

class TimeOffService
  def self.request_time_off(provider, params)
    TimeOffRequest.transaction do
      # Create request
      # Check policies
      # Route approval
      # Update availability
    end
  end
  
  def self.process_approval(request, approver, decision)
    # Validate authority
    # Process decision
    # Update schedules
    # Send notifications
  end
end
```

### Background Jobs
```ruby
class AvailabilityCalculationJob < ApplicationJob
  def perform(provider_id, date_range)
    # Calculate availability
    # Update cache
    # Handle conflicts
    # Send notifications
  end
end

class TimeOffReminderJob < ApplicationJob
  def perform
    # Check pending requests
    # Send reminders
    # Update status
    # Handle expirations
  end
end
```

## Views
1. Availability Management
   - Schedule editor
   - Time off requests
   - Override management
   - Conflict resolution

2. Calendar Interface
   - Availability view
   - Request handling
   - Schedule changes
   - Coverage planning

## API Endpoints
```ruby
# GET /api/v1/providers/:id/availability
{
  "date_range": {},
  "include_details": boolean
}

# POST /api/v1/time_off_requests
{
  "request_type": "string",
  "date_range": {},
  "details": {}
}
```

## Testing Strategy
1. Model Tests
   - Availability calculation
   - Request handling
   - Override management
   - Policy enforcement

2. Service Tests
   - Availability checking
   - Time off processing
   - Override handling
   - Conflict resolution

3. Integration Tests
   - Complete availability flow
   - Request workflow
   - API functionality
   - Calendar integration

## Security Considerations
- Request authorization
- Override validation
- Schedule access control
- Rate limiting
- Audit logging
- Data privacy

## Estimated Hours: 20

## Dependencies
- Team Assignment Management
- Calendar System
