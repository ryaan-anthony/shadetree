# Implementation Task: Multi-Factor Authentication

## Overview
Implement a comprehensive MFA system supporting multiple second-factor methods including TOTP, SMS, and recovery codes.

## Technical Design

### Models
```ruby
class MfaMethod < ApplicationRecord
  belongs_to :user
  
  store_encrypted :secret, coder: JSON
  store_encrypted :backup_codes, coder: JSON
  
  validates :method_type, inclusion: { in: %w[totp sms backup_codes] }
  validates :status, inclusion: { in: %w[enabled disabled revoked] }
  
  scope :active, -> { where(status: 'enabled') }
  scope :primary, -> { where(is_primary: true) }
end

class MfaChallenge < ApplicationRecord
  belongs_to :user
  belongs_to :session, class_name: 'UserSession', optional: true
  
  has_secure_token :challenge_token
  validates :expires_at, presence: true
  validates :challenge_type, inclusion: { in: %w[totp sms] }
  
  scope :pending, -> { where(completed_at: nil).where('expires_at > ?', Time.current) }
end
```

### Service Objects
```ruby
class MfaService
  def self.setup_totp(user)
    MfaMethod.transaction do
      # Generate TOTP secret
      # Create backup codes
      # Store encrypted data
      # Generate QR code
    end
  end
  
  def self.verify_totp(user, code)
    # Validate TOTP code
    # Check time window
    # Handle used codes
    # Log verification
  end
  
  def self.initiate_sms_challenge(user)
    MfaChallenge.transaction do
      # Generate challenge
      # Send SMS code
      # Store challenge
      # Set expiration
    end
  end
end

class BackupCodeService
  def self.generate_codes(user)
    # Generate secure codes
    # Store encrypted codes
    # Format for display
    # Log generation
  end
  
  def self.verify_code(user, code)
    # Validate backup code
    # Mark as used
    # Log usage
    # Check remaining codes
  end
end
```

### Controllers
```ruby
class Mfa::SetupController < ApplicationController
  def initialize_totp
    @setup = MfaService.setup_totp(current_user)
    # Handle setup response
  end
  
  def verify_setup
    @result = MfaService.verify_setup(
      current_user,
      setup_params[:code]
    )
    # Handle verification
  end
end

class Mfa::ChallengeController < ApplicationController
  def create
    @challenge = MfaService.create_challenge(
      current_user,
      challenge_params[:method]
    )
    # Handle challenge creation
  end
  
  def verify
    @result = MfaService.verify_challenge(
      current_user,
      verify_params[:code]
    )
    # Handle verification
  end
end
```

### Background Jobs
```ruby
class MfaChallengeCleanupJob < ApplicationJob
  def perform
    # Clean up expired challenges
    # Log cleanup results
  end
end

class MfaReminderJob < ApplicationJob
  def perform(user_id)
    # Check pending challenges
    # Send reminders
    # Update challenge status
  end
end
```

## Views
1. MFA Setup
   - Method selection
   - TOTP setup with QR
   - Backup codes display
   - Verification form

2. Challenge Response
   - Code input
   - Method switching
   - Resend options
   - Backup code entry

## API Endpoints
```ruby
# POST /api/v1/mfa/setup
{
  "method": "totp|sms",
  "phone_number": "string" // for SMS
}

# POST /api/v1/mfa/verify
{
  "challenge_token": "string",
  "code": "string"
}
```

## Testing Strategy
1. Model Tests
   - Secret encryption
   - Code validation
   - Challenge lifecycle
   - Backup code management

2. Service Tests
   - TOTP generation
   - SMS delivery
   - Code verification
   - Challenge handling

3. Integration Tests
   - Complete setup flow
   - Challenge resolution
   - API endpoints
   - Recovery process

## Security Considerations
- Secret encryption
- Code transmission
- Time-based validation
- Rate limiting
- Brute force prevention
- Audit logging
- Recovery process security

## Estimated Hours: 20

## Dependencies
- Core Authentication System
- SMS Gateway Integration
- QR Code Generation Library
