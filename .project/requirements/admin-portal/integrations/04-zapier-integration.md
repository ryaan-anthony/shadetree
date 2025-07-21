# Feature: Automation Platform (Zapier)

## Overview
Integrate Shadetree with Zapier to enable businesses to connect their platform with 3,000+ third-party applications without custom development. This integration allows businesses to automate workflows between Shadetree and their other business tools.

## Goals
- Enable workflow automation without requiring technical expertise
- Connect Shadetree data with thousands of external applications
- Reduce manual data entry and process management
- Provide businesses with flexibility to create custom automation workflows

## User Stories
- As a business owner, I want to connect my Shadetree account to Zapier so I can automate workflows
- As a marketer, I want new customers in Shadetree to automatically be added to my email marketing platform
- As an administrator, I want new bookings to trigger notifications in my team chat application
- As a business owner, I want customer feedback to be logged in my CRM system automatically
- As a staff member, I want completed service information to update project management tools

## Tasks

### Task 1: Create Zapier Authentication System
**Description:** Implement API key generation and management for secure Zapier connections.

**Implementation Notes:**
- Create API key management for Zapier integration
- Implement authentication middleware for Zapier requests
- Build secure token validation system

```ruby
# app/models/api_key.rb
class ApiKey < ApplicationRecord
  belongs_to :business
  belongs_to :created_by, class_name: 'User'
  
  has_secure_token :access_token, length: 36
  
  validates :name, presence: true
  
  enum status: { active: 0, revoked: 1 }
  enum access_level: { read_only: 0, read_write: 1, admin: 2 }
  
  scope :for_zapier, -> { where(integration_type: 'zapier') }
  
  def revoke!
    update(status: :revoked, revoked_at: Time.current)
  end
end
```

```ruby
# app/controllers/admin/integrations/zapier_controller.rb
class Admin::Integrations::ZapierController < Admin::IntegrationsController
  before_action :require_admin
  before_action :set_integration, only: [:show, :destroy]
  
  def new
    @integration = current_business.integrations.new(provider: :zapier)
  end
  
  def create
    @integration = current_business.integrations.new(
      provider: :zapier,
      configured_by: current_user,
      status: :connected
    )
    
    if @integration.save
      # Create API key for Zapier
      @api_key = current_business.api_keys.create!(
        name: "Zapier Integration",
        created_by: current_user,
        integration_type: 'zapier',
        access_level: :read_write,
        status: :active
      )
      
      flash[:success] = "Zapier integration enabled successfully"
      redirect_to admin_integrations_zapier_path(@integration)
    else
      flash[:error] = "Failed to enable Zapier integration"
      render :new
    end
  end
  
  def show
    @api_keys = current_business.api_keys.for_zapier.order(created_at: :desc)
  end
  
  def destroy
    # Revoke all Zapier API keys
    current_business.api_keys.for_zapier.active.each(&:revoke!)
    
    @integration.destroy
    flash[:success] = "Zapier integration disabled and all API keys revoked"
    redirect_to admin_integrations_path
  end
  
  private
  
  def set_integration
    @integration = current_business.integrations.find_by!(provider: :zapier)
  end
end
```

```ruby
# app/controllers/api/v1/auth_controller.rb
module Api
  module V1
    class AuthController < Api::BaseController
      skip_before_action :authenticate_api_request
      
      def verify
        token = request.headers['X-API-Key'] || params[:api_key]
        api_key = ApiKey.find_by(access_token: token)
        
        if api_key&.active?
          render json: {
            authenticated: true,
            business: {
              id: api_key.business_id,
              name: api_key.business.name
            },
            access_level: api_key.access_level
          }
        else
          render json: { authenticated: false }, status: :unauthorized
        end
      end
    end
  end
end
```

### Task 2: Design Zapier App Definition
**Description:** Create the Zapier app definition with triggers and actions for the Zapier platform.

**Implementation Notes:**
- Define triggers for new customers, bookings, and payments
- Create actions for customer, service, and appointment creation
- Build search operations for lookups

```javascript
// zapier-app/index.js
const authentication = require('./authentication');
const customerTrigger = require('./triggers/customer');
const bookingTrigger = require('./triggers/booking');
const paymentTrigger = require('./triggers/payment');
const createCustomerAction = require('./actions/create_customer');
const createAppointmentAction = require('./actions/create_appointment');

module.exports = {
  version: '1.0.0',
  platformVersion: '10.0.0',
  authentication: authentication,
  
  // Before a user can connect to your app, Zapier needs to know what triggers and actions are available
  triggers: {
    [customerTrigger.key]: customerTrigger,
    [bookingTrigger.key]: bookingTrigger,
    [paymentTrigger.key]: paymentTrigger,
  },
  
  // Actions allow users to create data in your app
  actions: {
    [createCustomerAction.key]: createCustomerAction,
    [createAppointmentAction.key]: createAppointmentAction,
  },
  
  // Searches allow users to find records in your app
  searches: {
    // Define search operations here
  },
};
```

