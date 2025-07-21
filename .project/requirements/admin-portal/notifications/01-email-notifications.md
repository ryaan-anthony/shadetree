# Feature: Email Notification System

## Overview
Implement the core email delivery system that sends automated notifications to clients and staff based on business events. This provides the foundation for all email-based communication automation.

## User Stories
- As a business owner, I want automated client notifications so I don't miss important follow-ups
- As a client, I want timely updates on my quote and service status
- As a staff member, I want notifications about new quotes and appointments assigned to me

## Tasks

### 1. Create NotificationRule Model
**File**: `app/models/notification_rule.rb`

**Implementation Notes**:
```ruby
class NotificationRule < ApplicationRecord
  belongs_to :business
  belongs_to :created_by, class_name: 'User'
  has_many :notification_deliveries, dependent: :destroy
  
  validates :name, :trigger_event, :delivery_method, :recipient_type, presence: true
  validates :name, uniqueness: { scope: :business_id }
  validates :email_template, presence: true
  
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
  enum recipient_type: { client: 0, staff: 1, owner: 2, all_staff: 3 }
  
  scope :active, -> { where(active: true) }
  scope :for_event, ->(event) { where(trigger_event: event) }
  scope :for_delivery_method, ->(method) { where(delivery_method: [method, 'both']) }
  
  def self.default_rules_for_business(business)
    [
      {
        name: 'Quote Sent to Client',
        trigger_event: 'quote_sent',
        delivery_method: 'email',
        recipient_type: 'client',
        email_template: default_quote_sent_template,
        active: true
      },
      {
        name: 'Quote Accepted Notification',
        trigger_event: 'quote_accepted',
        delivery_method: 'email',
        recipient_type: 'owner',
        email_template: default_quote_accepted_template,
        active: true
      },
      {
        name: 'Appointment Confirmation',
        trigger_event: 'appointment_scheduled',
        delivery_method: 'email',
        recipient_type: 'client',
        email_template: default_appointment_template,
        active: true
      }
    ]
  end
  
  private
  
  def self.default_quote_sent_template
    {
      subject: 'Your Service Quote from {{business_name}}',
      body: default_quote_sent_body
    }.to_json
  end
  
  def self.default_quote_sent_body
    <<~HTML
      <p>Hello {{client_name}},</p>
      
      <p>Thank you for your interest in our services! We've prepared a quote for your project:</p>
      
      <div style="background: #f8f9fa; padding: 15px; border-radius: 5px; margin: 20px 0;">
        <strong>Quote #{{quote_id}}</strong><br>
        Service: {{service_description}}<br>
        Total: {{quote_amount}}
      </div>
      
      <p><a href="{{quote_url}}" style="background: #2563eb; color: white; padding: 12px 24px; text-decoration: none; border-radius: 5px;">View Quote</a></p>
      
      <p>If you have any questions, please don't hesitate to contact us.</p>
      
      <p>Best regards,<br>{{business_name}}<br>{{business_phone}}</p>
    HTML
  end
end
```

### 2. Create NotificationDelivery Model
**File**: `app/models/notification_delivery.rb`

**Implementation Notes**:
```ruby
class NotificationDelivery < ApplicationRecord
  belongs_to :notification_rule
  belongs_to :recipient, polymorphic: true
  belongs_to :source, polymorphic: true
  
  validates :delivery_method, :status, presence: true
  validates :recipient_email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  
  enum delivery_method: { email: 0, sms: 1 }
  enum status: { pending: 0, sent: 1, delivered: 2, failed: 3, bounced: 4 }
  
  scope :recent, -> { where(created_at: 1.week.ago..) }
  scope :failed, -> { where(status: [:failed, :bounced]) }
  scope :successful, -> { where(status: [:sent, :delivered]) }
  
  def mark_as_sent!
    update!(status: :sent, sent_at: Time.current)
  end
  
  def mark_as_delivered!
    update!(status: :delivered, delivered_at: Time.current)
  end
  
  def mark_as_failed!(error_message)
    update!(
      status: :failed, 
      error_message: error_message,
      failed_at: Time.current
    )
  end
  
  def delivery_time
    return nil unless sent_at
    
    if delivered_at
      delivered_at - sent_at
    else
      Time.current - sent_at
    end
  end
end
```

