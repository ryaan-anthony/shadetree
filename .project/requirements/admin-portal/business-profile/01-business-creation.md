# Feature: Business Creation & Setup

## Overview
Streamlined business creation workflow that guides new users through the essential setup steps to get their service business operational on the platform quickly.

## User Stories
- As a new user, I want to create my first business profile so I can start using the platform
- As an entrepreneur, I want to set up a new business location quickly with minimal friction
- As a business owner, I want guided setup to ensure I don't miss critical configuration steps
- As a user, I want to see progress indicators during setup to understand completion status

## Tasks

### 1. Create Business Registration Form
**File**: `app/controllers/admin/business_setup_controller.rb`

**Implementation Notes**:
```ruby
class Admin::BusinessSetupController < ApplicationController
  before_action :authenticate_user!
  before_action :check_can_create_business
  
  def new
    @business = Business.new
    @step = params[:step] || 'basic_info'
  end
  
  def create
    @business = Business.new(business_params)
    
    if @business.save
      # Create ownership relationship
      BusinessOwnership.create!(
        user: current_user,
        business: @business,
        role: 'owner',
        is_primary: current_user.businesses.empty?
      )
      
      redirect_to admin_business_setup_path(@business, step: 'services')
    else
      render :new, status: :unprocessable_entity
    end
  end
  
  def show
    @business = current_user.businesses.find(params[:id])
    @step = params[:step] || 'complete'
    @progress = calculate_setup_progress(@business)
  end
  
  def update
    @business = current_user.businesses.find(params[:id])
    
    if @business.update(business_params)
      next_step = determine_next_step(params[:step])
      if next_step
        redirect_to admin_business_setup_path(@business, step: next_step)
      else
        # Setup complete
        BusinessSetupService.new(@business).finalize_setup
        redirect_to admin_dashboard_path, notice: "Business setup complete!"
      end
    else
      render :show, status: :unprocessable_entity
    end
  end
  
  private
  
  def business_params
    params.require(:business).permit(
      :name, :business_type, :phone, :email, :website,
      :address_line_1, :address_line_2, :city, :state, :zip_code,
      :description
    )
  end
  
  def check_can_create_business
    unless current_user.can_create_business?
      redirect_to admin_businesses_path, alert: "Maximum number of businesses reached"
    end
  end
  
  def calculate_setup_progress(business)
    steps = %w[basic_info services hours pricing complete]
    current_step_index = steps.index(params[:step]) || 0
    ((current_step_index + 1).to_f / steps.length * 100).round
  end
  
  def determine_next_step(current_step)
    steps = %w[basic_info services hours pricing]
    current_index = steps.index(current_step)
    return nil unless current_index
    
    steps[current_index + 1]
  end
end
```

### 2. Multi-Step Setup Wizard Views
**File**: `app/views/admin/business_setup/new.html.erb`

**Implementation Notes**:
```erb
<div class="max-w-3xl mx-auto py-8">
  <div class="bg-white shadow rounded-lg">
    <!-- Progress Bar -->
    <div class="px-6 py-4 border-b border-gray-200">
      <div class="flex items-center justify-between text-sm font-medium text-gray-500">
        <span class="text-green-600">Step 1 of 5</span>
        <span>Business Information</span>
      </div>
      <div class="mt-2">
        <div class="bg-gray-200 rounded-full h-2">
          <div class="bg-green-600 h-2 rounded-full" style="width: 20%"></div>
        </div>
      </div>
    </div>
    
    <!-- Form Content -->
    <div class="px-6 py-6">
      <h1 class="text-2xl font-bold text-gray-900 mb-2">Create Your Business</h1>
      <p class="text-gray-600 mb-8">Let's get your service business set up on Shadetree</p>
      
      <%= form_with model: [:admin, @business], url: admin_business_setup_index_path, local: true, class: "space-y-6" do |form| %>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div>
            <%= form.label :name, "Business Name", class: "block text-sm font-medium text-gray-700" %>
            <%= form.text_field :name, class: "mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-green-500 focus:border-green-500" %>
          </div>
          
          <div>
            <%= form.label :business_type, "Business Type", class: "block text-sm font-medium text-gray-700" %>
            <%= form.select :business_type, 
                options_for_select([
                  ['Landscaping', 'landscaping'],
                  ['Lawn Care', 'lawn_care'],
                  ['Tree Service', 'tree_service'],
                  ['Irrigation', 'irrigation'],
                  ['General Contractor', 'general_contractor'],
                  ['Other', 'other']
                ], @business.business_type),
                { prompt: 'Select business type...' },
                { class: "mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-green-500 focus:border-green-500" } %>
          </div>
        </div>
        
        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div>
            <%= form.label :phone, "Phone Number", class: "block text-sm font-medium text-gray-700" %>
            <%= form.telephone_field :phone, class: "mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-green-500 focus:border-green-500" %>
          </div>
          
          <div>
            <%= form.label :email, "Business Email", class: "block text-sm font-medium text-gray-700" %>
            <%= form.email_field :email, class: "mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-green-500 focus:border-green-500" %>
          </div>
        </div>
        
        <div>
          <%= form.label :address_line_1, "Address", class: "block text-sm font-medium text-gray-700" %>
          <%= form.text_field :address_line_1, placeholder: "Street address", class: "mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-green-500 focus:border-green-500" %>
        </div>
        
        <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div>
            <%= form.text_field :city, placeholder: "City", class: "block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-green-500 focus:border-green-500" %>
          </div>
          <div>
            <%= form.text_field :state, placeholder: "State", class: "block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-green-500 focus:border-green-500" %>
          </div>
          <div>
            <%= form.text_field :zip_code, placeholder: "ZIP Code", class: "block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-green-500 focus:border-green-500" %>
          </div>
        </div>
        
        <div>
          <%= form.label :description, "Business Description (Optional)", class: "block text-sm font-medium text-gray-700" %>
          <%= form.text_area :description, rows: 3, placeholder: "Brief description of your services...", class: "mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-green-500 focus:border-green-500" %>
        </div>
        
        <div class="flex justify-end">
          <%= form.submit "Continue to Services", class: "bg-green-600 text-white px-6 py-2 rounded-md hover:bg-green-700 font-medium" %>
        </div>
      <% end %>
    </div>
  </div>
</div>
```

