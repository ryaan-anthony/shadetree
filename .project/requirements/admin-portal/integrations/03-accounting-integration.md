# Feature: Accounting Integration (QuickBooks)

## Overview
Provide a seamless integration with QuickBooks accounting software that allows businesses to automatically sync financial data, invoices, payments, and customer information between Shadetree and their QuickBooks account.

## Goals
- Eliminate manual data entry for financial transactions
- Ensure financial data consistency across platforms
- Simplify tax preparation and financial reporting
- Reduce accounting errors and reconciliation time

## User Stories
- As a business owner, I want to connect my QuickBooks account so all financial data syncs automatically
- As an accountant, I want invoices created in Shadetree to appear in QuickBooks
- As a business owner, I want customer payments to be recorded in my accounting system
- As an administrator, I want to map service categories to specific QuickBooks accounts
- As a financial manager, I want to reconcile payments between systems

## Tasks

### Task 1: Create QuickBooks OAuth Integration
**Description:** Implement OAuth2 authentication flow for connecting to QuickBooks API.

**Implementation Notes:**
- Create QuickBooks integration controller and service
- Implement OAuth2 authentication flow
- Store and manage encrypted QuickBooks API tokens
- Handle token refresh and expiration

```ruby
# app/controllers/admin/integrations/quickbooks_controller.rb
class Admin::Integrations::QuickbooksController < Admin::IntegrationsController
  before_action :require_admin
  before_action :set_integration, only: [:edit, :update, :disconnect, :sync_now]
  
  def new
    @integration = current_business.integrations.new(provider: :quickbooks)
  end
  
  def create
    @integration = current_business.integrations.new(provider: :quickbooks, configured_by: current_user)
    if @integration.save
      # Generate auth URL and redirect to QuickBooks authorization page
      auth_url = QuickbooksIntegrationService.new(@integration).authorization_url(
        redirect_url: oauth_callback_admin_integrations_quickbooks_url
      )
      redirect_to auth_url
    else
      flash[:error] = "Failed to initialize QuickBooks integration"
      render :new
    end
  end
  
  def oauth_callback
    code = params[:code]
    integration = current_business.integrations.find_by(provider: :quickbooks)
    
    if code.present? && integration
      service = QuickbooksIntegrationService.new(integration)
      if service.complete_oauth(code)
        flash[:success] = "QuickBooks account connected successfully"
        redirect_to edit_admin_integration_path(integration)
      else
        flash[:error] = "Failed to connect QuickBooks account"
        redirect_to new_admin_integrations_quickbooks_path
      end
    else
      flash[:error] = "Invalid authorization request"
      redirect_to admin_integrations_path
    end
  end
  
  def disconnect
    QuickbooksIntegrationService.new(@integration).revoke_access
    @integration.update(status: :disconnected, credentials: nil)
    flash[:success] = "QuickBooks integration disconnected"
    redirect_to admin_integrations_path
  end
  
  def sync_now
    SyncQuickbooksJob.perform_later(@integration.id)
    flash[:notice] = "QuickBooks sync initiated"
    redirect_to edit_admin_integration_path(@integration)
  end
  
  private
  
  def set_integration
    @integration = current_business.integrations.find_by(provider: :quickbooks)
  end
end
```

```ruby
# app/services/quickbooks_integration_service.rb
class QuickbooksIntegrationService < IntegrationService
  SCOPES = "com.intuit.quickbooks.accounting"
  
  def authorization_url(redirect_url:)
    oauth_client.auth_code.authorize_url(
      redirect_uri: redirect_url,
      scope: SCOPES,
      state: SecureRandom.hex(24)
    )
  end
  
  def complete_oauth(code, redirect_url:)
    token = oauth_client.auth_code.get_token(
      code,
      redirect_uri: redirect_url
    )
    
    @integration.update(
      credentials: {
        access_token: token.token,
        refresh_token: token.refresh_token,
        expires_at: token.expires_at
      },
      status: :connected
    )
    
    true
  rescue OAuth2::Error
    false
  end
  
  def revoke_access
    # Call QuickBooks API to revoke access
  end
  
  private
  
  def oauth_client
    OAuth2::Client.new(
      Rails.application.credentials.quickbooks[:client_id],
      Rails.application.credentials.quickbooks[:client_secret],
      site: 'https://appcenter.intuit.com',
      authorize_url: '/connect/oauth2',
      token_url: '/oauth2/v1/tokens/bearer'
    )
  end
end
```

