# Implementation Task: Discount Management

## Overview
Create a comprehensive system for managing discounts, promotions, and special pricing offers across services and customer segments.

## Technical Design

### Models
```ruby
class DiscountProgram < ApplicationRecord
  belongs_to :business
  belongs_to :pricing_engine
  
  validates :program_type, inclusion: { in: %w[promotion coupon loyalty seasonal volume] }
  validates :status, inclusion: { in: %w[active scheduled expired cancelled] }
  
  # Store program configuration
  store :program_config, accessors: [
    :discount_rules,
    :eligibility_rules,
    :usage_limits,
    :stacking_rules
  ], coder: JSON
end

class DiscountCode < ApplicationRecord
  belongs_to :discount_program
  
  validates :code_type, inclusion: { in: %w[single_use multi_use unlimited referral] }
  
  # Store code configuration
  store :code_config, accessors: [
    :usage_count,
    :max_uses,
    :expiration_rules,
    :restrictions
  ], coder: JSON
  
  scope :active, -> { where('expires_at > ? AND status = ?', Time.current, 'active') }
end

class DiscountUsage < ApplicationRecord
  belongs_to :discount_code
  belongs_to :customer
  belongs_to :order, optional: true
  
  validates :usage_type, inclusion: { in: %w[applied saved cancelled expired] }
  
  # Store usage details
  store :usage_details, accessors: [
    :amount_saved,
    :items_discounted,
    :application_time
  ], coder: JSON
end
```

### Service Objects
```ruby
class DiscountManagementService
  def self.apply_discount(order, discount_code)
    DiscountUsage.transaction do
      # Validate discount
      # Calculate savings
      # Apply to order
      # Track usage
    end
  end
  
  def self.validate_eligibility(customer, program)
    # Check restrictions
    # Validate limits
    # Check stacking
    # Return eligibility
  end
end

class PromotionService
  def self.create_promotion(business, params)
    DiscountProgram.transaction do
      # Create program
      # Generate codes
      # Set up tracking
      # Initialize analytics
    end
  end
  
  def self.track_performance(program)
    # Calculate metrics
    # Analyze usage
    # Generate report
    # Return insights
  end
end
```

### Background Jobs
```ruby
class DiscountExpirationJob < ApplicationJob
  def perform
    # Check expiring discounts
    # Handle expirations
    # Send notifications
    # Update status
  end
end

class PromotionAnalyticsJob < ApplicationJob
  def perform(program_id)
    # Calculate metrics
    # Update analytics
    # Generate report
    # Send insights
  end
end
```

## Views
1. Discount Management
   - Program creator
   - Code generator
   - Usage tracker
   - Performance metrics

2. Customer Interface
   - Available discounts
   - Code redemption
   - Savings history
   - Eligibility check

## API Endpoints
```ruby
# POST /api/v1/discounts/validate
{
  "code": "string",
  "order": {
    "items": [],
    "customer_id": "uuid"
  }
}

# GET /api/v1/promotions/active
{
  "customer_id": "uuid",
  "service_types": ["string"]
}
```

## Testing Strategy
1. Model Tests
   - Discount validation
   - Code generation
   - Usage tracking
   - Expiration handling

2. Service Tests
   - Discount application
   - Eligibility checking
   - Stacking rules
   - Analytics calculation

3. Integration Tests
   - Complete discount flow
   - Promotion management
   - API functionality
   - Analytics accuracy

## Security Considerations
- Code validation
- Usage tracking
- Fraud prevention
- Rate limiting
- Audit logging
- Access control

## Estimated Hours: 24

## Dependencies
- Pricing Engine
- Service Pricing
