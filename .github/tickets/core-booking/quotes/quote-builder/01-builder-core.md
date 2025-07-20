# Implementation Task: Quote Builder Core System

## Overview
Implement the core quote builder system that manages quote construction, line item handling, and state management using the Builder pattern.

## Technical Design

### Models
```ruby
class QuoteBuilder < ApplicationRecord
  belongs_to :business
  belongs_to :creator, class_name: 'Staff'
  has_many :line_items, class_name: 'QuoteLineItem'
  has_many :build_activities
  
  store :builder_state, accessors: [
    :current_step,
    :validation_state,
    :temp_calculations,
    :draft_settings
  ]
  
  validates :status, inclusion: { in: %w[draft building reviewing ready complete] }
end

class QuoteLineItem < ApplicationRecord
  belongs_to :quote_builder
  belongs_to :service
  has_many :options
  has_many :adjustments
  
  store :item_config, accessors: [
    :quantity,
    :options_selected,
    :custom_fields,
    :price_overrides
  ]
  
  validates :position, presence: true, numericality: { only_integer: true }
  validates :base_price, :final_price, presence: true
end

class BuildActivity < ApplicationRecord
  belongs_to :quote_builder
  belongs_to :actor, polymorphic: true
  
  validates :activity_type, inclusion: { in: %w[add_item remove_item update_item change_state] }
  validates :occurred_at, presence: true
end
```

### Service Layer
```ruby
module QuoteBuilder
  class Director
    def initialize(business)
      @business = business
      @builder = new_builder
    end
    
    def build_quote(params)
      ActiveRecord::Base.transaction do
        initialize_quote(params)
        add_line_items(params[:items])
        apply_business_rules
        calculate_totals
      end
    end
    
    private
    
    def initialize_quote(params)
      @builder.create_quote(params)
      @builder.set_initial_state
    end
  end
  
  class LineItemManager
    def initialize(builder)
      @builder = builder
    end
    
    def add_item(params)
      validate_item(params)
      create_line_item(params)
      recalculate_quote
    end
    
    def update_item(item_id, params)
      item = find_item(item_id)
      update_item_details(item, params)
      recalculate_quote
    end
  end
end
```

## Implementation Steps

### Phase 1: Core Structure
1. Quote Building
   - Builder initialization
   - State management
   - Validation rules
   - Activity tracking

2. Line Items
   - Item creation
   - Position management
   - Bulk operations
   - Validation system

3. State Machine
   - Status transitions
   - State persistence
   - Event handling
   - Rollback support

### Phase 2: Business Logic
1. Rule Engine
   - Business rules
   - Validation logic
   - Constraint checking
   - Error handling

2. Calculation System
   - Base calculations
   - Running totals
   - Tax handling
   - Rounding rules

### Phase 3: Integration
1. Service Integration
   - Service lookup
   - Option handling
   - Price fetching
   - Availability check

## API Design

### RESTful Endpoints
```ruby
namespace :api do
  namespace :v1 do
    resources :quote_builders do
      resources :line_items do
        collection do
          post :bulk_create
          post :reorder
        end
        member do
          post :duplicate
          post :recalculate
        end
      end
      member do
        post :complete
        post :reset
        get :preview
      end
    end
  end
end
```

## Background Jobs

### Quote Calculator
```ruby
class CalculateQuoteJob < ApplicationJob
  queue_as :quotes
  
  def perform(builder_id)
    builder = QuoteBuilder.find(builder_id)
    calculator = QuoteBuilder::Calculator.new(builder)
    
    calculator.recalculate_all
  end
end
```

## Cache Strategy

### Redis Implementation
```ruby
class BuilderCache
  def cache_key(builder_id)
    "builder:#{builder_id}:state"
  end
  
  def cache_state(builder_id, state)
    Redis.current.setex(
      cache_key(builder_id),
      30.minutes.to_i,
      state.to_json
    )
  end
end
```

## Testing Strategy

### Unit Tests
- Builder operations
- Line item handling
- State transitions
- Calculation accuracy

### Integration Tests
- End-to-end building
- Service integration
- Price calculation
- State management

### Performance Tests
- Large quote handling
- Concurrent building
- Cache efficiency
- Memory usage

## Monitoring

### Key Metrics
- Build success rate
- Processing time
- Error frequency
- Memory usage

### Health Checks
- Service status
- Cache health
- Job processing
- API performance

## Documentation

### Technical Guide
1. Builder Pattern Usage
2. State Management
3. Integration Points
4. Error Handling

### User Guide
1. Quote Creation
2. Item Management
3. State Handling
4. Best Practices
