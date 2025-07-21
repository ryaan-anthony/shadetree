# Feature: Booking Preferences

## Description
System configuration for booking rules, policies, and customer experience settings that control how the booking process works for the business, including advance booking times, cancellation policies, and customer requirements.

## User Stories
- As a business owner, I want to set minimum advance booking time so I have adequate preparation time
- As a business owner, I want to configure cancellation policies so customers understand the rules
- As a business owner, I want to require customer information so I can provide better service
- As a business owner, I want to set booking limits so I don't get overbooked

## Tasks

### Task 1: Create Booking Preferences Model
**Implementation Notes:**
- Create model to store various booking configuration settings
- Include validation for business rules and constraints
- Support flexible policy configurations

```ruby
# app/models/booking_preferences.rb
class BookingPreferences < ApplicationRecord
  belongs_to :business
  
  validates :min_advance_hours, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :max_advance_days, presence: true, numericality: { greater_than: 0 }
  validates :cancellation_hours, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :max_bookings_per_day, numericality: { greater_than: 0 }, allow_nil: true
  validates :booking_window_days, presence: true, numericality: { greater_than: 0 }
  
  enum cancellation_policy: {
    flexible: 0,
    moderate: 1,
    strict: 2,
    custom: 3
  }
  
  enum payment_policy: {
    payment_on_service: 0,
    payment_on_booking: 1,
    deposit_required: 2
  }
  
  def advance_booking_allowed?(requested_time)
    min_time = Time.current + min_advance_hours.hours
    max_time = Time.current + max_advance_days.days
    
    requested_time >= min_time && requested_time <= max_time
  end
  
  def cancellation_allowed?(booking_time)
    return true if cancellation_hours.zero?
    
    Time.current <= booking_time - cancellation_hours.hours
  end
  
  def cancellation_fee(booking_amount)
    return 0 unless has_cancellation_fee?
    
    case cancellation_fee_type
    when 'percentage'
      booking_amount * (cancellation_fee_percentage / 100.0)
    when 'flat_rate'
      cancellation_flat_fee
    else
      0
    end
  end
  
  def deposit_amount(total_amount)
    return 0 unless deposit_required?
    
    case deposit_type
    when 'percentage'
      total_amount * (deposit_percentage / 100.0)
    when 'flat_rate'
      deposit_flat_amount
    else
      0
    end
  end
  
  def booking_available_on_date?(date)
    return false if business_closed_dates.include?(date.to_s)
    return true if allowed_booking_days.empty?
    
    day_name = date.strftime('%A').downcase
    allowed_booking_days.include?(day_name)
  end
end

# Migration
# rails g model BookingPreferences business:references min_advance_hours:integer max_advance_days:integer cancellation_hours:integer cancellation_policy:integer payment_policy:integer
class CreateBookingPreferences < ActiveRecord::Migration[8.0]
  def change
    create_table :booking_preferences do |t|
      t.references :business, null: false, foreign_key: true
      
      # Advance booking settings
      t.integer :min_advance_hours, default: 24
      t.integer :max_advance_days, default: 90
      t.integer :booking_window_days, default: 30
      
      # Cancellation settings
      t.integer :cancellation_hours, default: 24
      t.integer :cancellation_policy, default: 0
      t.boolean :has_cancellation_fee, default: false
      t.string :cancellation_fee_type, default: 'percentage'
      t.decimal :cancellation_fee_percentage, precision: 5, scale: 2, default: 0
      t.decimal :cancellation_flat_fee, precision: 8, scale: 2, default: 0
      
      # Payment settings
      t.integer :payment_policy, default: 0
      t.string :deposit_type, default: 'percentage'
      t.decimal :deposit_percentage, precision: 5, scale: 2, default: 0
      t.decimal :deposit_flat_amount, precision: 8, scale: 2, default: 0
      
      # Booking limits
      t.integer :max_bookings_per_day
      t.integer :max_bookings_per_customer_per_day, default: 1
      t.boolean :allow_same_day_booking, default: true
      
      # Customer requirements
      t.boolean :require_phone_number, default: true
      t.boolean :require_email_confirmation, default: true
      t.boolean :require_customer_notes, default: false
      t.boolean :send_booking_reminders, default: true
      t.integer :reminder_hours_before, default: 24
      
      # Business rules
      t.text :allowed_booking_days # JSON array of allowed days
      t.text :business_closed_dates # JSON array of closed dates
      t.text :special_instructions
      t.text :terms_and_conditions
      
      t.timestamps
    end
    
    add_index :booking_preferences, :business_id, unique: true
  end
end
```

