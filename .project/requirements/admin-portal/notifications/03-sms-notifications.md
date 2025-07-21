# Feature: SMS Notifications

## Overview
Extend the notification system to support SMS text messaging for time-sensitive communications and customers who prefer mobile notifications over email.

## User Stories
- As a business owner, I want to send SMS notifications for urgent updates
- As a client, I want to receive appointment reminders via text message
- As a business owner, I want to offer multiple communication channels to customers

## Tasks

### 1. Integrate SMS Service Provider
**File**: `app/services/sms_service.rb`

**Implementation Notes**:
```ruby
class SmsService
  def initialize
    @client = Twilio::REST::Client.new(
      Rails.application.credentials.twilio[:account_sid],
      Rails.application.credentials.twilio[:auth_token]
    )
  end
  
  def send_message(to:, body:, from: nil)
    from ||= Rails.application.credentials.twilio[:phone_number]
    
    message = @client.messages.create(
      body: body,
      from: from,
      to: to
    )
    
    {
      success: true,
      message_sid: message.sid,
      status: message.status
    }
  rescue Twilio::REST::RestError => e
    {
      success: false,
      error: e.message,
      error_code: e.code
    }
  end
  
  def validate_phone_number(phone)
    # Basic phone number validation
    cleaned = phone.gsub(/\D/, '')
    return false if cleaned.length < 10
    
    # Add country code if missing
    cleaned = "1#{cleaned}" if cleaned.length == 10
    "+#{cleaned}"
  end
end
```

### 2. Create SMS Notification Job
**File**: `app/jobs/notification_sms_job.rb`

**Implementation Notes**:
```ruby
class NotificationSmsJob < ApplicationJob
  queue_as :notifications
  
  def perform(delivery_id)
    delivery = NotificationDelivery.find(delivery_id)
    rule = delivery.notification_rule
    
    begin
      # Compile SMS template
      template_data = NotificationTemplateService.new(rule, delivery.source, delivery.recipient).compile_sms
      
      # Send SMS
      sms_service = SmsService.new
      result = sms_service.send_message(
        to: delivery.recipient_phone,
        body: template_data[:body]
      )
      
      if result[:success]
        delivery.mark_as_sent!
        delivery.update!(external_id: result[:message_sid])
      else
        delivery.mark_as_failed!(result[:error])
      end
      
    rescue => error
      delivery.mark_as_failed!(error.message)
      Rails.logger.error "SMS notification failed: #{error.message}"
      raise error
    end
  end
end
```

### 3. Update NotificationTemplateService for SMS
**File**: `app/services/notification_template_service.rb`

**Implementation Notes**:
```ruby
class NotificationTemplateService
  # ...existing code...
  
  def compile_sms
    template = JSON.parse(@rule.sms_template || default_sms_template)
    
    {
      body: compile_sms_template(template['body'])
    }
  end
  
  private
  
  def compile_sms_template(template_string)
    # SMS templates are shorter and don't support HTML
    variables = extract_template_variables
    
    compiled = template_string.dup
    variables.each do |variable, value|
      compiled.gsub!("{{#{variable}}}", value.to_s)
    end
    
    # Ensure SMS length limit (160 characters for single SMS)
    compiled.truncate(160, omission: '...')
  end
  
  def default_sms_template
    case @rule.trigger_event
    when 'appointment_reminder'
      {
        body: "Reminder: {{business_name}} appointment tomorrow at {{appointment_time}}. Call {{business_phone}} to reschedule."
      }
    when 'quote_accepted'
      {
        body: "Great! We received your quote acceptance. We'll contact you soon to schedule. - {{business_name}}"
      }
    else
      {
        body: "Update from {{business_name}}: {{event_description}}. Contact us at {{business_phone}} for questions."
      }
    end.to_json
  end
end
```

## Acceptance Criteria
- SMS notifications can be sent via Twilio integration
- Phone numbers are validated before sending
- SMS templates are limited to appropriate length
- SMS delivery status is tracked
- Fallback to email if SMS fails

## Estimate
- Story Points: 5
- Timeline: 3 days
- Dependencies: Twilio account, notification rules engine