### Task 2: Implement Data Mapping Configuration
**Description:** Create interface for mapping Shadetree financial entities to QuickBooks accounts.

**Implementation Notes:**
- Create account mapping interface
- Build service category to income account mappings
- Configure expense categories mapping
- Set up customer synchronization preferences

```ruby
# app/models/quickbooks_mapping.rb
class QuickbooksMapping < ApplicationRecord
  belongs_to :integration
  
  enum entity_type: {
    service: 0,
    customer: 1,
    payment: 2,
    expense: 3
  }
  
  validates :entity_type, :shadetree_id, :quickbooks_id, presence: true
  validates :shadetree_id, uniqueness: { scope: [:integration_id, :entity_type] }
end
```

```ruby
# app/controllers/admin/integrations/quickbooks_mappings_controller.rb
class Admin::Integrations::QuickbooksMappingsController < Admin::IntegrationsController
  before_action :require_admin
  before_action :set_integration
  
  def index
    @service_mappings = @integration.quickbooks_mappings.where(entity_type: :service)
    @quickbooks_accounts = fetch_quickbooks_accounts
    @services = current_business.services
  end
  
  def create
    @mapping = @integration.quickbooks_mappings.new(mapping_params)
    
    if @mapping.save
      flash[:success] = "Mapping created successfully"
    else
      flash[:error] = "Failed to create mapping: #{@mapping.errors.full_messages.join(', ')}"
    end
    
    redirect_to admin_integrations_quickbooks_mappings_path
  end
  
  private
  
  def set_integration
    @integration = current_business.integrations.find_by!(provider: :quickbooks)
  end
  
  def mapping_params
    params.require(:quickbooks_mapping).permit(:entity_type, :shadetree_id, :quickbooks_id, :quickbooks_name)
  end
  
  def fetch_quickbooks_accounts
    QuickbooksIntegrationService.new(@integration).fetch_accounts
  rescue => e
    flash.now[:error] = "Failed to fetch QuickBooks accounts: #{e.message}"
    []
  end
end
```

### Task 3: Implement Synchronization Jobs
**Description:** Create background jobs to handle data synchronization between Shadetree and QuickBooks.

**Implementation Notes:**
- Build bidirectional sync for customers
- Implement invoice creation in QuickBooks
- Sync payment records
- Create change tracking for triggering syncs

```ruby
# app/jobs/sync_quickbooks_job.rb
class SyncQuickbooksJob < ApplicationJob
  queue_as :integrations
  
  def perform(integration_id)
    integration = Integration.find_by(id: integration_id, provider: :quickbooks)
    return unless integration&.connected?
    
    integration.update(status: :syncing)
    
    begin
      service = QuickbooksIntegrationService.new(integration)
      
      # Sync customers
      sync_customers(integration, service)
      
      # Sync invoices
      sync_invoices(integration, service)
      
      # Sync payments
      sync_payments(integration, service)
      
      integration.update(status: :connected, last_sync_at: Time.current)
    rescue => e
      integration.update(
        status: :error,
        last_error: "#{e.class}: #{e.message}"
      )
      raise
    end
  end
  
  private
  
  def sync_customers(integration, service)
    # Sync logic for customers
    integration.business.customers.find_each do |customer|
      track_sync(integration, customer) do
        service.sync_customer(customer)
      end
    end
  end
  
  def sync_invoices(integration, service)
    # Sync logic for invoices
    integration.business.invoices.unpaid.find_each do |invoice|
      track_sync(integration, invoice) do
        service.sync_invoice(invoice)
      end
    end
  end
  
  def sync_payments(integration, service)
    # Sync logic for payments
    integration.business.payments.where(synced_at: nil).find_each do |payment|
      track_sync(integration, payment) do
        service.sync_payment(payment)
      end
    end
  end
  
  def track_sync(integration, source)
    sync = integration.integration_syncs.create!(
      source: source,
      sync_type: :push,
      status: :syncing
    )
    
    begin
      yield
      sync.update(status: :completed)
    rescue => e
      sync.update(status: :failed, error_message: "#{e.class}: #{e.message}")
      raise
    end
  end
end
```