### 3. Create NotificationService
**File**: `app/services/notification_service.rb`

**Implementation Notes**:
```ruby
class NotificationService
  def self.trigger(event, source_object, business = nil)
    business ||= source_object.business
    rules = business.notification_rules.active.for_event(event)
    
    rules.each do |rule|
      recipients = determine_recipients(rule, source_object, business)
      
      recipients.each do |recipient|
        deliver_notification(rule, recipient, source_object)
      end
    end
  end
  
  private
  
  def self.determine_recipients(rule, source_object, business)
    case rule.recipient_type
    when 'client'
      [determine_client(source_object)]
    when 'staff'
      [determine_assigned_staff(source_object)]
    when 'owner'
      business.users.where(business_users: { role: 'owner' })
    when 'all_staff'
      business.users.where(business_users: { role: ['admin', 'staff'] })
    end.compact
  end
  
  def self.determine_client(source_object)
    case source_object
    when Quote
      source_object.client
    when Appointment
      source_object.client
    when Job
      source_object.client
    else
      nil
    end
  end
  
  def self.determine_assigned_staff(source_object)
    case source_object
    when Quote
      source_object.assigned_to
    when Appointment
      source_object.assigned_staff
    when Job
      source_object.assigned_staff
    else
      nil
    end
  end
  
  def self.deliver_notification(rule, recipient, source_object)
    return unless recipient
    
    delivery = create_delivery_record(rule, recipient, source_object)
    
    case rule.delivery_method
    when 'email', 'both'
      NotificationEmailJob.perform_later(delivery.id)
    when 'sms', 'both'
      NotificationSmsJob.perform_later(delivery.id) if rule.delivery_method.in?(['sms', 'both'])
    end
  end
  
  def self.create_delivery_record(rule, recipient, source_object)
    NotificationDelivery.create!(
      notification_rule: rule,
      recipient: recipient,
      source: source_object,
      delivery_method: rule.delivery_method == 'both' ? 'email' : rule.delivery_method,
      recipient_email: recipient.email,
      status: :pending
    )
  end
end
```

### 4. Create NotificationEmailJob
**File**: `app/jobs/notification_email_job.rb`

**Implementation Notes**:
```ruby
class NotificationEmailJob < ApplicationJob
  queue_as :notifications
  
  def perform(delivery_id)
    delivery = NotificationDelivery.find(delivery_id)
    rule = delivery.notification_rule
    
    begin
      template_data = NotificationTemplateService.new(rule, delivery.source, delivery.recipient).compile
      
      NotificationMailer.send_notification(
        delivery.recipient_email,
        template_data[:subject],
        template_data[:body],
        rule.business
      ).deliver_now
      
      delivery.mark_as_sent!
      
    rescue => error
      delivery.mark_as_failed!(error.message)
      Rails.logger.error "Notification email failed: #{error.message}"
      raise error
    end
  end
end
```

### 5. Create NotificationMailer
**File**: `app/mailers/notification_mailer.rb`

**Implementation Notes**:
```ruby
class NotificationMailer < ApplicationMailer
  def send_notification(recipient_email, subject, body, business)
    @body_content = body
    @business = business
    
    mail(
      to: recipient_email,
      subject: subject,
      from: business.email || default_params[:from]
    )
  end
end
```

### 6. Create NotificationTemplateService
**File**: `app/services/notification_template_service.rb`

