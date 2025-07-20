# Implementation Task: Staff Availability Management

## Overview
Implement a staff availability system that handles working hours, breaks, time off, and recurring patterns while supporting real-time updates and conflict prevention.

## Technical Design

### Models
```ruby
class StaffSchedule < ApplicationRecord
  belongs_to :staff
  belongs_to :business
  has_many :schedule_exceptions
  has_many :recurring_patterns
  
  store :weekly_schedule, accessors: [
    :monday,
    :tuesday,
    :wednesday,
    :thursday,
    :friday,
    :saturday,
    :sunday
  ]
  
  validates :timezone, presence: true
  validates :effective_from, presence: true
  
  scope :current, -> { where('effective_from <= ? AND (effective_until IS NULL OR effective_until >= ?)', Time.current, Time.current) }
end

class ScheduleException < ApplicationRecord
  belongs_to :staff_schedule
  
  validates :start_time, :end_time, presence: true
  validates :exception_type, inclusion: { in: %w[time_off break holiday training] }
  validate :end_time_after_start_time
  
  scope :upcoming, -> { where('end_time > ?', Time.current) }
end

class RecurringPattern < ApplicationRecord
  belongs_to :staff_schedule
  
  store :pattern_config, accessors: [
    :frequency,
    :days,
    :start_time,
    :end_time,
    :interval
  ]
  
  validates :pattern_type, inclusion: { in: %w[weekly bi_weekly monthly custom] }
  validates :start_date, :end_date, presence: true
end
```

### Service Layer
```ruby
module StaffAvailability
  class ScheduleService
    def initialize(staff)
      @staff = staff
      @business = staff.business
    end
    
    def available_slots(date_range)
      base_schedule = fetch_base_schedule(date_range)
      apply_exceptions(base_schedule)
      apply_recurring_patterns(base_schedule)
      apply_business_rules(base_schedule)
      
      base_schedule
    end
    
    private
    
    def fetch_base_schedule(date_range)
      # Get base weekly schedule
    end
    
    def apply_exceptions(schedule)
      # Apply time off, breaks, etc.
    end
  end
end
```

## Implementation Steps

### Phase 1: Core Availability
1. Base Schedule
   - Weekly schedule setup
   - Working hours
   - Break periods
   - Time zones

2. Exception Handling
   - Time off requests
   - Holiday management
   - Break scheduling
   - Override system

3. Recurring Patterns
   - Pattern definition
   - Rule application
   - Conflict handling
   - Pattern updates

### Phase 2: Advanced Features
1. Availability Rules
   - Business constraints
   - Service requirements
   - Capacity limits
   - Buffer times

2. Real-time Updates
   - Schedule changes
   - Exception handling
   - Pattern modifications
   - Notification system

### Phase 3: Integration
1. Calendar System
   - Sync mechanism
   - Conflict prevention
   - Event handling
   - Update propagation

## API Design

### RESTful Endpoints
```ruby
namespace :api do
  namespace :v1 do
    resources :staff do
      resources :schedules do
        resources :exceptions
        resources :patterns
        collection do
          get :availability
          post :bulk_update
        end
      end
    end
  end
end
```

## Background Jobs

### Schedule Generator
```ruby
class GenerateScheduleJob < ApplicationJob
  queue_as :schedules
  
  def perform(staff_id, date_range)
    staff = Staff.find(staff_id)
    service = StaffAvailability::ScheduleService.new(staff)
    
    service.generate_schedule(date_range)
  end
end
```

## Cache Strategy

### Redis Implementation
```ruby
class ScheduleCache
  def cache_key(staff_id, date)
    "schedule:#{staff_id}:#{date}"
  end
  
  def cache_availability(staff_id, date, slots)
    Redis.current.setex(
      cache_key(staff_id, date),
      30.minutes.to_i,
      slots.to_json
    )
  end
end
```

## Testing Strategy

### Unit Tests
- Schedule generation
- Exception handling
- Pattern application
- Rule validation

### Integration Tests
- Calendar sync
- Real-time updates
- Conflict handling
- API endpoints

## Monitoring

### Key Metrics
- Schedule generation time
- Update propagation
- Cache efficiency
- Conflict rate

### Health Checks
- Service availability
- Cache status
- Job processing
- API health

## Documentation

### Technical Guide
1. Schedule Configuration
2. Exception Types
3. Pattern Setup
4. Integration Points

### User Guide
1. Setting Work Hours
2. Managing Time Off
3. Creating Patterns
4. Handling Exceptions