```javascript
// zapier-app/authentication.js
module.exports = {
  type: 'custom',
  
  test: {
    url: '{{bundle.authData.api_url}}/api/v1/auth/verify',
    method: 'GET',
    headers: {
      'X-API-Key': '{{bundle.authData.api_key}}',
    },
    body: {},
    removeMissingValuesFrom: {},
  },
  
  fields: [
    {
      key: 'api_url',
      label: 'API URL',
      required: true,
      helpText: 'Your Shadetree API URL (e.g., https://yourbusiness.shadetree.io)',
    },
    {
      key: 'api_key',
      label: 'API Key',
      required: true,
      helpText: 'Find your API key in Shadetree under Admin → Integrations → Zapier',
    },
  ],

  connectionLabel: '{{bundle.inputData.businessName}}',
};
```

### Task 3: Implement Zapier API Endpoints
**Description:** Develop the API endpoints necessary for Zapier to interact with Shadetree data.

**Implementation Notes:**
- Implement REST endpoints for triggers and actions
- Ensure proper rate limiting and security
- Add pagination for large data sets

```ruby
# app/controllers/api/v1/zapier_controller.rb
module Api
  module V1
    class ZapierController < Api::BaseController
      before_action :validate_zapier_integration
      
      def triggers
        case params[:trigger_type]
        when 'new_customer'
          customers = current_business.customers.order(created_at: :desc).limit(25)
          render json: customers, each_serializer: Api::V1::CustomerSerializer
        when 'new_booking'
          bookings = current_business.bookings.order(created_at: :desc).limit(25)
          render json: bookings, each_serializer: Api::V1::BookingSerializer
        when 'new_payment'
          payments = current_business.payments.order(created_at: :desc).limit(25)
          render json: payments, each_serializer: Api::V1::PaymentSerializer
        else
          render json: { error: "Unknown trigger type" }, status: :bad_request
        end
      end
      
      def webhook_subscribe
        webhook = current_business.webhooks.new(webhook_params)
        
        if webhook.save
          render json: { id: webhook.id, status: 'active' }, status: :created
        else
          render json: { errors: webhook.errors.full_messages }, status: :unprocessable_entity
        end
      end
      
      def webhook_unsubscribe
        webhook = current_business.webhooks.find_by(id: params[:id])
        
        if webhook&.destroy
          render json: { status: 'unsubscribed' }
        else
          render json: { error: "Webhook not found" }, status: :not_found
        end
      end
      
      private
      
      def validate_zapier_integration
        unless current_business.integrations.exists?(provider: :zapier, status: :connected)
          render json: { error: "Zapier integration is not enabled" }, status: :forbidden
        end
      end
      
      def webhook_params
        params.require(:webhook).permit(:event_type, :target_url, :description)
      end
    end
  end
end
```

```ruby
# app/models/webhook.rb
class Webhook < ApplicationRecord
  belongs_to :business
  
  validates :event_type, :target_url, presence: true
  validates :target_url, url: true
  
  enum event_type: {
    customer_created: 0,
    customer_updated: 1,
    booking_created: 2,
    booking_updated: 3,
    booking_canceled: 4,
    payment_created: 5,
    service_completed: 6
  }
  
  scope :for_event, ->(event_type) { where(event_type: event_type) }
end
```

### Task 4: Create Webhook Delivery System
**Description:** Build a reliable webhook delivery system to push events to Zapier.

**Implementation Notes:**
- Implement webhook event generation from model callbacks
- Create background jobs for webhook delivery
- Add retry logic for failed webhook deliveries
- Implement webhook logging and monitoring

```ruby
# app/services/webhook_service.rb
class WebhookService
  def self.trigger(business, event_type, payload)
    business.webhooks.for_event(event_type).find_each do |webhook|
      DeliverWebhookJob.perform_later(webhook.id, payload)
    end
  end
end
```

