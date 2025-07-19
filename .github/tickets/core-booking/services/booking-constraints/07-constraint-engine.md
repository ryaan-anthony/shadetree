# Implementation Task: Constraint Engine

## Overview
Create the core constraint engine that powers all booking constraint evaluations, providing a unified system for constraint definition, evaluation, and enforcement.

## Technical Design

### Models
```ruby
class ConstraintEngine < ApplicationRecord
  belongs_to :business
  
  validates :engine_mode, inclusion: { in: %w[strict flexible learning] }
  
  # Store engine configuration
  store :engine_config, accessors: [
    :evaluation_strategy,
    :caching_rules,
    :optimization_settings,
    :learning_parameters
  ], coder: JSON
end

class ConstraintDefinition < ApplicationRecord
  belongs_to :constraint_engine
  belongs_to :constrainable, polymorphic: true
  
  validates :definition_type, inclusion: { in: %w[rule formula predicate custom] }
  
  # Store constraint definition
  store :constraint_definition, accessors: [
    :expression,
    :parameters,
    :dependencies,
    :metadata
  ], coder: JSON
end

class ConstraintEvaluation < ApplicationRecord
  belongs_to :constraint_engine
  belongs_to :constraint_definition
  
  validates :evaluation_type, inclusion: { in: %w[validation prediction optimization] }
  
  # Store evaluation results
  store :evaluation_results, accessors: [
    :outcome,
    :factor_values,
    :confidence_score,
    :explanation
  ], coder: JSON
end
```

### Service Objects
```ruby
class ConstraintEngineService
  def self.evaluate_constraints(context, params)
    # Load applicable constraints
    # Evaluate expressions
    # Apply optimization
    # Return results
  end
  
  def self.optimize_evaluation(constraints, context)
    # Analyze dependencies
    # Order evaluations
    # Cache results
    # Return optimal plan
  end
end

class ConstraintDefinitionService
  def self.register_constraint(engine, definition)
    ConstraintDefinition.transaction do
      # Validate definition
      # Register constraint
      # Update dependencies
      # Initialize cache
    end
  end
  
  def self.compile_expression(definition)
    # Parse expression
    # Validate syntax
    # Optimize logic
    # Return compiled form
  end
end
```

### Background Jobs
```ruby
class ConstraintOptimizationJob < ApplicationJob
  def perform(engine_id)
    # Analyze patterns
    # Update strategies
    # Optimize cache
    # Generate report
  end
end

class ConstraintLearningJob < ApplicationJob
  def perform(engine_id)
    # Process evaluations
    # Update parameters
    # Improve accuracy
    # Generate insights
  end
end
```

## Constraint DSL
```ruby
ConstraintDSL.define do
  constraint :time_slot_available do |slot, context|
    # Time-based evaluation
    all_of do
      during_business_hours(slot)
      not_in_blackout_period(slot)
      has_available_capacity(slot)
    end
  end
  
  constraint :valid_location do |location, context|
    # Location-based evaluation
    any_of do
      in_service_area(location)
      special_coverage_approved(location)
    end
  end
end
```

## Testing Strategy
1. Model Tests
   - Engine configuration
   - Constraint definitions
   - Evaluation logic
   - Caching behavior

2. Service Tests
   - Constraint evaluation
   - Expression compilation
   - Optimization logic
   - Learning system

3. Integration Tests
   - Complete evaluation flow
   - Multiple constraint types
   - Performance testing
   - Cache effectiveness

## Security Considerations
- Expression validation
- Input sanitization
- Resource limits
- Cache security
- Audit logging
- Access control

## Estimated Hours: 32

## Dependencies
- None (Core Component)
