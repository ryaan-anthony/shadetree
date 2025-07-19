# Implementation Task: Customer Constraints

## Overview
Create a system for managing customer-specific booking constraints, including purchase history rules, loyalty tiers, and personalized restrictions.

## Technical Design

### Models
```ruby
class CustomerConstraint < ApplicationRecord
  belongs_to :business
  belongs_to :customer_group, optional: true
  belongs_to :customer, optional: true
  
  validates :constraint_type, inclusion: { in: %w[purchase_history loyalty_tier eligibility frequency customer_specific] }
  validates :status, inclusion: { in: %w[active inactive temporary] }
  
  # Store constraint configuration
  store :constraint_config, accessors: [
    :conditions,
    :restrictions,
    :exceptions,
    :validation_rules
  ], coder: JSON
end

class CustomerGroup < ApplicationRecord
  belongs_to :business
  has_many :customer_constraints
  has_many :group_memberships
  
  validates :group_type, inclusion: { in: %w[loyalty segment vip custom] }
  
  # Store group configuration
  store :group_config, accessors: [
    :membership_rules,
    :benefit_rules,
    :notification_settings
  ], coder: JSON
end

class GroupMembership < ApplicationRecord
  belongs_to :customer_group
  belongs_to :customer
  
  validates :status, inclusion: { in: %w[active pending expired revoked] }
  
  # Store membership details
  store :membership_details, accessors: [
    :join_date,
    :expiry_date,
    :benefits_used,
    :history
  ], coder: JSON
end
```

### Service Objects
```ruby
class CustomerConstraintService
  def self.validate_booking(customer, service, params)
    # Check customer constraints
    # Validate group rules
    # Apply restrictions
    # Return validation result
  end
  
  def self.check_eligibility(customer, service)
    # Check purchase history
    # Validate loyalty tier
    # Apply frequency rules
    # Return eligibility
  end
end

class CustomerGroupService
  def self.manage_membership(customer, group)
    GroupMembership.transaction do
      # Check eligibility
      # Process membership
      # Apply benefits
      # Send notifications
    end
  end
  
  def self.update_group_rules(group, rules)
    # Update configuration
    # Revalidate members
    # Handle changes
    # Send updates
  end
end
```

### Background Jobs
```ruby
class CustomerEligibilityJob < ApplicationJob
  def perform(customer_id)
    # Check constraints
    # Update eligibility
    # Process changes
    # Send notifications
  end
end

class GroupMembershipJob < ApplicationJob
  def perform(group_id)
    # Update memberships
    # Process expirations
    # Handle transitions
    # Send updates
  end
end
```

## Views
1. Customer Constraint Configuration
   - Rule builder
   - Group management
   - Exception handling
   - Benefit setup

2. Customer Group Management
   - Membership management
   - Rule configuration
   - Benefit tracking
   - Analytics view

## API Endpoints
```ruby
# GET /api/v1/customers/:id/constraints
{
  "service_id": "uuid",
  "include_groups": boolean
}

# POST /api/v1/customer_groups/:id/validate
{
  "customer_id": "uuid",
  "booking_params": {}
}
```

## Testing Strategy
1. Model Tests
   - Constraint validation
   - Group management
   - Membership handling
   - Rule enforcement

2. Service Tests
   - Eligibility checking
   - Group processing
   - Benefit handling
   - Rule application

3. Integration Tests
   - Complete constraint flow
   - Group management
   - API functionality
   - Notification system

## Security Considerations
- Customer data privacy
- Group access control
- Rule validation
- Rate limiting
- Audit logging
- Data protection

## Estimated Hours: 20

## Dependencies
- Time Constraints
- Capacity Constraints