```ruby
# app/jobs/deliver_webhook_job.rb
class DeliverWebhookJob < ApplicationJob
  queue_as :webhooks
  
  # Retry with exponential backoff
  retry_on Net::OpenTimeout, Net::ReadTimeout, Timeout::Error,
           wait: :exponentially_longer, attempts: 5
  
  # Retry with fixed delay for HTTP failures
  retry_on HTTP::ConnectionError, wait: 30.seconds, attempts: 3
  
  def perform(webhook_id, payload)
    webhook = Webhook.find_by(id: webhook_id)
    return unless webhook
    
    delivery = WebhookDelivery.create!(
      webhook: webhook,
      payload: payload,
      status: :processing
    )
    
    begin
      response = HTTP.timeout(15)
                     .headers('Content-Type' => 'application/json')
                     .post(webhook.target_url, json: payload)
      
      delivery.update!(
        status: response.status.success? ? :delivered : :failed,
        response_code: response.code,
        response_body: response.body.to_s,
        delivered_at: Time.current
      )
      
      unless response.status.success?
        raise "Webhook delivery failed with status #{response.code}"
      end
    rescue => e
      delivery.update!(
        status: :failed,
        response_body: e.message,
        error: "#{e.class}: #{e.message}"
      )
      raise
    end
  end
end
```

```ruby
# app/models/webhook_delivery.rb
class WebhookDelivery < ApplicationRecord
  belongs_to :webhook
  
  enum status: { processing: 0, delivered: 1, failed: 2 }
  
  scope :recent, -> { where(created_at: 24.hours.ago..) }
end
```

```ruby
# app/models/concerns/webhookable.rb
module Webhookable
  extend ActiveSupport::Concern
  
  included do
    after_create :trigger_created_webhook
    after_update :trigger_updated_webhook
    after_destroy :trigger_destroyed_webhook
  end
  
  def trigger_created_webhook
    return unless business&.webhooks&.exists?
    
    event_type = "#{self.class.name.underscore}_created"
    return unless Webhook.event_types.key?(event_type)
    
    payload = webhook_payload.merge(
      event_type: event_type,
      created_at: Time.current
    )
    
    WebhookService.trigger(business, event_type, payload)
  end
  
  def trigger_updated_webhook
    return unless business&.webhooks&.exists?
    
    event_type = "#{self.class.name.underscore}_updated"
    return unless Webhook.event_types.key?(event_type)
    
    payload = webhook_payload.merge(
      event_type: event_type,
      updated_at: Time.current,
      changes: previous_changes.except(:updated_at)
    )
    
    WebhookService.trigger(business, event_type, payload)
  end
  
  def trigger_destroyed_webhook
    return unless business&.webhooks&.exists?
    
    event_type = "#{self.class.name.underscore}_destroyed"
    return unless Webhook.event_types.key?(event_type)
    
    payload = {
      id: id,
      event_type: event_type,
      deleted_at: Time.current
    }
    
    WebhookService.trigger(business, event_type, payload)
  end
  
  # Override in models to customize webhook payload
  def webhook_payload
    as_json
  end
end
```

### Task 5: Create Integration Documentation
**Description:** Develop comprehensive documentation for the Zapier integration.

**Implementation Notes:**
- Create a step-by-step setup guide
- Document available triggers and actions
- Provide example Zaps for common workflows
- Include troubleshooting information

```ruby
# app/controllers/admin/integrations/zapier_docs_controller.rb
class Admin::Integrations::ZapierDocsController < Admin::IntegrationsController
  before_action :require_admin
  
  def index
    @integration = current_business.integrations.find_by(provider: :zapier)
  end
end
```