**Implementation Notes**:
```ruby
class NotificationTemplateService
  def initialize(rule, source_object, recipient)
    @rule = rule
    @source_object = source_object
    @recipient = recipient
    @business = rule.business
  end
  
  def compile
    template = JSON.parse(@rule.email_template)
    
    {
      subject: compile_template(template['subject']),
      body: compile_template(template['body'])
    }
  end
  
  private
  
  def compile_template(template_string)
    variables = extract_template_variables
    
    compiled = template_string.dup
    variables.each do |variable, value|
      compiled.gsub!("{{#{variable}}}", value.to_s)
    end
    
    compiled
  end
  
  def extract_template_variables
    {
      'business_name' => @business.name,
      'business_phone' => @business.phone,
      'business_email' => @business.email,
      'client_name' => client_name,
      'recipient_name' => @recipient.name,
      'quote_id' => quote_id,
      'quote_amount' => quote_amount,
      'quote_url' => quote_url,
      'service_description' => service_description,
      'appointment_date' => appointment_date,
      'staff_name' => staff_name
    }
  end
  
  def client_name
    case @source_object
    when Quote then @source_object.client_name
    when Appointment then @source_object.client.name
    when Job then @source_object.client.name
    else @recipient.name
    end
  end
  
  def quote_id
    case @source_object
    when Quote then @source_object.id
    else 'N/A'
    end
  end
  
  def quote_amount
    case @source_object
    when Quote then "$#{@source_object.total_amount}"
    else 'N/A'
    end
  end
  
  def quote_url
    case @source_object
    when Quote then Rails.application.routes.url_helpers.quote_url(@source_object)
    else '#'
    end
  end
  
  def service_description
    case @source_object
    when Quote then @source_object.service_description
    when Job then @source_object.title
    else 'Service'
    end
  end
  
  def appointment_date
    case @source_object
    when Appointment then @source_object.scheduled_at.strftime('%B %d, %Y at %I:%M %p')
    when Job then @source_object.scheduled_date&.strftime('%B %d, %Y')
    else 'TBD'
    end
  end
  
  def staff_name
    case @source_object
    when Appointment then @source_object.assigned_staff&.name
    when Job then @source_object.assigned_staff&.name
    else 'Staff'
    end
  end
end
```

### 7. Create Database Migration
**File**: `db/migrate/xxx_create_notification_rules.rb`

**Implementation Notes**:
```ruby
class CreateNotificationRules < ActiveRecord::Migration[8.0]
  def change
    create_table :notification_rules do |t|
      t.references :business, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.integer :trigger_event, null: false
      t.integer :delivery_method, null: false
      t.integer :recipient_type, null: false
      t.text :email_template
      t.text :sms_template
      t.boolean :active, default: true
      
      t.timestamps
    end
    
    add_index :notification_rules, [:business_id, :trigger_event]
    add_index :notification_rules, [:business_id, :active]
    add_index :notification_rules, [:business_id, :name], unique: true
  end
end

class CreateNotificationDeliveries < ActiveRecord::Migration[8.0]
  def change
    create_table :notification_deliveries do |t|
      t.references :notification_rule, null: false, foreign_key: true
      t.references :recipient, polymorphic: true, null: false
      t.references :source, polymorphic: true, null: false
      t.integer :delivery_method, null: false
      t.integer :status, default: 0
      t.string :recipient_email, null: false
      t.string :recipient_phone
      t.datetime :sent_at
      t.datetime :delivered_at
      t.datetime :failed_at
      t.text :error_message
      
      t.timestamps
    end
    
    add_index :notification_deliveries, [:notification_rule_id, :status]
    add_index :notification_deliveries, [:recipient_type, :recipient_id]
    add_index :notification_deliveries, [:source_type, :source_id]
    add_index :notification_deliveries, :created_at
  end
end
```

## Acceptance Criteria
- Email notifications are sent automatically for configured events
- Template variables are properly substituted with actual data
- Delivery status is tracked and logged
- Failed deliveries are recorded with error messages
- Multiple recipient types are supported (client, staff, owner)
- Email templates can be customized per notification rule

## Estimate
- Story Points: 13
- Timeline: 1.5 weeks
- Dependencies: Business model, User model, mailer configuration