### 3. Business Setup Service
**File**: `app/services/business_setup_service.rb`

**Implementation Notes**:
```ruby
class BusinessSetupService
  def initialize(business)
    @business = business
  end
  
  def call
    ActiveRecord::Base.transaction do
      create_default_service_categories
      create_default_quote_templates
      create_default_price_list
      create_default_business_hours
    end
  end
  
  def finalize_setup
    @business.update!(setup_completed_at: Time.current)
    send_welcome_email
  end
  
  private
  
  attr_reader :business
  
  def create_default_service_categories
    default_categories_for_type = {
      'landscaping' => [
        { name: "Landscape Design", description: "Custom landscape design and planning", color_code: "#8B5CF6" },
        { name: "Installation", description: "Landscape installation services", color_code: "#059669" },
        { name: "Maintenance", description: "Ongoing landscape maintenance", color_code: "#0D9488" }
      ],
      'lawn_care' => [
        { name: "Mowing", description: "Regular lawn mowing services", color_code: "#10B981" },
        { name: "Fertilization", description: "Lawn feeding and treatment", color_code: "#F59E0B" },
        { name: "Seasonal Cleanup", description: "Spring and fall cleanup", color_code: "#EF4444" }
      ],
      'tree_service' => [
        { name: "Tree Trimming", description: "Professional tree pruning", color_code: "#84CC16" },
        { name: "Tree Removal", description: "Safe tree removal services", color_code: "#EF4444" },
        { name: "Emergency Service", description: "Storm damage and emergency calls", color_code: "#F97316" }
      ]
    }
    
    categories = default_categories_for_type[@business.business_type] || 
                 default_categories_for_type['landscaping']
    
    categories.each do |category_attrs|
      business.service_categories.create!(category_attrs)
    end
  end
  
  def create_default_quote_templates
    QuoteTemplate.create_default_templates(business)
  end
  
  def create_default_price_list
    business.price_lists.create!(
      name: "Standard Pricing",
      customer_type: "standard",
      effective_date: Date.current,
      is_active: true
    )
  end
  
  def create_default_business_hours
    # Create default Monday-Friday 8am-5pm hours
    (1..5).each do |day_of_week|
      business.business_hours.create!(
        day_of_week: day_of_week,
        open_time: "08:00",
        close_time: "17:00",
        is_open: true
      )
    end
  end
  
  def send_welcome_email
    BusinessMailer.welcome_email(business).deliver_later
  end
end
```

### 4. Add Business Setup Routes
**File**: `config/routes.rb`

**Implementation Notes**:
```ruby
Rails.application.routes.draw do
  namespace :admin do
    resources :business_setup, only: [:new, :create, :show, :update]
    # ...existing routes...
  end
end
```

### 5. Business Setup Validation
**File**: `app/models/business.rb` (enhancement)

**Implementation Notes**:
```ruby
class Business < ApplicationRecord
  # ...existing code...
  
  def setup_complete?
    setup_completed_at.present?
  end
  
  def setup_progress_percentage
    completed_steps = []
    
    completed_steps << 'basic_info' if basic_info_complete?
    completed_steps << 'services' if services.exists?
    completed_steps << 'hours' if business_hours.exists?
    completed_steps << 'pricing' if price_lists.exists?
    
    total_steps = 4
    (completed_steps.length.to_f / total_steps * 100).round
  end
  
  private
  
  def basic_info_complete?
    name.present? && 
    business_type.present? && 
    phone.present? && 
    email.present? &&
    address_line_1.present? &&
    city.present? &&
    state.present? &&
    zip_code.present?
  end
end
```

## Business Validation Rules
- Business name must be unique within user's businesses
- Required fields: name, business_type, phone, email, address
- Email format validation
- Phone number format validation
- Business type must be from predefined enum

## Setup Flow
1. **Basic Info** - Business details and contact information
2. **Services** - Add initial service offerings
3. **Hours** - Set operating hours and availability
4. **Pricing** - Configure pricing structure
5. **Complete** - Review and launch

## Success Criteria
- Users can complete business setup in under 10 minutes
- Setup abandonment rate < 15%
- All required business data captured during setup
- Default configurations created automatically
