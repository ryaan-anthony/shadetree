# Implementation Task: Time Slot Selection

## Overview
Implement a time slot selection system that integrates with the calendar management system to show available booking times based on service requirements and provider availability.

## Technical Design

### Models
```ruby
class TimeSlot
  include ActiveModel::Model
  
  attr_accessor :start_time, :end_time, :provider_id, :service_id
  
  validates :start_time, :end_time, presence: true
  validate :end_time_after_start_time
  
  def duration
    (end_time - start_time).to_i
  end
  
  def available?
    validate_availability
  end
end

class SlotAvailability < ApplicationRecord
  belongs_to :provider, class_name: 'Staff'
  belongs_to :service
  
  validates :date, presence: true
  
  store :availability_slots, accessors: [
    :morning_slots,
    :afternoon_slots,
    :evening_slots,
    :blocked_slots
  ]
end
```

### Service Layer
```ruby
module TimeSlots
  class AvailabilityService
    def initialize(service, date_range, provider = nil)
      @service = service
      @date_range = date_range
      @provider = provider
    end
    
    def available_slots
      slots = fetch_base_availability
      apply_service_constraints(slots)
      apply_provider_constraints(slots) if @provider
      apply_business_rules(slots)
      
      slots
    end
    
    private
    
    def fetch_base_availability
      # Integrate with calendar management system
    end
  end
  
  class SlotGenerationService
    def initialize(business)
      @business = business
    end
    
    def generate_slots(date_range)
      business_hours = fetch_business_hours(date_range)
      staff_availability = fetch_staff_availability(date_range)
      
      generate_available_slots(business_hours, staff_availability)
    end
  end
end
```

## Implementation Steps

### Phase 1: Core Time Slot System
1. Slot Generation
   - Business hours integration
   - Provider availability check
   - Service duration handling
   - Buffer time management

2. Availability Rules
   - Business constraints
   - Provider schedules
   - Service requirements
   - Booking limits

3. Calendar Integration
   - Real-time availability
   - Conflict prevention
   - External calendar sync
   - Block time handling

### Phase 2: Advanced Features
1. Smart Scheduling
   - Optimal slot suggestion
   - Load balancing
   - Resource optimization
   - Peak time management

2. Flexibility Options
   - Custom durations
   - Split appointments
   - Multi-service booking
   - Group bookings

### Phase 3: Performance
1. Optimization
   - Slot caching
   - Batch generation
   - Query optimization
   - Background updates

## API Design

### RESTful Endpoints
```ruby
namespace :api do
  namespace :v1 do
    resources :time_slots do
      collection do
        get :available
        get :suggested
        post :validate
      end
    end
    
    resources :availability do
      collection do
        get :provider
        get :service
        get :combined
      end
    end
  end
end
```

## Cache Strategy

### Redis Implementation
```ruby
class SlotCache
  def cache_key(service_id, date, provider_id = nil)
    "slots:#{service_id}:#{date}:#{provider_id}"
  end
  
  def cache_slots(service_id, date, slots, provider_id = nil)
    Redis.current.setex(
      cache_key(service_id, date, provider_id),
      15.minutes.to_i,
      slots.to_json
    )
  end
end
```

## Background Jobs

### Slot Generation Job
```ruby
class GenerateSlotsJob < ApplicationJob
  queue_as :slots
  
  def perform(business_id, date_range)
    business = Business.find(business_id)
    service = TimeSlots::SlotGenerationService.new(business)
    
    service.generate_slots(date_range)
  end
end
```

## Testing Strategy

### Unit Tests
- Slot generation logic
- Availability checks
- Rule enforcement
- Cache operations

### Integration Tests
- Calendar integration
- Provider availability
- Service constraints
- Real-time updates

### Performance Tests
- Large date ranges
- Multiple providers
- Concurrent access
- Cache efficiency

## Monitoring

### Key Metrics
- Generation time
- Cache hit ratio
- Conflict rate
- Response time

### Health Checks
- Slot availability
- Cache status
- Calendar sync
- API health

## Documentation

### Technical Guide
1. Slot Generation
2. Availability Rules
3. Integration Points
4. Caching Strategy

### User Guide
1. Time Slot Setup
2. Rule Configuration
3. Calendar Integration
4. Troubleshooting
