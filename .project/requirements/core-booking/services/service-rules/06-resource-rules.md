# Implementation Task: Resource Rules

## Overview
Create a system for managing service resource requirements, allocation rules, and capacity management.

## Technical Design

### Models
```ruby
class ResourceRule < ServiceRule
  # Inherits from ServiceRule
  validates :rule_type, inclusion: { in: ['resource'] }
  
  # Store resource configuration
  store :resource_config, accessors: [
    :allocation_strategy,
    :capacity_rules,
    :sharing_rules,
    :reservation_policy
  ], coder: JSON
end

class ServiceResource < ApplicationRecord
  belongs_to :service
  belongs_to :resource_type
  has_many :resource_allocations
  
  validates :requirement_type, inclusion: { in: %w[required optional backup shared] }
  validates :quantity_required, numericality: { greater_than: 0 }
  
  # Store resource requirements
  store :resource_requirements, accessors: [
    :setup_time,
    :cleanup_time,
    :sharing_constraints,
    :alternatives
  ], coder: JSON
end

class ResourceAllocation < ApplicationRecord
  belongs_to :service_resource
  belongs_to :resource
  belongs_to :appointment, optional: true
  
  validates :status, inclusion: { in: %w[reserved allocated in_use released] }
  
  # Store allocation details
  store :allocation_details, accessors: [
    :setup_start,
    :usage_start,
    :usage_end,
    :cleanup_end
  ], coder: JSON
end
```

### Service Objects
```ruby
class ResourceRuleService
  def self.check_availability(service, datetime)
    # Check resource requirements
    # Validate availability
    # Calculate capacity
    # Return allocation options
  end
  
  def self.allocate_resources(service, appointment)
    # Reserve resources
    # Schedule setup/cleanup
    # Handle conflicts
    # Create allocations
  end
end

class ResourceCapacityService
  def self.calculate_capacity(resource_type, date_range)
    # Check allocations
    # Consider maintenance
    # Apply sharing rules
    # Return capacity
  end
  
  def self.optimize_allocations(resource_type, date_range)
    # Analyze usage patterns
    # Optimize assignments
    # Handle conflicts
    # Update schedules
  end
end
```

### Background Jobs
```ruby
class ResourceAllocationJob < ApplicationJob
  def perform(appointment_id)
    # Allocate resources
    # Update schedules
    # Send notifications
    # Handle conflicts
  end
end

class ResourceOptimizationJob < ApplicationJob
  def perform(resource_type_id, date_range)
    # Analyze allocations
    # Optimize usage
    # Update schedules
    # Generate report
  end
end
```

## Views
1. Resource Rules
   - Resource requirements
   - Allocation rules
   - Capacity settings
   - Sharing policies

2. Resource Management
   - Allocation calendar
   - Usage tracking
   - Maintenance schedule
   - Conflict resolution

## API Endpoints
```ruby
# GET /api/v1/services/:id/resource_requirements
{
  "datetime": "string",
  "include_availability": boolean
}

# POST /api/v1/appointments/:id/allocate_resources
{
  "resources": [{
    "resource_type_id": "uuid",
    "quantity": number
  }]
}
```

## Testing Strategy
1. Model Tests
   - Resource validation
   - Allocation handling
   - Capacity tracking
   - Rule enforcement

2. Service Tests
   - Availability checking
   - Resource allocation
   - Capacity calculation
   - Optimization logic

3. Integration Tests
   - Complete allocation flow
   - Conflict handling
   - API functionality
   - Notification system

## Security Considerations
- Resource access control
- Allocation validation
- Capacity verification
- Rate limiting
- Audit logging
- Data integrity

## Estimated Hours: 20

## Dependencies
- Rules Engine
- Resource Management System
