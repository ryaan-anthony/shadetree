# Implementation Task: Service Assignment Rules

## Overview
Create a rule-based system for managing how services are assigned to providers based on skills, availability, preferences, and business rules.

## Technical Design

### Models
```ruby
class AssignmentRule < ApplicationRecord
  belongs_to :business
  belongs_to :service, optional: true
  
  validates :rule_type, inclusion: { in: %w[auto_assign load_balance preference round_robin manual] }
  validates :priority, presence: true, numericality: { only_integer: true }
  
  # Store rule configuration
  store :rule_config, accessors: [
    :conditions,
    :provider_filters,
    :fallback_rules,
    :notification_settings
  ], coder: JSON
end

class ProviderPreference < ApplicationRecord
  belongs_to :user
  belongs_to :service
  
  validates :preference_type, inclusion: { in: %w[preferred neutral avoided blocked] }
  validates :priority, numericality: { only_integer: true }
  
  # Store preference details
  store :preference_details, accessors: [
    :reason,
    :time_restrictions,
    :location_preferences
  ], coder: JSON
end

class AssignmentOverride < ApplicationRecord
  belongs_to :service
  belongs_to :assigned_by, class_name: 'User'
  belongs_to :provider, class_name: 'User'
  
  validates :override_type, inclusion: { in: %w[manual temporary emergency] }
  
  # Store override details
  store :override_details, coder: JSON
end
```

### Service Objects
```ruby
class AssignmentRuleService
  def self.find_provider(service, datetime, context)
    # Apply assignment rules
    # Check provider availability
    # Consider preferences
    # Handle overrides
  end
  
  def self.validate_assignment(service, provider, datetime)
    # Check provider skills
    # Validate availability
    # Apply business rules
    # Return validation result
  end
end

class WorkloadBalancingService
  def self.calculate_workload(provider, date_range)
    # Calculate assigned hours
    # Check capacity limits
    # Consider skill levels
    # Return workload metrics
  end
  
  def self.optimize_assignments(providers, assignments)
    # Balance workload
    # Consider preferences
    # Minimize conflicts
    # Return optimized plan
  end
end
```

### Background Jobs
```ruby
class AssignmentOptimizationJob < ApplicationJob
  def perform(business_id, date_range)
    # Optimize assignments
    # Update schedules
    # Send notifications
    # Generate report
  end
end

class WorkloadAnalysisJob < ApplicationJob
  def perform(provider_ids)
    # Analyze workload
    # Generate metrics
    # Update dashboards
    # Send alerts
  end
end
```

## Views
1. Assignment Rules
   - Rule configuration
   - Provider filters
   - Override management
   - Workload visualization

2. Provider Preferences
   - Service preferences
   - Time preferences
   - Location preferences
   - Override requests

## API Endpoints
```ruby
# POST /api/v1/services/:id/assign
{
  "datetime": "string",
  "provider_id": "uuid",
  "override_params": {}
}

# GET /api/v1/providers/:id/workload
{
  "date_range": {},
  "include_metrics": boolean
}
```

## Testing Strategy
1. Model Tests
   - Rule validation
   - Preference handling
   - Override management
   - Workload calculation

2. Service Tests
   - Provider assignment
   - Rule processing
   - Workload balancing
   - Override handling

3. Integration Tests
   - Complete assignment flow
   - Workload optimization
   - API functionality
   - Notification system

## Security Considerations
- Assignment authorization
- Override validation
- Workload limits
- Rate limiting
- Audit logging
- Access control

## Estimated Hours: 20

## Dependencies
- Skill Management
- Scheduling System
