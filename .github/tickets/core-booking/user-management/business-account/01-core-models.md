# Implementation Task: Core User and Business Models

## Overview
Create the foundational User and Business models with proper relationships and authentication support.

## Technical Design

### Models to Create

1. User Model (`app/models/user.rb`)
```ruby
class User < ApplicationRecord
  belongs_to :business, optional: true
  has_one :profile
  has_many :roles
  has_many :permissions, through: :roles
  
  # Authentication & Security
  has_secure_password
  has_secure_token :auth_token
  
  # Validations
  validates :email, presence: true, uniqueness: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
end
```

2. Business Model (`app/models/business.rb`)
```ruby
class Business < ApplicationRecord
  has_many :users
  has_many :business_hours
  has_many :services
  has_many :locations
  
  # Validations
  validates :name, presence: true
  validates :time_zone, presence: true
end
```

3. Profile Model (`app/models/profile.rb`)
```ruby
class Profile < ApplicationRecord
  belongs_to :user
  
  # Add fields for:
  # - Name
  # - Phone
  # - Preferences
  # - Notifications settings
end
```

### Database Migrations
```ruby
# Users table
create_table :users do |t|
  t.string :email, null: false
  t.string :password_digest
  t.string :auth_token
  t.references :business
  t.timestamps
end

# Businesses table
create_table :businesses do |t|
  t.string :name, null: false
  t.string :time_zone, null: false
  t.string :status
  t.jsonb :settings
  t.timestamps
end

# Profiles table
create_table :profiles do |t|
  t.references :user
  t.string :first_name
  t.string :last_name
  t.string :phone
  t.jsonb :preferences
  t.timestamps
end
```

### Key Methods to Implement
```ruby
def self.create_business_account(params)
def add_staff_member(user)
def update_business_settings(settings)
```

## Testing Strategy
1. Unit Tests
   - Model validations
   - Relationship integrity
   - Authentication methods

2. Integration Tests
   - Account creation flow
   - Staff addition process
   - Settings management

## Security Considerations
- Password hashing (bcrypt)
- Auth token management
- Business data isolation
- GDPR compliance for user data

## Estimated Hours: 8

## Dependencies
- None (foundational models)

## Notes
- Use UUIDs for IDs
- Add DB indexes for common queries
- Set up model callbacks for logging
- Implement soft delete
