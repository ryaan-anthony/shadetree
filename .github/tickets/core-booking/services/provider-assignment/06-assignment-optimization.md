# Implementation Task: Assignment Optimization

## Overview
Create an intelligent assignment optimization system that balances workload, preferences, and efficiency across providers.

## Technical Design

### Models
```ruby
class AssignmentOptimizer < ApplicationRecord
  belongs_to :business
  
  # Store optimization configuration
  store :optimizer_config, accessors: [
    :balancing_strategy,
    :preference_weight,
    :efficiency_weight,
    :distance_weight
  ], coder: JSON
  
  validates :optimization_strategy, inclusion: { in: %w[balanced efficient fair preference_based] }
end

class OptimizationRun < ApplicationRecord
  belongs_to :assignment_optimizer
  has_many :optimization_changes
  
  validates :status, inclusion: { in: %w[running completed failed cancelled] }
  
  # Store run details
  store :run_details, accessors: [
    :start_params,
    :improvements,
    :metrics,
    :duration
  ], coder: JSON
end

class OptimizationChange < ApplicationRecord
  belongs_to :optimization_run
  belongs_to :appointment
  belongs_to :original_provider, class_name: 'User'
  belongs_to :new_provider, class_name: 'User'
  
  validates :change_type, inclusion: { in: %w[reassignment swap split merge] }
  
  # Store change details
  store :change_details, accessors: [
    :reason,
    :impact_score,
    :affected_metrics
  ], coder: JSON
end
```

### Service Objects
```ruby
class AssignmentOptimizerService
  def self.optimize_assignments(business, params)
    OptimizationRun.transaction do
      # Initialize optimization
      # Calculate current metrics
      # Generate improvements
      # Apply changes
    end
  end
  
  def self.calculate_impact(changes)
    # Analyze changes
    # Calculate metrics
    # Evaluate improvement
    # Return impact
  end
end

class AssignmentBalancerService
  def self.balance_workload(providers, date_range)
    # Calculate current load
    # Find imbalances
    # Generate transfers
    # Return plan
  end
  
  def self.evaluate_fairness(assignments)
    # Calculate distribution
    # Check preferences
    # Measure satisfaction
    # Return metrics
  end
end
```

### Background Jobs
```ruby
class OptimizationJob < ApplicationJob
  def perform(optimization_run_id)
    # Run optimization
    # Apply changes
    # Calculate results
    # Send notifications
  end
end

class MetricsCalculationJob < ApplicationJob
  def perform(business_id)
    # Calculate metrics
    # Update dashboards
    # Generate alerts
    # Store history
  end
end
```

## Views
1. Optimization Dashboard
   - Current metrics
   - Improvement suggestions
   - Change preview
   - Impact analysis

2. Configuration Interface
   - Strategy setup
   - Weight configuration
   - Rule management
   - Schedule settings

## API Endpoints
```ruby
# POST /api/v1/assignments/optimize
{
  "date_range": {},
  "strategy": "string",
  "constraints": {},
  "preview_only": boolean
}

# GET /api/v1/optimization/metrics
{
  "date_range": {},
  "provider_ids": ["uuid"],
  "include_history": boolean
}
```

## Testing Strategy
1. Model Tests
   - Optimization logic
   - Change tracking
   - Metric calculations
   - Strategy validation

2. Service Tests
   - Optimization process
   - Balance calculations
   - Impact analysis
   - Change application

3. Integration Tests
   - Complete optimization flow
   - Metric tracking
   - API functionality
   - Notification system

## Security Considerations
- Change authorization
- Metric access control
- Strategy validation
- Rate limiting
- Audit logging
- Data privacy

## Estimated Hours: 24

## Dependencies
- Workload Management
- Performance Tracking
