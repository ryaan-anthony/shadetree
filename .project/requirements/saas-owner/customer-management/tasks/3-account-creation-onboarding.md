# Task: Implement Account Creation and Onboarding Flow

## Overview
Create functionality that allows SaaS platform administrators to create and onboard new business customers, including registration, account setup, and initial configuration.

## Implementation Notes

### Create Account Creation Controller and Service

```ruby
# app/controllers/admin/customer_onboarding_controller.rb
module Admin
  class CustomerOnboardingController < AdminController
    def new
      @customer = BusinessCustomer.new
      @customer.build_subscription # Build a subscription association for the form
    end
    
    def create
      result = CustomerOnboardingService.create(customer_params)
      
      if result.success?
        redirect_to admin_customer_path(result.customer), notice: "Customer #{result.customer.name} was successfully created."
      else
        @customer = result.customer
        flash.now[:alert] = "There was an error creating the customer."
        render :new
      end
    end
    
    private
    
    def customer_params
      params.require(:business_customer).permit(
        :name, :domain, :contact_name, :contact_email, :contact_phone,
        :status, :time_zone, :notes,
        subscription_attributes: [:plan, :billing_cycle, :price_override]
      )
    end
  end
end

# app/services/customer_onboarding_service.rb
class CustomerOnboardingService
  attr_reader :customer, :success
  
  def self.create(params)
    new(params).tap(&:process)
  end
  
  def initialize(params)
    @params = params
    @success = false
    @customer = nil
  end
  
  def process
    ApplicationRecord.transaction do
      create_customer
      create_admin_user
      provision_resources
      send_welcome_email
      record_activity
      
      @success = true
    end
    
    self
  rescue => e
    Rails.logger.error("Customer onboarding failed: #{e.message}")
    @success = false
    self
  end
  
  def success?
    @success
  end
  
  private
  
  def create_customer
    @customer = BusinessCustomer.new(@params)
    @customer.save!
  end
  
  def create_admin_user
    # Create initial admin user for the customer
    generated_password = SecureRandom.hex(8)
    
    user = @customer.users.create!(
      email: @params[:contact_email],
      name: @params[:contact_name],
      role: 'admin',
      password: generated_password,
      password_confirmation: generated_password
    )
    
    @temp_password = generated_password
  end
  
  def provision_resources
    # Provision any necessary resources for the customer
    # This might include creating tenant databases, storage buckets, etc.
    ProvisionCustomerResourcesJob.perform_later(@customer.id)
  end
  
  def send_welcome_email
    CustomerMailer.welcome(@customer, @temp_password).deliver_later
  end
  
  def record_activity
    @customer.activity_logs.create!(
      action: 'customer_created',
      actor_type: 'AdminUser',
      actor_id: Current.user&.id,
      details: { method: 'manual_creation' }
    )
  end
end
```

### Create Onboarding Form

```erb
<!-- app/views/admin/customer_onboarding/new.html.erb -->
<div class="onboarding-container">
  <h1>Create New Business Customer</h1>
  
  <%= form_with model: [:admin, @customer], url: admin_customer_onboarding_path, method: :post, class: "onboarding-form" do |f| %>
    <section class="form-section">
      <h2>Business Information</h2>
      
      <div class="field-group">
        <%= f.label :name, "Business Name" %>
        <%= f.text_field :name, required: true %>
      </div>
      
      <div class="field-group">
        <%= f.label :domain %>
        <%= f.text_field :domain, placeholder: "example.com" %>
        <small>Used for single sign-on and branding</small>
      </div>
      
      <div class="field-group">
        <%= f.label :time_zone %>
        <%= f.time_zone_select :time_zone, nil, {default: "Pacific Time (US & Canada)"} %>
      </div>
    </section>
    
    <section class="form-section">
      <h2>Primary Contact</h2>
      
      <div class="field-group">
        <%= f.label :contact_name %>
        <%= f.text_field :contact_name, required: true %>
      </div>
      
      <div class="field-group">
        <%= f.label :contact_email %>
        <%= f.email_field :contact_email, required: true %>
        <small>Will be used to create the initial admin user</small>
      </div>
      
      <div class="field-group">
        <%= f.label :contact_phone %>
        <%= f.telephone_field :contact_phone %>
      </div>
    </section>
    
    <section class="form-section">
      <h2>Subscription</h2>
      
      <%= f.fields_for :subscription do |s| %>
        <div class="field-group">
          <%= s.label :plan %>
          <%= s.select :plan, Subscription.plans.keys.map { |p| [p.humanize, p] }, { include_blank: "Select a plan" }, required: true %>
        </div>
        
        <div class="field-group">
          <%= s.label :billing_cycle %>
          <%= s.select :billing_cycle, [["Monthly", "monthly"], ["Annually", "annually"]], { include_blank: "Select billing cycle" }, required: true %>
        </div>
        
        <div class="field-group">
          <%= s.label :price_override, "Price Override (optional)" %>
          <%= s.number_field :price_override, step: 0.01, min: 0 %>
          <small>Leave blank to use standard pricing</small>
        </div>
      <% end %>
    </section>
    
    <section class="form-section">
      <h2>Additional Information</h2>
      
      <div class="field-group">
        <%= f.label :notes %>
        <%= f.text_area :notes, rows: 3 %>
      </div>
    </section>
    
    <div class="form-actions">
      <%= f.submit "Create Customer", class: "primary-button" %>
      <%= link_to "Cancel", admin_customers_path, class: "secondary-button" %>
    </div>
  <% end %>
</div>
```

## Test Cases

```ruby
# spec/services/customer_onboarding_service_spec.rb
require 'rails_helper'

RSpec.describe CustomerOnboardingService do
  let(:valid_params) do
    {
      name: "Acme Corp",
      domain: "acme.com",
      contact_name: "John Doe",
      contact_email: "john@acme.com",
      contact_phone: "555-123-4567",
      time_zone: "Pacific Time (US & Canada)",
      subscription_attributes: {
        plan: "professional",
        billing_cycle: "monthly"
      }
    }
  end
  
  describe "#create" do
    it "creates a new customer record" do
      expect {
        CustomerOnboardingService.create(valid_params)
      }.to change(BusinessCustomer, :count).by(1)
    end
    
    it "creates an admin user for the customer" do
      result = CustomerOnboardingService.create(valid_params)
      
      expect(result.customer.users.count).to eq(1)
      expect(result.customer.users.first.role).to eq("admin")
      expect(result.customer.users.first.email).to eq("john@acme.com")
    end
    
    it "enqueues the resource provisioning job" do
      expect {
        CustomerOnboardingService.create(valid_params)
      }.to have_enqueued_job(ProvisionCustomerResourcesJob)
    end
    
    it "sends a welcome email" do
      expect {
        CustomerOnboardingService.create(valid_params)
      }.to have_enqueued_mail(CustomerMailer, :welcome)
    end
    
    it "records the activity in the log" do
      result = CustomerOnboardingService.create(valid_params)
      
      expect(result.customer.activity_logs.count).to eq(1)
      expect(result.customer.activity_logs.first.action).to eq("customer_created")
    end
  end
end
```