```ruby
# app/models/concerns/quickbooks_syncable.rb
module QuickbooksSyncable
  extend ActiveSupport::Concern
  
  included do
    after_save :schedule_quickbooks_sync, if: :sync_needed?
    after_destroy :schedule_quickbooks_sync_deletion
    
    # Track when record was last synced with QuickBooks
    attribute :quickbooks_id, :string
    attribute :synced_at, :datetime
  end
  
  def schedule_quickbooks_sync
    integration = business.integrations.find_by(provider: :quickbooks, status: :connected)
    return unless integration
    
    SyncQuickbooksEntityJob.perform_later(integration.id, self.class.name, id)
  end
  
  def schedule_quickbooks_sync_deletion
    integration = business.integrations.find_by(provider: :quickbooks, status: :connected)
    return unless integration
    
    DeleteQuickbooksEntityJob.perform_later(integration.id, self.class.name, id, quickbooks_id)
  end
  
  def sync_needed?
    quickbooks_syncable_fields = self.class.quickbooks_syncable_fields
    return true if quickbooks_syncable_fields.nil?
    
    (saved_changes.keys & quickbooks_syncable_fields).any?
  end
  
  class_methods do
    def quickbooks_syncable(*fields)
      cattr_accessor :quickbooks_syncable_fields
      self.quickbooks_syncable_fields = fields.map(&:to_s)
    end
  end
end
```

### Task 4: Create Integration Status and History Dashboard
**Description:** Build an interface for viewing integration health, sync status, and history.

**Implementation Notes:**
- Create a status dashboard
- Implement sync history and logs
- Add error reporting and alerting
- Provide manual sync triggers

```ruby
# app/controllers/admin/integrations/quickbooks_status_controller.rb
class Admin::Integrations::QuickbooksStatusController < Admin::IntegrationsController
  before_action :require_admin
  before_action :set_integration
  
  def show
    @recent_syncs = @integration.integration_syncs.recent.includes(:source).order(created_at: :desc).limit(50)
    @sync_stats = {
      total: @integration.integration_syncs.count,
      success: @integration.integration_syncs.completed.count,
      failed: @integration.integration_syncs.failed.count
    }
    @error_rate = (@sync_stats[:failed].to_f / @sync_stats[:total]) * 100 if @sync_stats[:total] > 0
  end
  
  private
  
  def set_integration
    @integration = current_business.integrations.find_by!(provider: :quickbooks)
  end
end
```

