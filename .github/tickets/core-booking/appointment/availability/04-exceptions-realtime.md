# Implementation Task: Availability Exceptions & Real-time Updates

## Overview
Implement a system to manage availability exceptions (holidays, time-off, special events) and ensure real-time propagation of availability changes across the platform.

## Technical Design

### Models
```ruby
class AvailabilityException < ApplicationRecord
  belongs_to :business
  belongs_to :creator, polymorphic: true
  has_many :affected_appointments
  
  store :exception_config, accessors: [
    :recurrence_rule,
    :notification_preferences,
    :affected_services,
    :affected_staff
  ]
  
  validates :start_time, :end_time, presence: true
  validates :exception_type, inclusion: { in: %w[holiday time_off special_event maintenance emergency] }
  validates :status, inclusion: { in: %w[scheduled active completed cancelled] }
end

class AvailabilityUpdate < ApplicationRecord
  belongs_to :source, polymorphic: true
  has_many :notifications
  
  store :update_details, accessors: [
    :change_type,
    :previous_state,
    :new_state,
    :affected_resources
  ]
  
  validates :update_type, inclusion: { in: %w[schedule exception capacity override] }
end
```

### Service Layer
```ruby
module Availability
  class ExceptionService
    def initialize(business)
      @business = business
    end
    
    def create_exception(params)
      exception = build_exception(params)
      process_affected_appointments(exception)
      notify_stakeholders(exception)
      broadcast_updates(exception)
    end
    
    private
    
    def process_affected_appointments(exception)
      # Handle existing appointments during exception period
    end
  end
  
  class UpdateBroadcaster
    include ActionCable::Channel::Broadcasting
    
    def broadcast_update(update)
      affected_channels(update).each do |channel|
        broadcast_to channel, serialize_update(update)
      end
    end
  end
end
```

## Implementation Steps

### Phase 1: Exception Management
1. Exception Types
   - Holidays setup
   - Time-off handling
   - Special events
   - Emergency closures

2. Conflict Resolution
   - Appointment rescheduling
   - Customer notification
   - Staff updates
   - Resource reallocation

3. Recurrence Handling
   - Pattern definition
   - Rule application
   - Override system
   - Update propagation

### Phase 2: Real-time Updates
1. Change Detection
   - Schedule changes
   - Exception creation
   - Capacity updates
   - Override application

2. Update Distribution
   - WebSocket channels
   - Client synchronization
   - State management
   - Conflict handling

### Phase 3: Integration
1. Notification System
   - Customer alerts
   - Staff notifications
   - Admin updates
   - External systems

## WebSocket Implementation

### Channel Configuration
```ruby
# app/channels/availability_channel.rb
class AvailabilityChannel < ApplicationCable::Channel
  def subscribed
    stream_from "availability_#{params[:business_id]}"
    stream_for current_user if current_user
  end
  
  def receive(data)
    process_client_update(data)
  end
end
```

### Client Updates
```javascript
// app/javascript/channels/availability_channel.js
import consumer from "./consumer"

const availabilityChannel = consumer.subscriptions.create("AvailabilityChannel", {
  connected() {
    this.installHandlers()
  },
  
  received(data) {
    this.handleUpdate(data)
  }
})
```

## Background Jobs

### Exception Processor
```ruby
class ProcessExceptionJob < ApplicationJob
  queue_as :exceptions
  
  def perform(exception_id)
    exception = AvailabilityException.find(exception_id)
    service = Availability::ExceptionService.new(exception.business)
    
    service.process_exception
  end
end
```

## Cache Strategy

### Redis Implementation
```ruby
class ExceptionCache
  def cache_key(business_id, date)
    "exceptions:#{business_id}:#{date}"
  end
  
  def cache_exceptions(business_id, date, exceptions)
    Redis.current.setex(
      cache_key(business_id, date),
      1.hour.to_i,
      exceptions.to_json
    )
  end
end
```

## Testing Strategy

### Unit Tests
- Exception creation
- Update broadcasting
- State management
- Cache operations

### Integration Tests
- Real-time updates
- Client sync
- Notification delivery
- Conflict handling

### Load Tests
- Concurrent updates
- Broadcast performance
- Client connections
- State consistency

## Monitoring

### Key Metrics
- Update latency
- Broadcast success
- Client sync rate
- Exception processing

### Health Checks
- WebSocket status
- Cache health
- Job processing
- Client connections

## Documentation

### Technical Guide
1. Exception System
2. Real-time Updates
3. WebSocket Setup
4. State Management

### User Guide
1. Managing Exceptions
2. Handling Updates
3. Client Integration
4. Troubleshooting
