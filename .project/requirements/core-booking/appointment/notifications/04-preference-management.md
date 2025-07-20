# Implementation Task: Preference Management

## Overview
Create a comprehensive notification preference system that allows customers and staff to manage their communication preferences across different notification types and channels.

## Technical Design

### Models
```ruby
class NotificationPreference < ApplicationRecord
  belongs_to :subscriber, polymorphic: true
  
  validates :subscription_type, inclusion: { in: %w[appointments quotes marketing system] }
  validates :status, inclusion: { in: %w[active unsubscribed custom] }
  
  # Store preference configuration
  store :channel_preferences, accessors: [
    :email_enabled,
    :sms_enabled,
    :push_enabled,
    :in_app_enabled
  ], coder: JSON
  
  # Store timing preferences
  store :timing_preferences, accessors: [
    :preferred_time,
    :timezone,
    :quiet_hours,
    :frequency_limits
  ], coder: JSON
end

class NotificationRule < ApplicationRecord
  belongs_to :notification_preference
  
  validates :rule_type, inclusion: { in: %w[time channel frequency custom] }
  
  # Store rule configuration
  store :rule_config, accessors: [
    :conditions,
    :actions,
    :exceptions,
    :priority
  ], coder: JSON
end

class UnsubscribeToken < ApplicationRecord
  belongs_to :notification_preference
  
  has_secure_token :unsubscribe_token
  validates :token_type, inclusion: { in: %w[global type_specific message_specific] }
  
  # Store token configuration
  store :token_config, accessors: [
    :scope,
    :expiration,
    :usage_limit,
    :metadata
  ], coder: JSON
end
```

### Service Objects
```ruby
class PreferenceManagementService
  def self.update_preferences(subscriber, preferences)
    NotificationPreference.transaction do
      # Update preferences
      # Apply rules
      # Handle unsubscribes
      # Update tokens
    end
  end
  
  def self.check_preferences(subscriber, notification_type)
    # Load preferences
    # Apply rules
    # Check timing
    # Return delivery options
  end
end

class UnsubscribeService
  def self.process_unsubscribe(token, options = {})
    NotificationPreference.transaction do
      # Validate token
      # Update preferences
      # Log unsubscribe
      # Send confirmation
    end
  end
  
  def self.generate_token(preference, scope)
    # Create token
    # Set expiration
    # Store metadata
    # Return token
  end
end
```

### Background Jobs
```ruby
class PreferenceCleanupJob < ApplicationJob
  def perform
    # Clean old tokens
    # Archive preferences
    # Update statistics
    # Generate report
  end
end

class PreferenceValidationJob < ApplicationJob
  def perform(subscriber_id)
    # Validate preferences
    # Check conflicts
    # Update status
    # Send notifications
  end
end
```

## Preference Management UI
```ruby
# app/components/preference_manager_component.rb
class PreferenceManagerComponent < ViewComponent::Base
  def initialize(subscriber:)
    @preferences = load_preferences(subscriber)
    @channels = available_channels
    @notification_types = notification_types
  end
  
  private
  
  def load_preferences(subscriber)
    PreferenceManagementService.load_preferences(subscriber)
  end
end
```

## Testing Strategy
1. Model Tests
   - Preference validation
   - Rule processing
   - Token management
   - Status transitions

2. Service Tests
   - Preference updates
   - Rule application
   - Unsubscribe handling
   - Token generation

3. Integration Tests
   - Complete preference flow
   - Unsubscribe process
   - Rule enforcement
   - UI functionality

## Security Considerations
- Token security
- Preference validation
- Access control
- Rate limiting
- Audit logging
- Privacy compliance

## Estimated Hours: 20

## Dependencies
- Notification Engine
- Delivery Management
