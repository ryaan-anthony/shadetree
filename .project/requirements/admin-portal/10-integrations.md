# Epic: Integration Management

## Overview
Enable business owners to connect their Shadetree platform with popular third-party services including Stripe for payments, Google Calendar for scheduling, QuickBooks for accounting, and Zapier for workflow automation. Provide a centralized integration hub for managing all external connections.

## Goals
- Streamline business operations through seamless third-party integrations
- Reduce manual data entry and synchronization tasks
- Enable professional payment processing capabilities
- Support accounting workflow automation
- Provide extensible integration framework for future services

## Success Metrics
- Integration setup completion time < 15 minutes per service
- Integration adoption rate > 60% of businesses
- Data synchronization accuracy > 98%
- Integration uptime > 99.5%
- Error resolution time < 24 hours

## User Stories
- As a business owner, I want to connect Stripe so I can accept credit card payments
- As a business owner, I want Google Calendar sync so appointments appear in my calendar
- As an accountant, I want QuickBooks integration so invoices sync automatically
- As a business owner, I want Zapier connections so I can automate workflows with other tools
- As a staff member, I want calendar integration so I can see my schedule across platforms

## Features

### Growth Phase (P2 - Advanced Features)
1. [Payment Integration (Stripe)](integrations/01-stripe-integration.md) - Credit card processing and payment management
2. [Calendar Integration (Google)](integrations/02-calendar-integration.md) - Two-way calendar synchronization
3. [Accounting Integration (QuickBooks)](integrations/03-accounting-integration.md) - Invoice and financial data sync
4. [Automation Platform (Zapier)](integrations/04-zapier-integration.md) - Workflow automation connections

## Technical Architecture

### Core Models
```ruby
# Integration configuration
class Integration < ApplicationRecord
  belongs_to :business
  belongs_to :configured_by, class_name: 'User'
  
  validates :provider, :status, presence: true
  validates :provider, uniqueness: { scope: :business_id }
  
  enum provider: {
    stripe: 0,
    google_calendar: 1,
    quickbooks: 2,
    zapier: 3,
    mailchimp: 4,
    twilio: 5
  }
  
  enum status: { disconnected: 0, connected: 1, error: 2, syncing: 3 }
  
  # Encrypted credentials and configuration
  encrypts :credentials
  encrypts :configuration
  
  scope :active, -> { where(status: 'connected') }
  scope :by_provider, ->(provider) { where(provider: provider) }
end

# Integration sync tracking
class IntegrationSync < ApplicationRecord
  belongs_to :integration
  belongs_to :source, polymorphic: true # Quote, Appointment, etc.
  
  validates :sync_type, :status, presence: true
  
  enum sync_type: { push: 0, pull: 1, bidirectional: 2 }
  enum status: { pending: 0, syncing: 1, completed: 2, failed: 3 }
  
  scope :recent, -> { where(created_at: 24.hours.ago..) }
  scope :failed, -> { where(status: 'failed') }
end
```

### Integration Service Framework
```ruby
class IntegrationService
  def self.for_provider(provider)
    case provider
    when 'stripe'
      StripeIntegrationService
    when 'google_calendar'
      GoogleCalendarService
    when 'quickbooks'
      QuickBooksService
    when 'zapier'
      ZapierService
    else
      raise "Unknown provider: #{provider}"
    end
  end
  
  def initialize(integration)
    @integration = integration
    @business = integration.business
    @credentials = integration.credentials
  end
  
  # Override in subclasses
  def connect
    raise NotImplementedError
  end
  
  def disconnect
    @integration.update!(status: :disconnected)
  end
  
  def sync_data(source_object, action)
    raise NotImplementedError
  end
  
  def test_connection
    raise NotImplementedError
  end
end
```

