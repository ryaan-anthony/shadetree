# Implementation Task: Business Registration Flow

## Overview
Implement the business registration workflow including form handling, validation, and initial setup.

## Technical Design

### Controllers
```ruby
class BusinessRegistrationController < ApplicationController
  def new
    @business = Business.new
    @user = User.new
  end

  def create
    # Transaction to create business, owner, and initial setup
  end
end
```

### Service Objects
```ruby
class BusinessRegistrationService
  def self.register(params)
    Business.transaction do
      # Create business
      # Create owner user
      # Set up initial configuration
      # Send welcome email
    end
  end
end
```

### Views/Forms
1. Registration Form (`app/views/business_registration/new.html.erb`)
   - Business Information
   - Owner Information
   - Terms Acceptance
   - Initial Setup Preferences

2. Email Templates
   - Welcome Email
   - Verification Email

### Routes
```ruby
# config/routes.rb
resources :business_registration, only: [:new, :create]
get 'register', to: 'business_registration#new'
```

### Background Jobs
```ruby
class BusinessSetupJob < ApplicationJob
  def perform(business_id)
    # Create default configurations
    # Set up integrations
    # Generate welcome resources
  end
end
```

## API Endpoints
```ruby
# For future mobile/SPA support
POST /api/v1/businesses
{
  "business": {
    "name": "string",
    "timezone": "string"
  },
  "owner": {
    "email": "string",
    "password": "string"
  }
}
```

## Testing Strategy
1. Controller Tests
   - Successful registration
   - Validation errors
   - Duplicate prevention

2. Integration Tests
   - Complete registration flow
   - Email delivery
   - Background job execution

3. API Tests
   - Endpoint functionality
   - Error handling

## Security Considerations
- CSRF protection
- Rate limiting registration
- Email verification
- Password strength rules
- Business name uniqueness

## Estimated Hours: 12

## Dependencies
- Core Models implementation
- Email service configuration
- Background job setup

## Notes
- Add tracking for registration source
- Implement progressive form steps
- Consider A/B testing different flows
- Add analytics hooks
