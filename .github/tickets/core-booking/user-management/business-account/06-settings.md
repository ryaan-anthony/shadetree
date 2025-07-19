# Implementation Task: Settings and Preferences

## Overview
Create a flexible settings management system that handles business preferences, notifications, and customization options.

## Technical Design

### Models
```ruby
class BusinessSettings < ApplicationRecord
  belongs_to :business
  
  # Core settings groups
  store :notification_settings, coder: JSON
  store :booking_preferences, coder: JSON
  store :display_preferences, coder: JSON
  store :integration_settings, coder: JSON
  
  after_save :invalidate_settings_cache
end

class FeatureFlag < ApplicationRecord
  belongs_to :business
  
  validates :key, presence: true
  validates :enabled, inclusion: { in: [true, false] }
  
  scope :enabled, -> { where(enabled: true) }
end
```

### Service Objects
```ruby
class SettingsManagerService
  def self.update_settings(business, category, params)
    BusinessSettings.transaction do
      # Validate settings schema
      # Update settings
      # Handle dependent changes
      # Clear relevant caches
    end
  end
  
  def self.toggle_feature(business, feature_key, enabled)
    # Toggle feature flag
    # Handle feature-specific logic
    # Update related services
  end
end
```

### Settings Schema
```ruby
SETTINGS_SCHEMA = {
  notification_settings: {
    email_notifications: :boolean,
    sms_notifications: :boolean,
    notification_preferences: :hash
  },
  booking_preferences: {
    allow_online_booking: :boolean,
    require_deposit: :boolean,
    cancellation_policy: :string,
    buffer_time: :integer
  },
  display_preferences: {
    date_format: :string,
    time_format: :string,
    currency: :string,
    language: :string
  },
  integration_settings: {
    calendar_sync: :boolean,
    payment_gateway: :string,
    crm_integration: :boolean
  }
}
```

### Controllers
```ruby
class Business::SettingsController < BusinessController
  def show
    @settings = @business.settings.with_schema
  end
  
  def update
    result = SettingsManagerService.update_settings(
      @business,
      params[:category],
      settings_params
    )
    # Handle result
  end
end
```

### Background Jobs
```ruby
class SettingsChangeNotifierJob < ApplicationJob
  def perform(business_id, changes)
    # Notify affected services
    # Update dependent systems
    # Send admin notification
  end
end
```

## Views
1. Settings Dashboard
   - Category navigation
   - Settings forms
   - Feature toggles

2. Quick Settings
   - Common settings widget
   - Recent changes
   - Quick toggles

## API Endpoints
```ruby
# PATCH /api/v1/business/settings/:category
{
  "settings": {
    "notification_settings": {
      "email_notifications": true,
      "sms_notifications": false
    }
  }
}
```

## Testing Strategy
1. Model Tests
   - Settings validation
   - Schema enforcement
   - Cache invalidation

2. Service Tests
   - Settings updates
   - Feature toggles
   - Dependency handling

3. Integration Tests
   - Settings workflow
   - API functionality
   - Cache behavior

## Security Considerations
- Settings validation
- Feature flag access control
- Audit logging
- Rate limiting
- Settings backup

## Estimated Hours: 16

## Dependencies
- Core Models implementation
- Cache system configuration
- Feature flag system
