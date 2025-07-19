# Implementation Task: Account Status Management

## Overview
Create a system to manage business account status transitions, including trial periods, subscription status, and account suspensions.

## Technical Design

### Models
```ruby
class AccountStatus < ApplicationRecord
  belongs_to :business
  
  validates :status, inclusion: { in: %w[trial active suspended cancelled] }
  validates :trial_ends_at, presence: true, if: :trial?
  
  store :status_metadata, coder: JSON
  
  after_save :handle_status_change
end

class AccountStatusChange < ApplicationRecord
  belongs_to :business
  belongs_to :changed_by, class_name: 'User'
  
  validates :from_status, :to_status, presence: true
  validates :reason, presence: true, if: :requires_reason?
end
```

### State Machine
```ruby
class AccountStateMachine
  include Statesman::Machine
  
  state :trial, initial: true
  state :active
  state :suspended
  state :cancelled
  
  transition from: :trial, to: [:active, :cancelled]
  transition from: :active, to: [:suspended, :cancelled]
  transition from: :suspended, to: [:active, :cancelled]
  
  guard_transition(to: :active) do |account|
    account.valid_subscription?
  end
  
  after_transition do |account, transition|
    AccountStatusChangeJob.perform_later(account.id, transition.to_h)
  end
end
```

### Service Objects
```ruby
class AccountStatusService
  def self.change_status(business, new_status, changed_by, reason = nil)
    Business.transaction do
      # Validate status change
      # Record status change
      # Handle dependent systems
      # Notify relevant parties
    end
  end
  
  def self.handle_trial_expiration(business)
    # Check trial status
    # Handle grace period
    # Process transition
    # Send notifications
  end
end
```

### Controllers
```ruby
class Business::AccountStatusController < BusinessController
  def update
    result = AccountStatusService.change_status(
      @business,
      status_params[:status],
      current_user,
      status_params[:reason]
    )
    # Handle result
  end
  
  def show_status
    @status_history = @business.account_status_changes.includes(:changed_by)
  end
end
```

### Background Jobs
```ruby
class AccountStatusChangeJob < ApplicationJob
  def perform(business_id, transition_data)
    # Update dependent services
    # Send notifications
    # Update integrations
  end
end

class TrialExpirationCheckerJob < ApplicationJob
  def perform
    # Check for expiring trials
    # Handle grace periods
    # Process status changes
  end
end
```

## Views
1. Status Dashboard
   - Current status display
   - Trial period countdown
   - Status change history
   - Action buttons

2. Status Change Form
   - Status selection
   - Reason input
   - Confirmation dialog

## API Endpoints
```ruby
# PATCH /api/v1/business/account_status
{
  "status": "active|suspended|cancelled",
  "reason": "string",
  "metadata": {}
}

# GET /api/v1/business/account_status/history
```

## Testing Strategy
1. Model Tests
   - Status transitions
   - Validation rules
   - Callback behavior

2. Service Tests
   - Status changes
   - Trial handling
   - Notification sending

3. Integration Tests
   - Complete status workflow
   - Trial expiration process
   - API functionality

## Security Considerations
- Status change authorization
- Audit logging
- Status verification
- Rate limiting
- Data retention

## Estimated Hours: 20

## Dependencies
- Core Models implementation
- Subscription system
- Notification system
