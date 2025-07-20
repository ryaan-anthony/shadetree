# Implementation Task: Provider Selection

## Overview
Create a system for managing provider selection during the booking process, including provider matching, preferences, and availability checking.

## Technical Design

### Models
```ruby
class ProviderSelection < ApplicationRecord
  belongs_to :service_selection
  belongs_to :provider, class_name: 'User', optional: true
  
  validates :selection_type, inclusion: { in: %w[specific_provider any_qualified auto_assign] }
  
  # Store selection preferences
  store :preferences, accessors: [
    :preferred_providers,
    :skill_requirements,
    :gender_preference,
    :language_requirements
  ], coder: JSON
end

class ProviderMatch < ApplicationRecord
  belongs_to :provider_selection
  belongs_to :provider, class_name: 'User'
  
  validates :match_status, inclusion: { in: %w[available tentative unavailable] }
  
  # Store match details
  store :match_details, accessors: [
    :match_score,
    :availability_windows,
    :constraints_met,
    :override_reasons
  ], coder: JSON
end

class ProviderPreference < ApplicationRecord
  belongs_to :customer
  belongs_to :provider, class_name: 'User'
  
  validates :preference_type, inclusion: { in: %w[preferred blocked favorite] }
  
  # Store preference details
  store :preference_details, accessors: [
    :reason,
    :service_types,
    :valid_until,
    :notes
  ], coder: JSON
end
```

### Service Objects
```ruby
class ProviderMatchingService
  def self.find_matches(selection, preferences)
    # Find qualified providers
    # Check availability
    # Apply preferences
    # Score matches
  end
  
  def self.validate_match(provider, selection)
    # Check qualifications
    # Verify availability
    # Apply constraints
    # Return validation
  end
end

class ProviderPreferenceService
  def self.apply_preferences(matches, customer)
    # Load preferences
    # Filter providers
    # Adjust scores
    # Sort results
  end
  
  def self.update_preferences(customer, provider, preference)
    # Save preference
    # Update matches
    # Handle conflicts
    # Send notifications
  end
end
```

### Background Jobs
```ruby
class ProviderMatchingJob < ApplicationJob
  def perform(selection_id)
    # Find matches
    # Update availability
    # Calculate scores
    # Cache results
  end
end

class PreferenceUpdateJob < ApplicationJob
  def perform(customer_id)
    # Update preferences
    # Recalculate matches
    # Update bookings
    # Send notifications
  end
end
```

## Provider Selection UI
```ruby
# app/components/provider_selector_component.rb
class ProviderSelectorComponent < ViewComponent::Base
  def initialize(service_selection:)
    @matches = load_provider_matches(service_selection)
    @preferences = load_customer_preferences(service_selection.customer)
    @availability = check_availability(@matches)
  end
  
  private
  
  def load_provider_matches(selection)
    ProviderMatchingService.find_matches(selection)
  end
end
```

## Testing Strategy
1. Model Tests
   - Selection validation
   - Match scoring
   - Preference handling
   - Status transitions

2. Service Tests
   - Provider matching
   - Availability checking
   - Preference application
   - Score calculation

3. Integration Tests
   - Complete selection flow
   - Preference system
   - UI functionality
   - Cache behavior

## Security Considerations
- Provider data privacy
- Preference validation
- Match authorization
- Rate limiting
- Audit logging
- Access control

## Estimated Hours: 24

## Dependencies
- Booking Engine
- Time Slot Selection
