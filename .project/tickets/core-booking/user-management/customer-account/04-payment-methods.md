# Implementation Task: Payment Methods Management

## Overview
Create a secure payment method management system that allows customers to save and manage their preferred payment methods.

## Technical Design

### Models
```ruby
class CustomerPaymentMethod < ApplicationRecord
  belongs_to :customer
  
  encrypts :token
  store_encrypted :card_metadata, coder: JSON
  store_encrypted :billing_address, coder: JSON
  
  validates :payment_type, inclusion: { in: %w[credit_card bank_account digital_wallet] }
  validates :status, inclusion: { in: %w[active expired failed deleted] }
  
  scope :active, -> { where(status: 'active') }
  scope :default, -> { where(is_default: true) }
end

class PaymentAuthorization < ApplicationRecord
  belongs_to :customer
  belongs_to :payment_method, class_name: 'CustomerPaymentMethod'
  
  validates :authorization_type, inclusion: { in: %w[recurring one_time] }
  validates :status, inclusion: { in: %w[active revoked expired] }
  
  # For recurring payments
  store_encrypted :schedule_details, coder: JSON
end
```

### Service Objects
```ruby
class PaymentMethodService
  def self.add_payment_method(customer, params)
    CustomerPaymentMethod.transaction do
      # Validate payment token
      # Store payment method
      # Handle default setting
      # Update customer profile
    end
  end
  
  def self.authorize_recurring(payment_method, params)
    PaymentAuthorization.transaction do
      # Validate authorization request
      # Create authorization record
      # Set up recurring schedule
      # Send confirmation
    end
  end
end
```

### Controllers
```ruby
class Customers::PaymentMethodsController < ApplicationController
  before_action :authenticate_customer!
  before_action :set_payment_method, except: [:index, :new, :create]
  
  def index
    @payment_methods = current_customer.payment_methods.active
  end
  
  def create
    @result = PaymentMethodService.add_payment_method(
      current_customer,
      payment_method_params
    )
    # Handle result
  end
  
  def set_default
    @result = PaymentMethodService.set_default(
      current_customer,
      @payment_method
    )
    # Handle result
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

class RecurringAuthorizationJob < ApplicationJob
  def perform(authorization_id)
    # Process recurring payment
    # Update authorization status
    # Handle failures
  end
end
```

## Views
1. Payment Methods List
   - Saved methods display
   - Default method indicator
   - Quick actions

2. Add Payment Method
   - Payment form
   - Billing address
   - Authorization options

## API Endpoints
```ruby
# POST /api/v1/customers/payment_methods
{
  "payment_method": {
    "token": "string",
    "payment_type": "string",
    "is_default": boolean,
    "billing_address": {}
  }
}

# POST /api/v1/customers/payment_methods/:id/authorize
{
  "authorization": {
    "type": "recurring|one_time",
    "schedule": {},
    "amount_limit": number
  }
}
```

## Testing Strategy
1. Model Tests
   - Encryption handling
   - Status transitions
   - Authorization rules

2. Service Tests
   - Payment method addition
   - Authorization creation
   - Default management

3. Integration Tests
   - Complete payment flow
   - Payment processor integration
   - Authorization workflow

## Security Considerations
- PCI compliance
- Token encryption
- Authorization validation
- Access control
- Audit logging
- Rate limiting

## Estimated Hours: 20

## Dependencies
- Core Customer Models
- Payment Gateway Integration
- Encryption System
