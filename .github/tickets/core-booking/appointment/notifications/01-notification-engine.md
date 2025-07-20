# Implementation Task: Notification Engine

## Overview
Create a flexible notification engine that handles all appointment-related communications across multiple channels (email, SMS, push) with support for templates and delivery preferences.

## Technical Design

### Models
```ruby
class NotificationConfig < ApplicationRecord
  belongs_to :business
  
  validates :channel_type, inclusion: { in: %w[email sms push in_app] }
  
  # Store channel configuration
  store :channel_config, accessors: [
    :provider_settings,
    :delivery_preferences,
    :retry_policy,
    :fallback_channels
  ], coder: JSON
end

class NotificationTemplate < ApplicationRecord
  belongs_to :business
  belongs_to :event_type
  
  validates :template_type, inclusion: { in: %w[appointment reminder cancellation reschedule custom] }
  validates :status, inclusion: { in: %w[active draft archived] }
  
  # Store template content
  store :template_content, accessors: [
    :subject_template,
    :body_template,
    :variables,
    :attachments
  ], coder: JSON
end

class NotificationDelivery < ApplicationRecord
  belongs_to :notification_template
  belongs_to :recipient, polymorphic: true
  
  validates :status, inclusion: { in: %w[queued sent failed bounced] }
  
  # Store delivery details
  store :delivery_details, accessors: [
    :sent_at,
    :delivery_channel,
    :tracking_data,
    :failure_reason
  ], coder: JSON
end
```

### Service Objects
```ruby
class NotificationService
  def self.send_notification(template, recipient, data)
    NotificationDelivery.transaction do
      # Prepare notification
      # Apply template
      # Choose channel
      # Send message
    end
  end
  
  def self.schedule_notification(template, recipient, data, send_at)
    # Validate schedule
    # Create delivery record
    # Queue background job
    # Return tracking info
  end
end

class TemplateService
  def self.render_template(template, data)
    # Process variables
    # Apply business rules
    # Handle attachments
    # Return content
  end
  
  def self.validate_template(template, sample_data)
    # Check syntax
    # Validate variables
    # Test rendering
    # Return validation
  end
end
```

### Background Jobs
```ruby
class NotificationDeliveryJob < ApplicationJob
  def perform(delivery_id)
    # Load delivery
    # Process template
    # Send notification
    # Track status
  end
end

class NotificationCleanupJob < ApplicationJob
  def perform
    # Archive old notifications
    # Clean up failed deliveries
    # Update statistics
    # Generate report
  end
end
```

## Event Handling
```ruby
# config/initializers/notification_events.rb
Rails.application.config.notification_events = {
  appointment: {
    created: 'AppointmentCreatedEvent',
    confirmed: 'AppointmentConfirmedEvent',
    reminder: 'AppointmentReminderEvent',
    cancelled: 'AppointmentCancelledEvent'
  }
}

class NotificationSubscriber
  def appointment_created(event)
    template = NotificationTemplate.find_by(event_type: event.type)
    NotificationService.send_notification(template, event.appointment.customer, event.data)
  end
end
```

## Testing Strategy
1. Model Tests
   - Template validation
   - Channel configuration
   - Delivery tracking
   - Status transitions

2. Service Tests
   - Notification sending
   - Template rendering
   - Channel selection
   - Scheduling logic

3. Integration Tests
   - Complete notification flow
   - Multi-channel delivery
   - Template processing
   - Error handling

## Security Considerations
- Template sanitization
- Variable escaping
- Channel validation
- Rate limiting
- Personal data handling
- Audit logging

## Estimated Hours: 24

## Dependencies
- None (Foundation Component)