```erb
<!-- app/views/admin/integrations/zapier_docs/index.html.erb -->
<div class="container mx-auto px-4 py-8">
  <h1 class="text-2xl font-bold mb-6">Zapier Integration Guide</h1>
  
  <div class="bg-white shadow rounded-lg mb-6">
    <div class="p-4 border-b border-gray-200">
      <h2 class="text-lg font-semibold">Getting Started</h2>
    </div>
    <div class="p-4">
      <ol class="list-decimal ml-5 space-y-2">
        <li>Go to your <a href="https://zapier.com/app/dashboard" class="text-blue-600 hover:underline" target="_blank">Zapier dashboard</a></li>
        <li>Click the "Make a Zap" button to create a new automation</li>
        <li>Search for "Shadetree" in the app selection</li>
        <li>Connect your Shadetree account using your API key</li>
        <li>Configure your trigger or action as needed</li>
      </ol>
      
      <div class="mt-4 p-4 bg-yellow-50 border-l-4 border-yellow-400">
        <h3 class="text-sm font-medium text-yellow-800">Your API Key</h3>
        <% if @integration&.connected? %>
          <p class="mt-1 text-yellow-700">Find your API key in the <a href="<%= admin_integrations_zapier_path %>" class="underline">Zapier Integration Settings</a>.</p>
        <% else %>
          <p class="mt-1 text-yellow-700">You need to enable the Zapier integration first.</p>
        <% end %>
      </div>
    </div>
  </div>
  
  <div class="bg-white shadow rounded-lg mb-6">
    <div class="p-4 border-b border-gray-200">
      <h2 class="text-lg font-semibold">Available Triggers</h2>
    </div>
    <div class="p-4">
      <div class="space-y-4">
        <div>
          <h3 class="font-medium">New Customer</h3>
          <p class="text-gray-600 mt-1">Triggers when a new customer is added to your Shadetree account.</p>
        </div>
        
        <div>
          <h3 class="font-medium">New Booking</h3>
          <p class="text-gray-600 mt-1">Triggers when a new appointment or booking is created.</p>
        </div>
        
        <div>
          <h3 class="font-medium">New Payment</h3>
          <p class="text-gray-600 mt-1">Triggers when a new payment is recorded in your system.</p>
        </div>
      </div>
    </div>
  </div>
  
  <div class="bg-white shadow rounded-lg mb-6">
    <div class="p-4 border-b border-gray-200">
      <h2 class="text-lg font-semibold">Available Actions</h2>
    </div>
    <div class="p-4">
      <div class="space-y-4">
        <div>
          <h3 class="font-medium">Create Customer</h3>
          <p class="text-gray-600 mt-1">Creates a new customer in your Shadetree account.</p>
        </div>
        
        <div>
          <h3 class="font-medium">Create Appointment</h3>
          <p class="text-gray-600 mt-1">Books a new appointment in your calendar.</p>
        </div>
      </div>
    </div>
  </div>
  
  <div class="bg-white shadow rounded-lg">
    <div class="p-4 border-b border-gray-200">
      <h2 class="text-lg font-semibold">Example Zaps</h2>
    </div>
    <div class="p-4">
      <div class="space-y-6">
        <div>
          <h3 class="font-medium">Add new customers to your email marketing platform</h3>
          <p class="text-gray-600 mt-1">When a new customer is created in Shadetree, automatically add them to your email list.</p>
          <div class="flex items-center mt-2">
            <span class="px-3 py-1 bg-gray-100 rounded-l-md border border-gray-300">Trigger</span>
            <span class="px-3 py-1 border-t border-b border-gray-300">New Customer in Shadetree</span>
            <span class="px-3 py-1 bg-gray-100 rounded-r-md border border-gray-300">Action</span>
            <span class="px-3 py-1 border-t border-r border-b border-gray-300">Add Subscriber in Mailchimp</span>
          </div>
        </div>
        
        <div>
          <h3 class="font-medium">Notify team of new bookings</h3>
          <p class="text-gray-600 mt-1">Send a message to your team chat when a new booking is created.</p>
          <div class="flex items-center mt-2">
            <span class="px-3 py-1 bg-gray-100 rounded-l-md border border-gray-300">Trigger</span>
            <span class="px-3 py-1 border-t border-b border-gray-300">New Booking in Shadetree</span>
            <span class="px-3 py-1 bg-gray-100 rounded-r-md border border-gray-300">Action</span>
            <span class="px-3 py-1 border-t border-r border-b border-gray-300">Send Channel Message in Slack</span>
          </div>
        </div>
        
        <div>
          <h3 class="font-medium">Log completed appointments in project management tool</h3>
          <p class="text-gray-600 mt-1">When a service is marked as completed, create a task in your project management system.</p>
          <div class="flex items-center mt-2">
            <span class="px-3 py-1 bg-gray-100 rounded-l-md border border-gray-300">Trigger</span>
            <span class="px-3 py-1 border-t border-b border-gray-300">Service Completed in Shadetree</span>
            <span class="px-3 py-1 bg-gray-100 rounded-r-md border border-gray-300">Action</span>
            <span class="px-3 py-1 border-t border-r border-b border-gray-300">Create Task in Asana</span>
          </div>
        </div>
      </div>
    </div>
  </div>
</div>
```

## Security Considerations
- API keys are generated with secure entropy
- All webhooks use HTTPS
- Rate limiting is implemented to prevent abuse
- Sensitive data is filtered from webhook payloads
- Access logs for all API usage
- API keys can be revoked at any time

## Testing Strategy
- Unit tests for webhook delivery service
- Integration tests with mock Zapier endpoints
- Load testing for webhook throughput
- Security testing for API authentication
- End-to-end tests for each trigger and action

## Rollout Plan
1. Internal testing with sample Zaps
2. Limited beta with selected customers
3. Zapier app submission for developer approval
4. Public beta in Zapier marketplace
5. Full documentation and support readiness
6. General availability announcement
