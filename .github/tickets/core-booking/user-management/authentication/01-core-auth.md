# Implementation Task: Core Authentication System

## Overview
Implement the foundational authentication system that handles user authentication, session management, and security across all user types.

## Technical Design

### Models
```ruby
class UserSession < ApplicationRecord
  belongs_to :user
  
  has_secure_token :session_token
  store_encrypted :device_info, coder: JSON
  
  validates :ip_address, presence: true
  validates :user_agent, presence: true
  validates :expires_at, presence: true
  
  scope :active, -> { where('expires_at > ?', Time.current) }
  scope :for_device, ->(device_id) { where("device_info->>'device_id' = ?", device_id) }
end

class LoginAttempt < ApplicationRecord
  belongs_to :user, optional: true
  
  validates :ip_address, presence: true
  validates :status, inclusion: { in: %w[success failure blocked] }
  
  scope :recent, -> { where('created_at > ?', 15.minutes.ago) }
  scope :failed, -> { where(status: 'failure') }
end

class SecurityEvent < ApplicationRecord
  belongs_to :user
  belongs_to :session, class_name: 'UserSession', optional: true
  
  validates :event_type, inclusion: { 
    in: %w[login logout password_change mfa_enabled mfa_disabled device_authorized] 
  }
  
  store :event_metadata, coder: JSON
end
```

### Service Objects
```ruby
class AuthenticationService
  def self.authenticate(email, password, request_info)
    User.transaction do
      # Validate credentials
      # Check rate limiting
      # Create session
      # Log security event
      # Handle 2FA if enabled
    end
  end
  
  def self.validate_session(token, request_info)
    # Verify token
    # Check expiration
    # Validate device info
    # Extend session if needed
  end
  
  def self.invalidate_session(token, reason)
    # End session
    # Log security event
    # Clean up related data
  end
end

class SecurityService
  def self.track_login_attempt(email, success, request_info)
    # Record attempt
    # Check for suspicious activity
    # Handle rate limiting
    # Trigger notifications if needed
  end
  
  def self.validate_request(request)
    # Check rate limits
    # Validate origin
    # Check security headers
    # Detect suspicious patterns
  end
end
```

### Controllers
```ruby
class AuthenticationController < ApplicationController
  def create
    result = AuthenticationService.authenticate(
      auth_params[:email],
      auth_params[:password],
      request_info
    )
    # Handle result
  end
  
  def destroy
    result = AuthenticationService.invalidate_session(
      current_session.token,
      params[:reason]
    )
    # Handle result
  end
end
```

### Background Jobs
```ruby
class SessionCleanupJob < ApplicationJob
  def perform
    # Remove expired sessions
    # Archive security events
    # Clean up login attempts
  end
end

class SuspiciousActivityJob < ApplicationJob
  def perform(user_id, event_data)
    # Analyze security events
    # Check for patterns
    # Trigger security measures
    # Send notifications
  end
end
```

## Security Headers
```ruby
# config/initializers/security_headers.rb
Rails.application.config.action_dispatch.default_headers = {
  'X-Frame-Options' => 'DENY',
  'X-XSS-Protection' => '1; mode=block',
  'X-Content-Type-Options' => 'nosniff',
  'X-Download-Options' => 'noopen',
  'X-Permitted-Cross-Domain-Policies' => 'none',
  'Referrer-Policy' => 'strict-origin-when-cross-origin'
}
```

## API Endpoints
```ruby
# POST /api/v1/auth/login
{
  "email": "string",
  "password": "string",
  "device_info": {
    "device_id": "string",
    "device_name": "string",
    "platform": "string"
  }
}

# POST /api/v1/auth/logout
{
  "reason": "string"
}
```

## Testing Strategy
1. Model Tests
   - Session management
   - Token generation
   - Event logging
   - Data encryption

2. Service Tests
   - Authentication flow
   - Session validation
   - Security checks
   - Rate limiting

3. Integration Tests
   - Complete login flow
   - Session management
   - Security headers
   - API endpoints

## Security Considerations
- Password hashing (Argon2)
- Session token security
- Rate limiting
- IP blocking
- Device fingerprinting
- Audit logging
- CSRF protection
- XSS prevention

## Estimated Hours: 24

## Dependencies
- Core User Models
- Redis for rate limiting
- Encryption system
