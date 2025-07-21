# Epic: Notification System

## Overview
Provide automated email and SMS notifications to clients and staff based on configurable triggers throughout the quote-to-payment workflow. Enable businesses to maintain professional communication and reduce manual follow-up tasks.

## Goals
- Automate client communication throughout service lifecycle
- Keep staff informed of important business events
- Reduce manual follow-up tasks and improve response times
- Maintain professional brand consistency in all communications
- Support both email and SMS notification channels

## Success Metrics
- Notification delivery rate > 95%
- Client response time improvement > 40%
- Manual follow-up task reduction > 60%
- Notification opt-out rate < 10%
- Staff notification engagement > 80%

## User Stories
- As a business owner, I want automated client notifications so I don't miss important follow-ups
- As a client, I want timely updates on my quote and service status
- As a staff member, I want notifications about new quotes and appointments assigned to me
- As a business owner, I want to customize notification templates to match my brand
- As a client, I want to choose how I receive notifications (email/SMS)

## Features

### MVP Phase (P1 - Early Value)
1. [Email Notification System](notifications/01-email-notifications.md) - Core email delivery and templates
2. [Notification Rules Engine](notifications/02-notification-rules.md) - Configure triggers and timing

### Growth Phase (P2 - Advanced Features)
3. [SMS Notifications](notifications/03-sms-notifications.md) - Text message delivery integration
4. [Template Customization](notifications/04-template-customization.md) - Brand-customized notification templates

## Technical Architecture

### Core Models
```ruby
# Notification rule configuration
class NotificationRule < ApplicationRecord
  belongs_to :business
  
  validates :name, :trigger_event, :delivery_method, presence: true
  validates :name, uniqueness: { scope: :business_id }
  
  enum trigger_event: {
    quote_sent: 0,
    quote_viewed: 1,
    quote_accepted: 2,
    quote_expired: 3,
    appointment_scheduled: 4,
    appointment_reminder: 5,
    payment_received: 6,
    staff_assigned: 7
  }
  
  enum delivery_method: { email: 0, sms: 1, both: 2 }
  enum recipient_type: { client: 0, staff: 1, owner: 2 }
  
  scope :active, -> { where(active: true) }
  scope :for_event, ->(event) { where(trigger_event: event) }
end

# Notification delivery tracking
class NotificationDelivery < ApplicationRecord
  belongs_to :notification_rule
  belongs_to :recipient, polymorphic: true # User or Client
  belongs_to :source, polymorphic: true # Quote, Appointment, etc.
  
  validates :delivery_method, :status, presence: true
  
  enum delivery_method: { email: 0, sms: 1 }
  enum status: { pending: 0, sent: 1, delivered: 2, failed: 3, bounced: 4 }
  
  scope :recent, -> { where(created_at: 1.week.ago..) }
  scope :failed, -> { where(status: [:failed, :bounced]) }
end
```

### Notification Service
```ruby
class NotificationService
  def self.trigger(event, source_object, business)
    rules = business.notification_rules.active.for_event(event)
    
    rules.each do |rule|
      recipients = determine_recipients(rule, source_object)
      
      recipients.each do |recipient|
        case rule.delivery_method
        when 'email'
          deliver_email(rule, recipient, source_object)
        when 'sms'
          deliver_sms(rule, recipient, source_object)
        when 'both'
          deliver_email(rule, recipient, source_object)
          deliver_sms(rule, recipient, source_object)
        end
      end
    end
  end
  
  private
  
  def self.deliver_email(rule, recipient, source)
    delivery = create_delivery_record(rule, recipient, source, :email)
    
    begin
      NotificationMailer.send_notification(rule, recipient, source).deliver_now
      delivery.update!(status: :sent)
    rescue => e
      delivery.update!(status: :failed, error_message: e.message)
      Rails.logger.error "Email notification failed: #{e.message}"
    end
  end
  
  def self.deliver_sms(rule, recipient, source)
    # SMS delivery implementation
    # Integration with Twilio or similar service
  end
end
```

