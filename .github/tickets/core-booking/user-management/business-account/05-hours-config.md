# Implementation Task: Business Hours Configuration

## Overview
Create a flexible system for managing business hours, including regular hours, exceptions, holidays, and special hours.

## Technical Design

### Models
```ruby
class BusinessHours < ApplicationRecord
  belongs_to :business
  belongs_to :location, optional: true
  
  # Store hours in a structured format
  store :regular_hours, accessors: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday, :sunday], coder: JSON
  store :special_hours, coder: JSON
  
  validates :timezone, presence: true
  validate :hours_format_valid?
end

class BusinessException < ApplicationRecord
  belongs_to :business
  belongs_to :location, optional: true
  
  validates :start_date, presence: true
  validates :end_date, presence: true
  validate :end_date_after_start_date
end
```

### Service Objects
```ruby
class BusinessHoursService
  def self.update_hours(business, params)
    BusinessHours.transaction do
      # Update regular hours
      # Process special hours
      # Handle exceptions
      # Recalculate availability
    end
  end
  
  def self.is_available?(business, datetime)
    # Check regular hours
    # Check exceptions
    # Check special hours
    # Consider timezone
  end
end
```

### Time Slot Generation
```ruby
class TimeSlotGenerator
  def self.generate_slots(business, date)
    # Get business hours for date
    # Consider exceptions
    # Generate available slots
    # Apply buffer times
  end
end
```

### Background Jobs
```ruby
class RecalculateAvailabilityJob < ApplicationJob
  def perform(business_id, date_range)
    # Recalculate availability slots
    # Update cached availability
    # Notify affected appointments
  end
end
```

## Views
1. Hours Configuration
   - Weekly schedule editor
   - Special hours manager
   - Exception calendar
   - Timezone selection

2. Bulk Operations
   - Holiday import
   - Special hours batch update
   - Exception batch creation

## API Endpoints
```ruby
# PUT /api/v1/business/hours
{
  "regular_hours": {
    "monday": [{"start": "09:00", "end": "17:00"}],
    "tuesday": [{"start": "09:00", "end": "17:00"}]
  },
  "special_hours": [
    {
      "date": "2025-12-24",
      "hours": [{"start": "09:00", "end": "14:00"}]
    }
  ]
}
```

## Testing Strategy
1. Model Tests
   - Hour validation
   - Exception handling
   - Timezone calculations

2. Service Tests
   - Hour updates
   - Availability checks
   - Slot generation

3. Integration Tests
   - Complete hours management flow
   - Availability recalculation
   - API functionality

## Security Considerations
- Timezone validation
- Date range limits
- Rate limiting API calls
- Audit logging for changes

## Estimated Hours: 20

## Dependencies
- Core Models implementation
- Location management system
- Availability calculation engine
