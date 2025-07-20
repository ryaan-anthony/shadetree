# Implementation Task: Price Calculator

## Overview
Implement a flexible price calculation system that handles base pricing, adjustments, taxes, and total calculations for quote line items while supporting various pricing strategies.

## Technical Design

### Models
```ruby
class PriceCalculation < ApplicationRecord
  belongs_to :calculatable, polymorphic: true
  has_many :calculation_items
  has_many :adjustments
  
  store :calculation_config, accessors: [
    :pricing_strategy,
    :rounding_rules,
    :tax_handling,
    :currency_settings
  ]
  
  validates :status, inclusion: { in: %w[draft calculating reviewed final] }
end

class CalculationItem < ApplicationRecord
  belongs_to :price_calculation
  has_many :modifiers
  
  store :item_details, accessors: [
    :base_amount,
    :adjustments,
    :tax_amounts,
    :final_amount
  ]
  
  validates :item_type, inclusion: { in: %w[service option addon tax adjustment] }
end

class PriceModifier < ApplicationRecord
  belongs_to :calculation_item
  
  store :modifier_config, accessors: [
    :modification_type,
    :value,
    :application_rules,
    :conditions
  ]
  
  validates :modifier_type, inclusion: { in: %w[percentage fixed multiplier] }
end
```

### Service Layer
```ruby
module PriceCalculator
  class CalculationService
    def initialize(quote_item)
      @item = quote_item
      @config = quote_item.quote_builder.business.price_configuration
    end
    
    def calculate_price
      ActiveRecord::Base.transaction do
        calculate_base_price
        apply_modifiers
        calculate_taxes
        finalize_calculation
      end
    end
    
    private
    
    def calculate_base_price
      # Calculate initial price based on service
    end
    
    def apply_modifiers
      # Apply price modifiers and adjustments
    end
  end
  
  class TaxCalculator
    def initialize(calculation)
      @calculation = calculation
    end
    
    def calculate_taxes
      determine_tax_rules
      calculate_tax_amounts
      apply_tax_adjustments
    end
  end
end
```

## Implementation Steps

### Phase 1: Core Calculation
1. Base Price
   - Service pricing
   - Option costs
   - Add-on pricing
   - Quantity handling

2. Modifier System
   - Adjustment types
   - Discount handling
   - Surcharge application
   - Custom modifiers

3. Tax Engine
   - Tax rule application
   - Rate calculation
   - Exemption handling
   - Tax categories

### Phase 2: Advanced Features
1. Complex Pricing
   - Volume pricing
   - Tiered rates
   - Bundle pricing
   - Dynamic pricing

2. Currency Handling
   - Multi-currency support
   - Exchange rates
   - Rounding rules
   - Currency conversion

### Phase 3: Optimization
1. Performance
   - Calculation caching
   - Batch processing
   - Memory optimization
   - Background jobs

## API Design

### RESTful Endpoints
```ruby
namespace :api do
  namespace :v1 do
    resources :calculations do
      collection do
        post :preview
        get :tax_rates
      end
      member do
        post :recalculate
        post :finalize
      end
    end
  end
end
```

## Background Jobs

### Price Calculator
```ruby
class CalculatePricesJob < ApplicationJob
  queue_as :calculations
  
  def perform(quote_builder_id)
    builder = QuoteBuilder.find(quote_builder_id)
    calculator = PriceCalculator::CalculationService.new(builder)
    
    calculator.calculate_all_items
  end
end
```

## Cache Strategy

### Redis Implementation
```ruby
class CalculationCache
  def cache_key(item_id, config = {})
    "calculation:#{item_id}:#{config.hash}"
  end
  
  def cache_calculation(item_id, result, config = {})
    Redis.current.setex(
      cache_key(item_id, config),
      15.minutes.to_i,
      result.to_json
    )
  end
end
```

## Testing Strategy

### Unit Tests
- Base calculations
- Modifier application
- Tax computation
- Currency handling

### Integration Tests
- Full price calculation
- Tax integration
- Currency conversion
- Modifier chains

### Performance Tests
- Large calculations
- Concurrent processing
- Cache efficiency
- Memory usage

## Monitoring

### Key Metrics
- Calculation accuracy
- Processing time
- Cache hit ratio
- Error frequency

### Health Checks
- Service status
- Tax rates
- Exchange rates
- Cache health

## Documentation

### Technical Guide
1. Calculation Setup
2. Modifier System
3. Tax Configuration
4. Currency Handling

### User Guide
1. Price Configuration
2. Modifier Management
3. Tax Rules
4. Troubleshooting
