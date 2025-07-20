# Implementation Task: Cancellation Core System

## Overview
Implement a core cancellation system that handles appointment cancellations, policy enforcement, and state management while maintaining data integrity.

## Technical Design

### Models
```ruby
class CancellationPolicy < ApplicationRecord
  belongs_to :business
  has_many :policy_rules
  has_many :exceptions
  
  store :policy_config, accessors: [
    :notice_period,
    :refund_percentage,
    :allow_rescheduling,
    :max_cancellations,
    :blacklist_threshold
  ]
  
  validates :notice_period, numericality: { greater_than_or_equal_to: 0 }
  validates :refund_percentage, inclusion: { in: 0..100 }
end

class CancellationRequest < ApplicationRecord
  belongs_to :appointment
  belongs_to :requester, polymorphic: true
  has_one :refund_transaction
  
  store :cancellation_details, accessors: [
    :reason,
    :evidence,
    :policy_snapshot,
    :refund_amount
  ]
  
  validates :status, inclusion: { in: %w[pending approved denied processed] }
  validate :within_policy_period
end

class CancellationAudit < ApplicationRecord
  belongs_to :cancellation_request
  belongs_to :actor, polymorphic: true
  
  validates :action_type, inclusion: { in: %w[request review approve deny process] }
  validates :action_timestamp, presence: true
end
```

### Service Layer
```ruby
module Cancellation
  class ProcessingService
    def initialize(appointment)
      @appointment = appointment
      @policy = appointment.business.cancellation_policy
    end
    
    def process_cancellation(params)
      ActiveRecord::Base.transaction do
        create_request(params)
        apply_policy
        handle_refund if refund_applicable?
        update_availability
        notify_stakeholders
      end
    end
    
    private
    
    def apply_policy
      # Apply cancellation policy rules
    end
    
    def handle_refund
      # Process refund if applicable
    end
  end
  
  class PolicyEnforcementService
    def initialize(policy)
      @policy = policy
    end
    
    def validate_cancellation(appointment)
      validate_notice_period(appointment)
      validate_cancellation_limit(appointment.customer)
      calculate_refund_amount(appointment)
    end
  end
end
```

## Implementation Steps

### Phase 1: Core Cancellation
1. Request Processing
   - Validation system
   - Policy enforcement
   - State management
   - Audit logging

2. Policy Management
   - Rule configuration
   - Exception handling
   - Threshold management
   - Time constraints

3. Refund Handling
   - Amount calculation
   - Payment integration
   - Transaction records
   - Receipt generation

### Phase 2: Business Logic
1. Policy Rules
   - Notice periods
   - Refund percentages
   - Cancellation limits
   - Blacklist rules

2. State Management
   - Status tracking
   - State transitions
   - Validation rules
   - History logging

### Phase 3: Integration
1. External Systems
   - Payment gateway
   - Calendar system
   - Notification service
   - Analytics platform

## API Design

### RESTful Endpoints
```ruby
namespace :api do
  namespace :v1 do
    resources :appointments do
      resources :cancellations do
        member do
          post :process
          post :review
          get :refund_preview
        end
      end
    end
    
    resources :cancellation_policies do
      resources :rules
      resources :exceptions
    end
  end
end
```

## Background Jobs

### Cancellation Processor
```ruby
class ProcessCancellationJob < ApplicationJob
  queue_as :cancellations
  
  def perform(cancellation_request_id)
    request = CancellationRequest.find(cancellation_request_id)
    service = Cancellation::ProcessingService.new(request.appointment)
    
    service.process_cancellation
  end
end
```

## Cache Strategy

### Redis Implementation
```ruby
class CancellationCache
  def cache_key(appointment_id)
    "cancellation:#{appointment_id}"
  end
  
  def cache_policy_check(appointment_id, check_result)
    Redis.current.setex(
      cache_key(appointment_id),
      15.minutes.to_i,
      check_result.to_json
    )
  end
end
```

## Testing Strategy

### Unit Tests
- Policy validation
- Refund calculation
- State transitions
- Rule enforcement

### Integration Tests
- End-to-end flow
- Payment processing
- Notification sending
- Availability updates

### Load Tests
- Concurrent cancellations
- Policy evaluations
- Cache performance
- System stability

## Monitoring

### Key Metrics
- Cancellation rate
- Processing time
- Refund accuracy
- Policy compliance

### Health Checks
- Service status
- Payment gateway
- Cache health
- Job processing

## Documentation

### Technical Guide
1. Policy Configuration
2. Integration Setup
3. API Reference
4. Error Handling

### User Guide
1. Managing Policies
2. Processing Cancellations
3. Handling Refunds
4. Troubleshooting