### Task 2: Create Booking Preferences Service
**Implementation Notes:**
- Service to handle booking validation and policy enforcement
- Centralized logic for booking rules and calculations
- Integration with booking creation process

```ruby
# app/services/admin/booking_preferences_service.rb
class Admin::BookingPreferencesService
  attr_reader :business, :preferences

  def initialize(business)
    @business = business
    @preferences = business.booking_preferences || build_default_preferences
  end

  def validate_booking_request(requested_time, customer, service = nil)
    errors = []
    
    # Check advance booking window
    unless preferences.advance_booking_allowed?(requested_time)
      min_time = Time.current + preferences.min_advance_hours.hours
      max_time = Time.current + preferences.max_advance_days.days
      errors << "Booking must be between #{min_time.strftime('%m/%d/%Y %I:%M %p')} and #{max_time.strftime('%m/%d/%Y')}"
    end
    
    # Check if date is available
    unless preferences.booking_available_on_date?(requested_time.to_date)
      errors << "Booking not available on #{requested_time.strftime('%A, %B %d, %Y')}"
    end
    
    # Check daily booking limits
    if preferences.max_bookings_per_day.present?
      daily_bookings = business.bookings.where(
        scheduled_at: requested_time.beginning_of_day..requested_time.end_of_day
      ).count
      
      if daily_bookings >= preferences.max_bookings_per_day
        errors << "Maximum bookings per day reached"
      end
    end
    
    # Check customer daily limits
    if customer && preferences.max_bookings_per_customer_per_day.present?
      customer_daily_bookings = business.bookings.where(
        customer: customer,
        scheduled_at: requested_time.beginning_of_day..requested_time.end_of_day
      ).count
      
      if customer_daily_bookings >= preferences.max_bookings_per_customer_per_day
        errors << "Maximum bookings per customer per day reached"
      end
    end
    
    # Check same-day booking policy
    if !preferences.allow_same_day_booking && requested_time.to_date == Date.current
      errors << "Same-day booking is not allowed"
    end
    
    {
      valid: errors.empty?,
      errors: errors
    }
  end

  def calculate_booking_costs(base_amount)
    costs = {
      base_amount: base_amount,
      deposit_amount: 0,
      total_due_now: 0,
      total_due_later: base_amount
    }
    
    case preferences.payment_policy
    when 'payment_on_booking'
      costs[:total_due_now] = base_amount
      costs[:total_due_later] = 0
    when 'deposit_required'
      deposit = preferences.deposit_amount(base_amount)
      costs[:deposit_amount] = deposit
      costs[:total_due_now] = deposit
      costs[:total_due_later] = base_amount - deposit
    end
    
    costs
  end

  def cancellation_details(booking)
    return { allowed: false, reason: 'Booking cannot be cancelled' } unless booking
    
    allowed = preferences.cancellation_allowed?(booking.scheduled_at)
    fee = allowed ? preferences.cancellation_fee(booking.total_amount) : 0
    refund_amount = booking.amount_paid - fee
    
    {
      allowed: allowed,
      fee: fee,
      refund_amount: [refund_amount, 0].max,
      deadline: booking.scheduled_at - preferences.cancellation_hours.hours,
      policy: preferences.cancellation_policy
    }
  end

  def booking_window_dates
    start_date = Date.current
    end_date = start_date + preferences.booking_window_days.days
    
    (start_date..end_date).select do |date|
      preferences.booking_available_on_date?(date)
    end
  end

  def customer_requirements
    {
      phone_required: preferences.require_phone_number,
      email_confirmation_required: preferences.require_email_confirmation,
      notes_required: preferences.require_customer_notes,
      terms_acceptance_required: preferences.terms_and_conditions.present?
    }
  end

  private

  def build_default_preferences
    business.build_booking_preferences(
      min_advance_hours: 24,
      max_advance_days: 90,
      cancellation_hours: 24,
      cancellation_policy: 'flexible',
      payment_policy: 'payment_on_service'
    )
  end
end
```

### Task 3: Create Booking Preferences Controller
**Implementation Notes:**
- Handle preferences configuration and updates
- Include validation preview functionality
- Support policy testing and simulation