### Stripe Integration Service
```ruby
class StripeIntegrationService < IntegrationService
  def connect
    # Stripe Connect OAuth flow
    client_id = Rails.application.credentials.stripe[:client_id]
    
    {
      oauth_url: "https://connect.stripe.com/oauth/authorize?" +
        "response_type=code&client_id=#{client_id}&scope=read_write&" +
        "state=#{@business.id}&redirect_uri=#{callback_url}"
    }
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
      @integration.update!(
        credentials: {
          access_token: response['access_token'],
          refresh_token: response['refresh_token'],
          stripe_user_id: response['stripe_user_id']
        },
        status: :connected
      )
    else
      @integration.update!(status: :error, error_message: response['error_description'])
    end
  end
  
  def create_payment_intent(quote)
    Stripe::PaymentIntent.create(
      {
        amount: (quote.total_amount * 100).to_i, # Convert to cents
        currency: 'usd',
        metadata: {
          quote_id: quote.id,
          business_id: @business.id
        }
      },
      { stripe_account: @credentials['stripe_user_id'] }
    )
  end
  
  def sync_data(quote, action)
    case action
    when 'payment_received'
      sync_payment_to_quote(quote)
    when 'refund_processed'
      sync_refund_to_quote(quote)
    end
  end
  
  def test_connection
    Stripe::Account.retrieve(@credentials['stripe_user_id'])
    true
  rescue Stripe::StripeError => e
    false
  end
end
```

### Google Calendar Integration Service
```ruby
class GoogleCalendarService < IntegrationService
  def connect
    # Google OAuth2 flow
    client = Google::Apis::CalendarV3::CalendarService.new
    
    {
      oauth_url: google_auth_client.authorization_uri.to_s
    }
  end
  
  def complete_oauth(auth_code)
    auth_client = google_auth_client
    auth_client.code = auth_code
    auth_client.fetch_access_token!
    
    @integration.update!(
      credentials: {
        access_token: auth_client.access_token,
        refresh_token: auth_client.refresh_token,
        expires_at: Time.at(auth_client.expires_at)
      },
      status: :connected
    )
  end
  
  def sync_appointment(appointment, action)
    calendar_service = Google::Apis::CalendarV3::CalendarService.new
    calendar_service.authorization = google_auth_client
    
    case action
    when 'created'
      create_calendar_event(appointment)
    when 'updated'
      update_calendar_event(appointment)
    when 'cancelled'
      delete_calendar_event(appointment)
    end
  end
  
  private
  
  def create_calendar_event(appointment)
    event = Google::Apis::CalendarV3::Event.new(
      summary: "#{@business.name} - #{appointment.service_name}",
      description: "Appointment with #{appointment.client_name}",
      start: {
        date_time: appointment.start_time.iso8601,
        time_zone: @business.timezone
      },
      end: {
        date_time: appointment.end_time.iso8601,
        time_zone: @business.timezone
      },
      attendees: [
        { email: appointment.client_email },
        { email: appointment.staff_member.email }
      ]
    )
    
    result = calendar_service.insert_event('primary', event)
    appointment.update!(google_event_id: result.id)
  end
  
  def google_auth_client
    Google::Auth::UserRefreshCredentials.new(
      client_id: Rails.application.credentials.google[:client_id],
      client_secret: Rails.application.credentials.google[:client_secret],
      scope: ['https://www.googleapis.com/auth/calendar'],
      redirect_uri: callback_url
    )
  end
end
```

### Integration Controller
```ruby
class Admin::IntegrationsController < Admin::BaseController
  def index
    @integrations = current_business.integrations.includes(:configured_by)
    @available_providers = available_providers_for_business
  end
  
  def connect
    provider = params[:provider]
    integration = find_or_create_integration(provider)
    service = IntegrationService.for_provider(provider).new(integration)
    
    result = service.connect
    
    if result[:oauth_url]
      redirect_to result[:oauth_url]
    else
      redirect_to admin_integrations_path, notice: "#{provider.humanize} connected successfully"
    end
  end
  
  def callback
    provider = params[:provider]
    integration = current_business.integrations.find_by!(provider: provider)
    service = IntegrationService.for_provider(provider).new(integration)
    
    if params[:code]
      service.complete_oauth(params[:code])
      redirect_to admin_integrations_path, notice: "#{provider.humanize} connected successfully"
    else
      redirect_to admin_integrations_path, alert: "Failed to connect #{provider.humanize}"
    end
  end
  
  def disconnect
    integration = current_business.integrations.find(params[:id])
    service = IntegrationService.for_provider(integration.provider).new(integration)
    service.disconnect
    
    redirect_to admin_integrations_path, notice: "#{integration.provider.humanize} disconnected"
  end
  
  def test
    integration = current_business.integrations.find(params[:id])
    service = IntegrationService.for_provider(integration.provider).new(integration)
    
    if service.test_connection
      render json: { status: 'success', message: 'Connection test successful' }
    else
      render json: { status: 'error', message: 'Connection test failed' }
    end
  end
  
  private
  
  def find_or_create_integration(provider)
    current_business.integrations.find_or_create_by!(provider: provider) do |integration|
      integration.configured_by = current_user
      integration.status = :disconnected
    end
  end
  
  def available_providers_for_business
    %w[stripe google_calendar quickbooks zapier]
  end
end
```

