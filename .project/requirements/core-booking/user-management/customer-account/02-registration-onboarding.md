# Implementation Task: Customer Registration & Onboarding

## Overview
Create a streamlined registration and onboarding process for new customers, including email verification and preference setup.

## Technical Design

### Controllers
```ruby
class Customers::RegistrationController < ApplicationController
  def new
    @customer = Customer.new
    @customer.build_customer_profile
  end

  def create
    @registration = CustomerRegistrationService.register(registration_params)
    # Handle registration result
  end

  def verify_email
    @verification = CustomerVerificationService.verify(params[:token])
    # Handle verification result
  end
end

class Customers::OnboardingController < ApplicationController
  before_action :authenticate_customer!
  before_action :require_unfinished_onboarding

  def preferences
    @preference_categories = Service.category_options
  end

  def complete
    @result = CustomerOnboardingService.complete(current_customer, onboarding_params)
    # Handle completion
  end
end
```

### Service Objects
```ruby
class CustomerRegistrationService
  def self.register(params)
    Customer.transaction do
      # Create customer account
      # Generate verification token
      # Send verification email
      # Initialize onboarding state
    end
  end
end

class CustomerOnboardingService
  def self.complete(customer, params)
    Customer.transaction do
      # Save preferences
      # Set up notification preferences
      # Mark onboarding complete
      # Trigger welcome sequence
    end
  end
end
```

### Background Jobs
```ruby
class CustomerWelcomeSequenceJob < ApplicationJob
  def perform(customer_id)
    # Send welcome email
    # Schedule follow-up emails
    # Initialize customer rewards
  end
end

class CustomerVerificationReminderJob < ApplicationJob
  def perform(customer_id)
    # Check verification status
    # Send reminder if needed
    # Track reminder count
  end
end
```

### Views
1. Registration Flow
   - Registration form
   - Email verification
   - Success confirmation

2. Onboarding Flow
   - Service preferences
   - Contact preferences
   - Special requirements
   - Welcome tour

## API Endpoints
```ruby
# POST /api/v1/customers
{
  "customer": {
    "email": "string",
    "password": "string",
    "profile_attributes": {
      "first_name": "string",
      "last_name": "string",
      "phone": "string"
    }
  }
}

# POST /api/v1/customers/onboarding/complete
{
  "preferences": {
    "contact": {},
    "services": [],
    "notifications": {}
  }
}
```

## Testing Strategy
1. Controller Tests
   - Registration flow
   - Verification process
   - Onboarding steps

2. Service Tests
   - Account creation
   - Email verification
   - Preference setup

3. Integration Tests
   - Complete registration flow
   - Email delivery
   - API functionality

## Security Considerations
- Password strength requirements
- Email verification requirement
- Rate limiting registration
- Input sanitization
- Session management
- CSRF protection

## Estimated Hours: 16

## Dependencies
- Core Customer Models
- Email service setup
- Authentication system
