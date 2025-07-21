# Feature: Payment Integration (Stripe)

## Overview
Integrate Stripe payment processing to enable businesses to accept credit card payments for quotes and invoices, with secure payment handling and automated status updates.

## User Stories
- As a business owner, I want to accept credit card payments so I can get paid faster
- As a customer, I want to pay invoices online with my credit card
- As a business owner, I want payment status to update automatically when customers pay

## Tasks

### 1. Create StripeIntegration Model
**File**: `app/models/stripe_integration.rb`

**Implementation Notes**:
```ruby
class StripeIntegration < ApplicationRecord
  belongs_to :business
  belongs_to :configured_by, class_name: 'User'
  
  validates :status, presence: true
  
  enum status: { disconnected: 0, connected: 1, error: 2 }
  
  # Encrypted credentials storage
  encrypts :stripe_account_id
  encrypts :access_token
  encrypts :refresh_token
  
  scope :active, -> { where(status: 'connected') }
  
  def test_connection
    return false unless connected?
    
    begin
      Stripe::Account.retrieve(stripe_account_id, stripe_account: stripe_account_id)
      true
    rescue Stripe::StripeError
      false
    end
  end
  
  def create_payment_intent(amount_cents, metadata = {})
    Stripe::PaymentIntent.create(
      {
        amount: amount_cents,
        currency: 'usd',
        metadata: metadata,
        automatic_payment_methods: { enabled: true }
      },
      { stripe_account: stripe_account_id }
    )
  end
end
```

### 2. Create StripeIntegrationService
**File**: `app/services/stripe_integration_service.rb`

**Implementation Notes**:
```ruby
class StripeIntegrationService
  def initialize(business)
    @business = business
    @integration = business.stripe_integration
  end
  
  def connect_account
    # Stripe Connect OAuth URL
    client_id = Rails.application.credentials.stripe[:client_id]
    redirect_uri = Rails.application.routes.url_helpers.stripe_callback_url
    
    "https://connect.stripe.com/oauth/authorize?" +
    "response_type=code&client_id=#{client_id}&scope=read_write&" +
    "state=#{@business.id}&redirect_uri=#{redirect_uri}"
  end
  
  def complete_oauth(auth_code)
    response = HTTParty.post('https://connect.stripe.com/oauth/token', {
      body: {
        client_secret: Rails.application.credentials.stripe[:client_secret],
        code: auth_code,
        grant_type: 'authorization_code'
      }
    })
    
    if response.success?
      if @integration
        @integration.update!(
          stripe_account_id: response['stripe_user_id'],
          access_token: response['access_token'],
          refresh_token: response['refresh_token'],
          status: :connected
        )
      else
        @business.create_stripe_integration!(
          stripe_account_id: response['stripe_user_id'],
          access_token: response['access_token'],
          refresh_token: response['refresh_token'],
          status: :connected,
          configured_by: @business.owner
        )
      end
      
      true
    else
      Rails.logger.error "Stripe OAuth failed: #{response['error_description']}"
      false
    end
  end
  
  def create_payment_for_quote(quote)
    return nil unless @integration&.connected?
    
    amount_cents = (quote.total_amount * 100).to_i
    
    payment_intent = @integration.create_payment_intent(
      amount_cents,
      {
        quote_id: quote.id,
        business_id: @business.id,
        client_email: quote.client.email
      }
    )
    
    # Store payment intent for tracking
    quote.update!(
      stripe_payment_intent_id: payment_intent.id,
      payment_url: generate_payment_url(payment_intent)
    )
    
    payment_intent
  end
  
  def handle_payment_success(payment_intent_id)
    payment_intent = Stripe::PaymentIntent.retrieve(payment_intent_id)
    quote_id = payment_intent.metadata['quote_id']
    
    quote = @business.quotes.find(quote_id)
    quote.update!(
      payment_status: 'paid',
      payment_received_at: Time.current,
      payment_method: 'stripe'
    )
    
    # Trigger notifications
    NotificationService.trigger('payment_received', quote, @business)
    
    quote
  end
  
  private
  
  def generate_payment_url(payment_intent)
    Rails.application.routes.url_helpers.payment_url(
      payment_intent_id: payment_intent.id
    )
  end
end
```

### 3. Create StripeController
**File**: `app/controllers/admin/stripe_controller.rb`

