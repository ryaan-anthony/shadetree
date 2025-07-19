# Implementation Task: Billing Information Setup

## Overview
Create a secure system for managing business billing information, payment methods, and subscription details.

## Technical Design

### Models
```ruby
class BillingInfo < ApplicationRecord
  belongs_to :business
  encrypts :tax_number
  
  store_encrypted :billing_address, coder: JSON
  validates :billing_email, format: { with: URI::MailTo::EMAIL_REGEXP }
end

class PaymentMethod < ApplicationRecord
  belongs_to :business
  
  # Store tokenized payment info from payment processor
  encrypts :token
  store_encrypted :card_metadata, coder: JSON
  
  validates :provider, inclusion: { in: %w[stripe square braintree] }
  validates :status, inclusion: { in: %w[active expired failed] }
end
```

### Service Objects
```ruby
class BillingSetupService
  def self.setup_billing(business, params)
    Business.transaction do
      # Create/update billing info
      # Setup payment method
      # Initialize subscription
      # Setup tax settings
    end
  end
  
  def self.update_payment_method(business, params)
    PaymentMethod.transaction do
      # Validate payment token
      # Update payment method
      # Handle subscription update
      # Send confirmation
    end
  end
end
```

### Controllers
```ruby
class Business::BillingController < BusinessController
  def setup
    @billing_info = @business.billing_info || @business.build_billing_info
  end
  
  def create
    result = BillingSetupService.setup_billing(@business, billing_params)
    # Handle result
  end
  
  def payment_methods
    @payment_methods = @business.payment_methods.active
  end
end
```

### Background Jobs
```ruby
class PaymentMethodExpirationJob < ApplicationJob
  def perform
    # Check for expiring payment methods
    # Send notification reminders
    # Update payment status
  end
end

class BillingSetupCompletionJob < ApplicationJob
  def perform(business_id)
    # Finalize billing setup
    # Initialize services
    # Send welcome materials
  end
end
```

## Views
1. Billing Setup
   - Billing information form
   - Tax information
   - Payment method setup

2. Payment Methods
   - Payment method list
   - Add/remove methods
   - Default method selection

## API Endpoints
```ruby
# POST /api/v1/business/billing/setup
{
  "billing_info": {
    "billing_email": "string",
    "tax_number": "string",
    "billing_address": {}
  },
  "payment_method": {
    "token": "string",
    "provider": "string"
  }
}
```

## Testing Strategy
1. Model Tests
   - Encryption handling
   - Validation rules
   - Payment method lifecycle

2. Service Tests
   - Billing setup process
   - Payment method updates
   - Error handling

3. Integration Tests
   - Complete billing setup
   - Payment processor integration
   - API functionality

## Security Considerations
- PCI compliance
- Data encryption
- Token handling
- Audit logging
- Access control

## Estimated Hours: 20

## Dependencies
- Core Models implementation
- Payment processor integration
- Subscription system
