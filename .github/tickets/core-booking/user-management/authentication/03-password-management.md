# Implementation Task: Password Management

## Overview
Create a secure password management system that handles password resets, changes, and security policies while maintaining high security standards.

## Technical Design

### Models
```ruby
class PasswordReset < ApplicationRecord
  belongs_to :user
  
  has_secure_token :reset_token
  validates :expires_at, presence: true
  validates :status, inclusion: { in: %w[pending used expired cancelled] }
  
  scope :active, -> { where(status: 'pending').where('expires_at > ?', Time.current) }
end

class PasswordPolicy < ApplicationRecord
  belongs_to :business, optional: true
  
  store :requirements, accessors: [
    :minimum_length,
    :require_uppercase,
    :require_numbers,
    :require_symbols,
    :password_history_count
  ], coder: JSON
  
  validates :minimum_length, numericality: { greater_than: 7 }
end

class PasswordHistory < ApplicationRecord
  belongs_to :user
  
  store_encrypted :password_digest, coder: JSON
  validates :used_at, presence: true
  
  scope :recent, ->(count) { order(used_at: :desc).limit(count) }
end
```

### Service Objects
```ruby
class PasswordService
  def self.initiate_reset(email)
    User.transaction do
      # Find user
      # Generate reset token
      # Send reset email
      # Log security event
    end
  end
  
  def self.complete_reset(token, new_password)
    PasswordReset.transaction do
      # Validate token
      # Check password policy
      # Update password
      # Invalidate sessions
    end
  end
  
  def self.change_password(user, old_password, new_password)
    User.transaction do
      # Verify old password
      # Validate new password
      # Store in history
      # Update password
    end
  end
end

class PasswordPolicyService
  def self.validate_password(password, policy)
    # Check length
    # Verify complexity
    # Check history
    # Return detailed feedback
  end
end
```

### Controllers
```ruby
class PasswordsController < ApplicationController
  def forgot
    @result = PasswordService.initiate_reset(params[:email])
    # Handle result
  end
  
  def reset
    @result = PasswordService.complete_reset(
      params[:token],
      password_params[:password]
    )
    # Handle result
  end
  
  def update
    @result = PasswordService.change_password(
      current_user,
      password_params[:current_password],
      password_params[:new_password]
    )
    # Handle result
  end
end
```

### Background Jobs
```ruby
class PasswordResetCleanupJob < ApplicationJob
  def perform
    # Clean up expired resets
    # Archive security events
  end
end

class PasswordExpirationJob < ApplicationJob
  def perform
    # Check password age
    # Send expiration warnings
    # Force resets if needed
  end
end
```

## Views
1. Password Reset Flow
   - Reset request form
   - Token validation
   - New password form
   - Confirmation

2. Password Change
   - Current password verification
   - New password input
   - Policy feedback
   - Success confirmation

## API Endpoints
```ruby
# POST /api/v1/password/forgot
{
  "email": "string"
}

# POST /api/v1/password/reset
{
  "token": "string",
  "password": "string",
  "password_confirmation": "string"
}
```

## Testing Strategy
1. Model Tests
   - Token generation
   - Policy validation
   - History tracking
   - Encryption

2. Service Tests
   - Reset workflow
   - Password changes
   - Policy enforcement
   - Security events

3. Integration Tests
   - Complete reset flow
   - Change password flow
   - API functionality
   - Email delivery

## Security Considerations
- Token security
- Rate limiting
- Brute force prevention
- Password encryption
- Session invalidation
- Audit logging
- Email security

## Estimated Hours: 16

## Dependencies
- Core Authentication System
- Email Service
- Security Event System
