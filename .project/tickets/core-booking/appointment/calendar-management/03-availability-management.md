# Implementation Task: Availability Management

## Overview
Implement a comprehensive availability management system that handles business hours, staff scheduling, and special time slots while supporting recurring patterns and exceptions.

## Technical Design

### Models
```ruby
class BusinessHours < ApplicationRecord
  belongs_to :business
  has_many :exceptions
  
  store :schedule, accessors: [
    :weekday_hours,
    :weekend_hours,
    :holiday_hours
  ]
  
  validates :timezone, presence: true
end

class StaffAvailability < ApplicationRecord
  belongs_to :staff
  belongs_to :business
  has_many :exceptions
  has_many :recurring_patterns
  
  validates :start_date, :end_date, presence: true
  validate :end_date_after_start_date
end

class AvailabilityException < ApplicationRecord
  belongs_to :exceptional, polymorphic: true # BusinessHours or StaffAvailability
  
  validates :start_time, :end_time, presence: true
  validates :exception_type, inclusion: { in: %w[override blackout holiday] }
end
```

### Service Layer
```ruby
module Availability
  class CalculationService
    def initialize(business, date_range)
      @business = business
      @date_range = date_range
    end
    
    def available_slots(duration: 30.minutes)
      combine_constraints([
        business_hours_constraint,
        staff_availability_constraint,
        existing_bookings_constraint
      ])
    end
  end
  
  class RecurringPatternService
    def initialize(staff)
      @staff = staff
    end
    
    def apply_pattern(pattern)
      validate_pattern(pattern)
      generate_availability_entries(pattern)
    end
  end
end
```

## Implementation Steps

### Phase 1: Core Availability
1. Business Hours
   - Regular hours setup
   - Exception handling
   - Holiday management
   - Timezone support

2. Staff Availability
   - Individual schedules
   - Time off requests
   - Break periods
   - Rotation patterns

3. Exception Management
   - Override rules
   - Blackout dates
   - Special events
   - Emergency closures

### Phase 2: Advanced Features
1. Recurring Patterns
   - Weekly rotations
   - Custom patterns
   - Pattern conflicts
   - Pattern updates

2. Capacity Management
   - Staff overlap
   - Resource limits
   - Buffer times
   - Peak handling

### Phase 3: Optimization
1. Performance
   - Query optimization
   - Caching strategy
   - Batch updates
   - Background jobs

2. Validation
   - Rule enforcement
   - Conflict prevention
   - Data integrity
   - Error handling

## Business Rules

### Availability Rules
```ruby
module AvailabilityRules
  class BusinessHoursRule
    def validate(time_slot)
      within_business_hours?(time_slot) &&
      !during_holiday?(time_slot) &&
      !during_blackout?(time_slot)
    end
  end
  
  class StaffAvailabilityRule
    def validate(time_slot, staff)
      staff.available_during?(time_slot) &&
      !staff.on_break_during?(time_slot) &&
      within_working_hours?(staff, time_slot)
    end
  end
end
```

### Conflict Resolution
```ruby
module AvailabilityConflicts
  class ConflictResolver
    def resolve_conflicts(availability_entries)
      sort_by_priority(availability_entries)
      merge_overlapping_entries
      handle_gaps
    end
  end
end
```

## Cache Strategy

### Redis Implementation
```ruby
class AvailabilityCache
  def cache_key(business, date)
    "availability:#{business.id}:#{date.to_s(:number)}"
  end
  
  def cache_slots(business, date, slots)
    Redis.current.setex(
      cache_key(business, date),
      1.day.to_i,
      slots.to_json
    )
  end
end
```

## Background Jobs

### Availability Generation
```ruby
class GenerateAvailabilityJob < ApplicationJob
  queue_as :availability
  
  def perform(business_id, start_date, end_date)
    business = Business.find(business_id)
    service = Availability::CalculationService.new(business, start_date..end_date)
    
    service.generate_and_cache_slots
  end
end
```

## API Endpoints

### RESTful API
```ruby
# config/routes.rb
namespace :api do
  namespace :v1 do
    resources :availability do
      collection do
        get :slots
        post :exceptions
        get :staff
      end
    end
  end
end
```

## Testing Strategy

### Unit Tests
- Business hour calculations
- Staff availability rules
- Exception handling
- Pattern generation

### Integration Tests
- Full availability flow
- Conflict resolution
- Cache operations
- API endpoints

### Performance Tests
- Large date ranges
- Multiple staff members
- Concurrent requests
- Cache efficiency

## Monitoring

### Key Metrics
- Slot calculation time
- Cache hit ratio
- Conflict frequency
- API response time

### Health Checks
- Cache status
- Background jobs
- Database queries
- API endpoints

## Documentation

### Technical Specs
1. Data Models
2. Business Rules
3. API Reference
4. Cache Strategy

### User Guide
1. Setting Business Hours
2. Managing Staff Availability
3. Handling Exceptions
4. Pattern Configuration
