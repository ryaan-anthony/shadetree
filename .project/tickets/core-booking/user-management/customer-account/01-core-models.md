# Implementation Task: Core Customer Models

## Overview
Create the foundational customer models that handle customer profiles, preferences, and service history.

## Technical Design

### Models
```ruby
class Customer < User
  has_one :customer_profile
  has_many :service_preferences
  has_many :appointments
  has_many :quotes
  has_many :payment_methods
  
  # Use single table inheritance from User model
  validates :type, inclusion: { in: ['Customer'] }
  
  scope :active, -> { where(status: 'active') }
  scope :with_appointments, -> { joins(:appointments).distinct }
end

class CustomerProfile < ApplicationRecord
  belongs_to :customer
  
  store :contact_preferences, accessors: [
    :preferred_contact_method,
    :appointment_reminders,
    :marketing_notifications
  ], coder: JSON
  
  store :preferences, accessors: [
    :preferred_providers,
    :service_notes,
    :special_requirements
  ], coder: JSON
  
  validates :first_name, :last_name, presence: true
  validates :phone, phone_number: true, allow_blank: true
  validates :preferred_contact_method, inclusion: { 
    in: %w[email sms both none],
    allow_nil: true
  }
end

class ServicePreference < ApplicationRecord
  belongs_to :customer
  belongs_to :service
  
  store :preferences, coder: JSON
  validates :preference_type, inclusion: { in: %w[favorite blocked preferred] }
end
```

### Service Objects
```ruby
class CustomerProfileService
  def self.create_profile(user_params, profile_params)
    Customer.transaction do
      # Create customer user
      # Create customer profile
      # Set default preferences
      # Send welcome email
    end
  end
  
  def self.update_preferences(customer, preferences)
    # Update contact preferences
    # Update service preferences
    # Trigger relevant notifications
  end
end
```

### Database Migrations
```ruby
class CreateCustomerProfiles < ActiveRecord::Migration[7.1]
  def change
    create_table :customer_profiles do |t|
      t.references :customer, null: false, foreign_key: { to_table: :users }
      t.string :first_name
      t.string :last_name
      t.string :phone
      t.jsonb :contact_preferences, default: {}
      t.jsonb :preferences, default: {}
      t.timestamps
    end
    
    create_table :service_preferences do |t|
      t.references :customer, null: false
      t.references :service, null: false
      t.string :preference_type
      t.jsonb :preferences, default: {}
      t.timestamps
      t.index [:customer_id, :service_id], unique: true
    end
  end
end
```

## Testing Strategy
1. Model Tests
   - STI functionality from User model
   - Profile validations
   - Preference storage
   - Relationship integrity

2. Service Tests
   - Profile creation workflow
   - Preference updates
   - Email triggers

3. Integration Tests
   - Full customer creation flow
   - Preference management
   - Data consistency

## Security Considerations
- Personal data encryption
- GDPR compliance
- Phone number validation
- Preference data validation
- Audit logging for changes

## Estimated Hours: 12

## Dependencies
- Core User model from Business Account
- Database encryption setup
- Email service configuration