## Integration Points
- Quote Management (payment processing integration)
- Appointment Scheduling (calendar synchronization)
- Invoice Generation (accounting software sync)
- Notification System (communication platform integrations)
- Workflow Builder (automation platform connections)

## Security Considerations
- Encrypt all integration credentials using Rails encrypted attributes
- Implement secure OAuth flows for third-party authentication
- Validate webhook signatures from integrated services
- Audit integration configuration changes
- Implement rate limiting for API calls to prevent quota exhaustion

## Growth Phase Scope (P2 Priority)
**Included in Growth Phase:**
- 4 core integrations (Stripe, Google Calendar, QuickBooks, Zapier)
- OAuth-based authentication for secure connections
- Basic data synchronization capabilities
- Integration health monitoring and error handling

**Future Enhancements:**
- Additional payment processors (Square, PayPal)
- CRM integrations (HubSpot, Salesforce)
- Communication platforms (Slack, Microsoft Teams)
- Marketing automation tools (Mailchimp, Constant Contact)

## Technical Implementation Notes
```ruby
# Background job for integration syncing
class IntegrationSyncJob < ApplicationJob
  queue_as :integrations
  
  def perform(integration_id, source_id, source_type, action)
    integration = Integration.find(integration_id)
    source = source_type.constantize.find(source_id)
    
    sync_record = IntegrationSync.create!(
      integration: integration,
      source: source,
      sync_type: :push,
      status: :syncing
    )
    
    begin
      service = IntegrationService.for_provider(integration.provider).new(integration)
      service.sync_data(source, action)
      
      sync_record.update!(status: :completed)
    rescue => e
      sync_record.update!(status: :failed, error_message: e.message)
      Rails.logger.error "Integration sync failed: #{e.message}"
    end
  end
end

# Usage in other services
class QuoteService
  def accept_quote(quote)
    quote.update!(status: :accepted)
    
    # Trigger integrations
    quote.business.integrations.active.each do |integration|
      IntegrationSyncJob.perform_later(
        integration.id,
        quote.id,
        'Quote',
        'accepted'
      )
    end
  end
end
```

## Webhook Handling
```ruby
# Controller for handling webhooks from integrated services
class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :verify_webhook_signature
  
  def stripe
    event = Stripe::Event.construct_from(JSON.parse(request.body.read))
    
    case event.type
    when 'payment_intent.succeeded'
      handle_stripe_payment_success(event.data.object)
    when 'payment_intent.payment_failed'
      handle_stripe_payment_failure(event.data.object)
    end
    
    head :ok
  end
  
  private
  
  def handle_stripe_payment_success(payment_intent)
    quote_id = payment_intent.metadata.quote_id
    quote = Quote.find(quote_id)
    
    quote.update!(
      payment_status: :paid,
      payment_date: Time.current,
      stripe_payment_intent_id: payment_intent.id
    )
    
    # Trigger notifications
    NotificationService.trigger('payment_received', quote, quote.business)
  end
  
  def verify_webhook_signature
    # Implement webhook signature verification for each provider
  end
end
```

## Dependencies
- OAuth2 authentication libraries
- Third-party service SDKs (Stripe, Google APIs, QuickBooks SDK)
- Background Job Processing (Sidekiq)
- Webhook handling infrastructure

## Estimate
- All Features: 25 story points (3 weeks)
- Note: This is a Growth Phase epic, not included in MVP
