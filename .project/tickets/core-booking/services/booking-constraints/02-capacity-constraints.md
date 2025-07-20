# Implementation Task: Capacity Constraints

## Overview
Create a system for managing booking capacity limits, including concurrent appointments, resource utilization, and staff availability constraints.

## Technical Design

### Models
```ruby
class CapacityConstraint < ApplicationRecord
  belongs_to :business
  belongs_to :service, optional: true
  belongs_to :resource_type, optional: true
  
  validates :constraint_type, inclusion: { in: %w[concurrent total daily resource_based staff_based] }
  validates :status, inclusion: { in: %w[active inactive override] }
  
  # Store capacity configuration
  store :capacity_config, accessors: [
    :max_concurrent,
    :max_daily,
    :max_weekly,
    :resource_limits
  ], coder: JSON
end

class CapacityAllocation < ApplicationRecord
  belongs_to :capacity_constraint
  belongs_to :appointment, optional: true
  belongs_to :resource, optional: true
  
  validates :allocation_type, inclusion: { in: %w[reserved confirmed tentative blocked] }
  
  # Store allocation details
  store :allocation_details, accessors: [
    :quantity_used,
    :time_period,
    :priority_level,
    :expiration
  ], coder: JSON
end

class CapacityOverride < ApplicationRecord
  belongs_to :capacity_constraint
  belongs_to :authorized_by, class_name: 'User'
  
  validates :override_type, inclusion: { in: %w[increase decrease temporary special] }
  
  # Store override configuration
  store :override_config, accessors: [
    :reason,
    :adjustment,
    :valid_period,
    :conditions
  ], coder: JSON
end
```

### Service Objects
```ruby
class CapacityService
  def self.check_capacity(service, datetime)
    # Check concurrent limits
    # Validate resources
    # Check staff capacity
    # Return availability
  end
  
  def self.allocate_capacity(appointment)
    CapacityAllocation.transaction do
      # Reserve capacity
      # Allocate resources
      # Update availability
      # Handle conflicts
    end
  end
end

class CapacityPlanningService
  def self.forecast_capacity(service, date_range)
    # Analyze bookings
    # Calculate utilization
    # Project availability
    # Return forecast
  end
  
  def self.optimize_capacity(service)
    # Analyze usage patterns
    # Calculate optimal limits
    # Generate recommendations
    # Return optimization plan
  end
end
```

### Background Jobs
```ruby
class CapacityCalculationJob < ApplicationJob
  def perform(service_id, date_range)
    # Calculate capacity
    # Update availability
    # Handle conflicts
    # Send notifications
  end
end

class CapacityOptimizationJob < ApplicationJob
  def perform(business_id)
    # Analyze capacity usage
    # Generate recommendations
    # Update configurations
    # Send reports
  end
end
```

## Views
1. Capacity Configuration
   - Limit settings
   - Resource allocation
   - Override management
   - Forecast view

2. Capacity Dashboard
   - Current utilization
   - Upcoming allocations
   - Bottleneck analysis
   - Optimization suggestions

## API Endpoints
```ruby
# GET /api/v1/services/:id/capacity
{
  "datetime": "string",
  "include_forecast": boolean
}

# POST /api/v1/appointments/:id/allocate_capacity
{
  "resources": [{
    "resource_type_id": "uuid",
    "quantity": number
  }]
}
```

## Testing Strategy
1. Model Tests
   - Constraint validation
   - Allocation handling
   - Override management
   - Capacity calculation

2. Service Tests
   - Capacity checking
   - Allocation process
   - Forecast generation
   - Optimization logic

3. Integration Tests
   - Complete capacity flow
   - Resource integration
   - API functionality
   - Conflict handling

## Security Considerations
- Capacity validation
- Override authorization
- Resource access control
- Rate limiting
- Audit logging
- Data integrity

## Estimated Hours: 20

## Dependencies
- Time Constraints
- Resource Management System