**Implementation Notes**:
```ruby
class Admin::StripeController < Admin::BaseController
  before_action :ensure_can_manage_integrations
  
  def show
    @integration = current_business.stripe_integration
    @connection_status = @integration&.test_connection || false
  end
  
  def connect
    service = StripeIntegrationService.new(current_business)
    oauth_url = service.connect_account
    
    redirect_to oauth_url, allow_other_host: true
  end
  
  def callback
    auth_code = params[:code]
    business_id = params[:state]
    
    unless business_id == current_business.id.to_s
      redirect_to admin_integrations_path, alert: 'Invalid state parameter'
      return
    end
    
    service = StripeIntegrationService.new(current_business)
    
    if service.complete_oauth(auth_code)
      redirect_to admin_stripe_path, notice: 'Stripe connected successfully'
    else
      redirect_to admin_integrations_path, alert: 'Failed to connect Stripe'
    end
  end
  
  def disconnect
    integration = current_business.stripe_integration
    integration&.update!(status: :disconnected)
    
    redirect_to admin_integrations_path, notice: 'Stripe disconnected'
  end
  
  def test_connection
    integration = current_business.stripe_integration
    
    if integration&.test_connection
      render json: { status: 'success', message: 'Connection successful' }
    else
      render json: { status: 'error', message: 'Connection failed' }
    end
  end
  
  private
  
  def ensure_can_manage_integrations
    unless current_business_user.can_manage_services?
      redirect_to admin_dashboard_path, alert: 'Access denied'
    end
  end
end
```

### 4. Create Webhook Handler
**File**: `app/controllers/webhooks/stripe_controller.rb`

**Implementation Notes**:
```ruby
class Webhooks::StripeController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :verify_stripe_signature
  
  def handle
    event = Stripe::Event.construct_from(JSON.parse(request.body.read))
    
    case event.type
    when 'payment_intent.succeeded'
      handle_payment_success(event.data.object)
    when 'payment_intent.payment_failed'
      handle_payment_failure(event.data.object)
    when 'account.updated'
      handle_account_update(event.data.object)
    end
    
    head :ok
  end
  
  private
  
  def handle_payment_success(payment_intent)
    business_id = payment_intent.metadata['business_id']
    business = Business.find(business_id)
    
    service = StripeIntegrationService.new(business)
    service.handle_payment_success(payment_intent.id)
  end
  
  def handle_payment_failure(payment_intent)
    business_id = payment_intent.metadata['business_id']
    quote_id = payment_intent.metadata['quote_id']
    
    business = Business.find(business_id)
    quote = business.quotes.find(quote_id)
    
    quote.update!(payment_status: 'failed')
    
    # Notify business owner of failed payment
    NotificationService.trigger('payment_failed', quote, business)
  end
  
  def verify_stripe_signature
    payload = request.body.read
    sig_header = request.env['HTTP_STRIPE_SIGNATURE']
    endpoint_secret = Rails.application.credentials.stripe[:webhook_secret]
    
    begin
      Stripe::Webhook.construct_event(payload, sig_header, endpoint_secret)
    rescue JSON::ParserError, Stripe::SignatureVerificationError => e
      Rails.logger.error "Stripe webhook verification failed: #{e.message}"
      head :bad_request
    end
  end
end
```

### 5. Create Database Migration
**File**: `db/migrate/xxx_create_stripe_integrations.rb`

**Implementation Notes**:
```ruby
class CreateStripeIntegrations < ActiveRecord::Migration[8.0]
  def change
    create_table :stripe_integrations do |t|
      t.references :business, null: false, foreign_key: true
      t.references :configured_by, null: false, foreign_key: { to_table: :users }
      t.string :stripe_account_id
      t.string :access_token
      t.string :refresh_token
      t.integer :status, default: 0
      t.datetime :connected_at
      t.text :error_message
      
      t.timestamps
    end
    
    add_index :stripe_integrations, :business_id, unique: true
    add_index :stripe_integrations, :stripe_account_id
  end
end

# Add payment fields to quotes table
class AddPaymentFieldsToQuotes < ActiveRecord::Migration[8.0]
  def change
    add_column :quotes, :stripe_payment_intent_id, :string
    add_column :quotes, :payment_url, :string
    add_column :quotes, :payment_status, :integer, default: 0
    add_column :quotes, :payment_received_at, :datetime
    add_column :quotes, :payment_method, :string
    
    add_index :quotes, :stripe_payment_intent_id
    add_index :quotes, :payment_status
  end
end
```

## Acceptance Criteria
- Businesses can connect their Stripe accounts via OAuth
- Payment intents are created for quotes with correct amounts
- Webhook handling updates payment status automatically
- Failed payments are logged and notifications sent
- Connection status can be tested and verified
- Payment URLs are generated for customer checkout

## Estimate
- Story Points: 13
- Timeline: 1.5 weeks
- Dependencies: Stripe API credentials, webhook endpoint setup, SSL certificate