```ruby
# app/controllers/admin/booking_preferences_controller.rb
class Admin::BookingPreferencesController < Admin::BaseController
  before_action :authenticate_admin!
  before_action :authorize_business_management!
  before_action :load_preferences

  def show
    @preferences_service = Admin::BookingPreferencesService.new(current_admin.business)
    @booking_window = @preferences_service.booking_window_dates.first(14)
    @customer_requirements = @preferences_service.customer_requirements
  end

  def edit
  end

  def update
    if @preferences.update(booking_preferences_params)
      track_preferences_update
      redirect_to admin_booking_preferences_path, notice: 'Booking preferences updated successfully'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def test_booking
    requested_time = Time.zone.parse(params[:test_datetime])
    customer = current_admin.business.customers.find_by(id: params[:customer_id]) if params[:customer_id].present?
    
    preferences_service = Admin::BookingPreferencesService.new(current_admin.business)
    result = preferences_service.validate_booking_request(requested_time, customer)
    
    if result[:valid]
      costs = preferences_service.calculate_booking_costs(params[:test_amount].to_f)
      render json: { valid: true, costs: costs }
    else
      render json: { valid: false, errors: result[:errors] }
    end
  end

  def preview_cancellation
    booking_amount = params[:booking_amount].to_f
    booking_time = Time.zone.parse(params[:booking_time])
    
    # Create a temporary booking object for testing
    test_booking = OpenStruct.new(
      total_amount: booking_amount,
      amount_paid: booking_amount,
      scheduled_at: booking_time
    )
    
    preferences_service = Admin::BookingPreferencesService.new(current_admin.business)
    details = preferences_service.cancellation_details(test_booking)
    
    render json: details
  end

  private

  def load_preferences
    @preferences = current_admin.business.booking_preferences || 
                  current_admin.business.build_booking_preferences
  end

  def booking_preferences_params
    params.require(:booking_preferences).permit(
      :min_advance_hours, :max_advance_days, :booking_window_days,
      :cancellation_hours, :cancellation_policy, :has_cancellation_fee,
      :cancellation_fee_type, :cancellation_fee_percentage, :cancellation_flat_fee,
      :payment_policy, :deposit_type, :deposit_percentage, :deposit_flat_amount,
      :max_bookings_per_day, :max_bookings_per_customer_per_day, :allow_same_day_booking,
      :require_phone_number, :require_email_confirmation, :require_customer_notes,
      :send_booking_reminders, :reminder_hours_before,
      :special_instructions, :terms_and_conditions,
      allowed_booking_days: [], business_closed_dates: []
    )
  end

  def track_preferences_update
    Admin::ActivityTrackingService.new(current_admin.business)
                                  .track_business_setting_changed(
                                    'booking_preferences',
                                    current_admin,
                                    @preferences.changes
                                  )
  end
end
```

### Task 4: Add Booking Preferences Routes
**Implementation Notes:**
- Add routes for preferences management and testing
- Include special endpoints for validation and preview

```ruby
# Add to config/routes.rb
namespace :admin do
  # ...existing routes...
  resource :booking_preferences, only: [:show, :edit, :update] do
    collection do
      post :test_booking
      post :preview_cancellation
    end
  end
end
```

### Task 5: Integration with Business Model
**Implementation Notes:**
- Add association to Business model
- Create default preferences on business creation

```ruby
# Add to app/models/business.rb
class Business < ApplicationRecord
  # ...existing associations...
  has_one :booking_preferences, dependent: :destroy
  
  after_create :create_default_booking_preferences
  
  private
  
  def create_default_booking_preferences
    create_booking_preferences!(
      min_advance_hours: 24,
      max_advance_days: 90,
      cancellation_hours: 24,
      cancellation_policy: 'flexible',
      payment_policy: 'payment_on_service'
    )
  end
end
```

## Acceptance Criteria
- [ ] Business owners can configure all booking rules and policies
- [ ] Advance booking windows are enforced correctly
- [ ] Cancellation policies calculate fees accurately
- [ ] Payment policies determine deposit requirements properly
- [ ] Booking limits prevent overbooking scenarios
- [ ] Test functionality validates policy configurations

## Testing Requirements
- Unit tests for BookingPreferences model validations
- Service tests for booking validation logic
- Integration tests for policy enforcement
- Cancellation fee calculation verification
- Booking window date filtering tests