```erb
<!-- app/views/admin/integrations/quickbooks_status/show.html.erb -->
<div class="container mx-auto px-4">
  <h1 class="text-2xl font-bold mb-6">QuickBooks Integration Status</h1>
  
  <div class="bg-white shadow rounded-lg mb-6">
    <div class="p-4 border-b border-gray-200">
      <h2 class="text-lg font-semibold">Connection Status</h2>
    </div>
    <div class="p-4">
      <div class="flex items-center mb-2">
        <span class="mr-2">Status:</span>
        <% if @integration.connected? %>
          <span class="bg-green-100 text-green-800 px-2 py-1 rounded-full text-sm">Connected</span>
        <% elsif @integration.error? %>
          <span class="bg-red-100 text-red-800 px-2 py-1 rounded-full text-sm">Error</span>
        <% else %>
          <span class="bg-yellow-100 text-yellow-800 px-2 py-1 rounded-full text-sm"><%= @integration.status.humanize %></span>
        <% end %>
      </div>
      
      <div class="mb-2">
        <span>Last synced: <%= @integration.last_sync_at&.strftime("%B %d, %Y at %I:%M %p") || "Never" %></span>
      </div>
      
      <% if @integration.error? && @integration.last_error.present? %>
        <div class="bg-red-50 border-l-4 border-red-500 p-4 mt-4">
          <h3 class="font-medium text-red-800">Error Details</h3>
          <p class="text-red-700 mt-1"><%= @integration.last_error %></p>
        </div>
      <% end %>
      
      <div class="mt-4">
        <%= button_to "Sync Now", sync_now_admin_integrations_quickbooks_path, method: :post, class: "bg-blue-500 hover:bg-blue-600 text-white px-4 py-2 rounded" %>
      </div>
    </div>
  </div>
  
  <div class="bg-white shadow rounded-lg">
    <div class="p-4 border-b border-gray-200">
      <h2 class="text-lg font-semibold">Sync History</h2>
    </div>
    <div class="p-4">
      <div class="grid grid-cols-3 gap-4 mb-6">
        <div class="bg-blue-50 p-4 rounded-lg">
          <h3 class="text-sm text-blue-800 uppercase">Total Syncs</h3>
          <p class="text-2xl font-bold text-blue-900"><%= @sync_stats[:total] %></p>
        </div>
        <div class="bg-green-50 p-4 rounded-lg">
          <h3 class="text-sm text-green-800 uppercase">Successful</h3>
          <p class="text-2xl font-bold text-green-900"><%= @sync_stats[:success] %></p>
        </div>
        <div class="bg-red-50 p-4 rounded-lg">
          <h3 class="text-sm text-red-800 uppercase">Failed</h3>
          <p class="text-2xl font-bold text-red-900"><%= @sync_stats[:failed] %></p>
        </div>
      </div>
      
      <table class="min-w-full">
        <thead>
          <tr>
            <th class="px-4 py-2 text-left">Time</th>
            <th class="px-4 py-2 text-left">Type</th>
            <th class="px-4 py-2 text-left">Entity</th>
            <th class="px-4 py-2 text-left">Status</th>
          </tr>
        </thead>
        <tbody>
          <% @recent_syncs.each do |sync| %>
            <tr class="border-t border-gray-200">
              <td class="px-4 py-2"><%= sync.created_at.strftime("%m/%d/%Y %H:%M") %></td>
              <td class="px-4 py-2"><%= sync.sync_type.humanize %></td>
              <td class="px-4 py-2">
                <%= sync.source_type %> #<%= sync.source_id %>
              </td>
              <td class="px-4 py-2">
                <% case sync.status %>
                <% when 'completed' %>
                  <span class="bg-green-100 text-green-800 px-2 py-1 rounded-full text-xs">Completed</span>
                <% when 'failed' %>
                  <span class="bg-red-100 text-red-800 px-2 py-1 rounded-full text-xs">Failed</span>
                <% else %>
                  <span class="bg-yellow-100 text-yellow-800 px-2 py-1 rounded-full text-xs"><%= sync.status.humanize %></span>
                <% end %>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
  </div>
</div>
```

## Security Considerations
- All API credentials are encrypted at rest
- OAuth tokens are stored securely
- Access to financial data is restricted to authorized users
- All data transfers occur over HTTPS
- API calls are rate-limited to prevent abuse

## Testing Strategy
- Unit tests for QuickBooks service methods
- Integration tests for OAuth flow
- Mock API responses for sync tests
- End-to-end tests for data mapping accuracy
- Error handling and recovery tests

## Rollout Plan
1. Alpha testing with internal accounting team
2. Beta release to selected customers
3. Documentation and help guides creation
4. Full release with in-app guided setup
5. Post-launch monitoring for errors and support needs