### Email Templates
```ruby
class NotificationMailer < ApplicationMailer
  def send_notification(rule, recipient, source)
    @rule = rule
    @recipient = recipient
    @source = source
    @business = rule.business
    
    template_name = "#{rule.trigger_event}_#{rule.recipient_type}"
    
    mail(
      to: recipient.email,
      subject: render_template_subject(template_name),
      template_name: template_name
    )
  end
  
  private
  
  def render_template_subject(template_name)
    case template_name
    when 'quote_sent_client'
      "#{@business.name} - Your Service Quote ##{@source.id}"
    when 'quote_accepted_owner'
      "Quote Accepted - #{@source.client_name}"
    # ... other templates
    end
  end
end
```

## Integration Points
- Quote Management (quote status change triggers)
- Appointment Scheduling (appointment event triggers)
- Payment Processing (payment confirmation triggers)
- Staff Management (staff assignment triggers)
- Business Profile (notification branding and settings)

## Security Considerations
- Validate email addresses before sending notifications
- Implement rate limiting to prevent notification spam
- Secure notification templates to prevent injection attacks
- Audit notification rule changes and delivery failures
- Comply with email marketing regulations (CAN-SPAM, GDPR)

## MVP Scope (P1 Priority)
**Included in MVP:**
- Email notifications only
- 6 core trigger events (quote sent/viewed/accepted, appointment scheduled, payment received, staff assigned)
- Basic notification rules configuration
- Simple email templates with business branding

**Deferred to Growth Phase:**
- SMS notifications
- Advanced template customization
- Delivery scheduling and delays
- Notification analytics and reporting

## Technical Implementation Notes
```ruby
# Background job for notification processing
class NotificationJob < ApplicationJob
  queue_as :notifications
  
  def perform(event, source_id, source_type, business_id)
    source = source_type.constantize.find(source_id)
    business = Business.find(business_id)
    
    NotificationService.trigger(event, source, business)
  end
end

# Usage in controllers/services
class QuotesController < ApplicationController
  def update
    if @quote.update(quote_params)
      # Trigger notification for quote status change
      NotificationJob.perform_later(
        'quote_accepted',
        @quote.id,
        'Quote',
        current_business.id
      ) if @quote.status_changed? && @quote.accepted?
    end
  end
end
```

## Email Template Structure
```erb
<!-- app/views/notification_mailer/quote_sent_client.html.erb -->
<div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
  <div style="background: <%= @business.brand_color || '#2563eb' %>; color: white; padding: 20px;">
    <h1><%= @business.name %></h1>
  </div>
  
  <div style="padding: 20px;">
    <h2>Your Service Quote is Ready</h2>
    
    <p>Hello <%= @recipient.name %>,</p>
    
    <p>Thank you for your interest in our services. We've prepared a quote for your project:</p>
    
    <div style="background: #f8f9fa; padding: 15px; border-radius: 5px; margin: 20px 0;">
      <strong>Quote #<%= @source.id %></strong><br>
      Service: <%= @source.service_description %><br>
      Total: <%= number_to_currency(@source.total_amount) %>
    </div>
    
    <p>
      <a href="<%= quote_url(@source) %>" 
         style="background: <%= @business.brand_color || '#2563eb' %>; 
                color: white; 
                padding: 12px 24px; 
                text-decoration: none; 
                border-radius: 5px;">
        View Quote
      </a>
    </p>
  </div>
</div>
```

## Dependencies
- Business Profile Management (business branding settings)
- Email System (ActionMailer configuration)
- Background Job Processing (Sidekiq)
- Quote Management System (trigger sources)

## Estimate
- MVP Features: 13 story points (1.5 weeks)
- Growth Features: 8 story points (1 week)
- Total: 21 story points (2.5 weeks)
