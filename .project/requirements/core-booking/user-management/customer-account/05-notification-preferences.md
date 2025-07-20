# Implementation Task: Notification Preferences

## Overview
Create a comprehensive notification preference system that allows customers to control how and when they receive communications.

## Technical Design

### Models
```ruby
class NotificationPreference < ApplicationRecord
  belongs_to :customer
  
  store :channel_preferences, accessors: [
    :email_enabled,
    :sms_enabled,
    :push_enabled,
    :whatsapp_enabled
  ], coder: JSON
  
  store :type_preferences, accessors: [
    :appointment_reminders,
    :service_updates,
    :marketing_messages,
    :special_offers,
    :feedback_requests
  ], coder: JSON
  
  store :schedule_preferences, accessors: [
    :quiet_hours_start,
    :quiet_hours_end,
    :preferred_days,
    :timezone
  ], coder: JSON
  
  validates :timezone, presence: true
end

class NotificationSchedule < ApplicationRecord
  belongs_to :customer
  belongs_to :notification_type
  
  validates :frequency, inclusion: { in: %w[instant daily weekly monthly] }
  validates :time_of_day, presence: true, if: :scheduled?
  
  scope :active, -> { where(active: true) }
  scope :due_now, -> { where('next_send_at <= ?', Time.current) }
end
```

### Service Objects
```ruby
class NotificationPreferenceService
  def self.update_preferences(customer, params)
    NotificationPreference.transaction do
      # Update preferences
      # Validate combinations
      # Update schedules
      # Handle channel updates
    end
  end
  
  def self.validate_delivery(customer, notification_type, channel)
    # Check preferences
    # Verify quiet hours
    # Check frequency limits
    # Validate channel status
  end
end

class NotificationOptOutService
  def self.process_opt_out(customer, channel, category)
    # Handle opt-out request
    # Update preferences
    # Record opt-out reason
    # Send confirmation
  end
end
```

### Background Jobs
```ruby
class NotificationDigestJob < ApplicationJob
  def perform(customer_id)
    # Compile pending notifications
    # Apply preferences
    # Generate digest
    # Send through preferred channel
  end
end

class PreferenceUpdateJob < ApplicationJob
  def perform(customer_id, changes)
    # Process preference changes
    # Update notification schedules
    # Sync with external services
  end
end
```

## Views
1. Preference Management
   - Channel settings
   - Notification types
   - Schedule preferences
   - Quick toggles

2. Notification Center
   - Message history
   - Preference shortcuts
   - Channel status

## API Endpoints
```ruby
# PATCH /api/v1/customers/notification_preferences
{
  "preferences": {
    "channels": {
      "email": boolean,
      "sms": boolean,
      "push": boolean
    },
    "types": {
      "appointment_reminders": boolean,
      "marketing": boolean
    },
    "schedule": {
      "quiet_hours": {},
      "preferred_days": []
    }
  }
}

# POST /api/v1/notifications/opt-out
{
  "channel": "string",
  "category": "string",
  "reason": "string"
}
```

## Testing Strategy
1. Model Tests
   - Preference validation
   - Schedule handling
   - Channel configuration

2. Service Tests
   - Preference updates
   - Delivery validation
   - Opt-out processing

3. Integration Tests
   - Complete preference flow
   - Notification delivery
   - API functionality

## Security Considerations
- Channel verification
- Preference access control
- Rate limiting
- Audit logging
- Privacy compliance
- Opt-out handling

## Estimated Hours: 16

## Dependencies
- Core Customer Models
- Notification System
- Communication Services
