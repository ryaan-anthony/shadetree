# Implementation Task: Booking Confirmation & Payment

## Overview
Create a comprehensive booking confirmation system that handles final validation, payment processing, and appointment finalization.

## Technical Design

### Models
```ruby
class BookingConfirmation < ApplicationRecord
  belongs_to :appointment
  belongs_to :payment, optional: true
  
  validates :confirmation_status, inclusion: { in: %w[pending processing confirmed failed cancelled] }
  
  # Store confirmation details
  store :confirmation_details, accessors: [
    :confirmation_code,
    :payment_required,
    :deposit_amount,
    :expiration_time
  ], coder: JSON
end

class BookingPayment < ApplicationRecord
  belongs_to :booking_confirmation
  belongs_to :payment_method, optional: true
  
  validates :payment_status, inclusion: { in: %w[pending authorized captured failed refunded] }
  
  # Store payment details
  store :payment_details, accessors: [
    :amount,
    :currency,
    :payment_type,
    :transaction_id
  ], coder: JSON
end

class ConfirmationRule < ApplicationRecord
  belongs_to :business
  belongs_to :service, optional: true
  
  validates :rule_type, inclusion: { in: %w[deposit_required approval_required payment_timing] }
  
  # Store rule configuration
  store :rule_config, accessors: [
    :conditions,
    :deposit_percentage,
    :approval_workflow,
    :payment_deadline
  ], coder: JSON
end
```

### Service Objects
```ruby
class BookingConfirmationService
  def self.confirm_booking(appointment, payment_info = nil)
    BookingConfirmation.transaction do
      # Validate final details
      # Process payment
      # Create confirmation
      # Send notifications
    end
  end
  
  def self.validate_confirmation(confirmation)
    # Check requirements
    # Verify payment
    # Apply rules
    # Return validation
  end
end

class PaymentProcessingService
  def self.process_payment(confirmation, payment_params)
    BookingPayment.transaction do
      # Validate amount
      # Process payment
      # Update confirmation
      # Handle result
    end
  end
  
  def self.handle_payment_failure(payment, error)
    # Log failure
    # Retry if appropriate
    # Update status
    # Notify parties
  end
end
```

### Background Jobs
```ruby
class ConfirmationTimeoutJob < ApplicationJob
  def perform(confirmation_id)
    # Check confirmation status
    # Handle timeouts
    # Release resources
    # Send notifications
  end
end

class PaymentReconciliationJob < ApplicationJob
  def perform(payment_id)
    # Verify payment status
    # Update booking
    # Handle discrepancies
    # Generate receipt
  end
end
```

## Confirmation Flow
```ruby
# app/controllers/booking_confirmations_controller.rb
class BookingConfirmationsController < ApplicationController
  def create
    @confirmation = BookingConfirmationService.confirm_booking(
      @appointment,
      payment_params
    )
    
    if @confirmation.successful?
      BookingNotificationJob.perform_later(@confirmation.id)
      render json: @confirmation, status: :created
    else
      render json: { errors: @confirmation.errors }, status: :unprocessable_entity
    end
  end
end
```

## Testing Strategy
1. Model Tests
   - Confirmation validation
   - Payment processing
   - Rule application
   - Status transitions

2. Service Tests
   - Booking confirmation
   - Payment handling
   - Rule enforcement
   - Error handling

3. Integration Tests
   - Complete confirmation flow
   - Payment processing
   - Notification triggers
   - Resource cleanup

## Security Considerations
- Payment security
- Confirmation validation
- PCI compliance
- Rate limiting
- Audit logging
- Data privacy

## Estimated Hours: 32

## Dependencies
- Booking Engine
- Payment Gateway Integration
