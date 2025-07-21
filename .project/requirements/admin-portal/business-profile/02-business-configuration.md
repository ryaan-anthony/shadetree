# Feature: Business Configuration

## Overview
Comprehensive business profile management that allows owners to configure all aspects of their business information, including contact details, service areas, and operational preferences.

## User Stories
- As a business owner, I want to update my business information so customers see accurate details
- As a business owner, I want to configure my service areas so I only get requests in my coverage zone
- As a business owner, I want to set my business preferences to control how the platform operates
- As a business owner, I want to manage my business contact information across all customer touchpoints

## Tasks

### 1. Business Information Management
**File**: `app/controllers/admin/business_settings_controller.rb`

**Implementation Notes**:
```ruby
class Admin::BusinessSettingsController < ApplicationController
  include BusinessContext
  
  before_action :require_business
  before_action :require_business_owner
  
  def show
    @business = current_business
  end
  
  def edit
    @business = current_business
  end
  
  def update
    @business = current_business
    
    if @business.update(business_params)
      redirect_to admin_business_settings_path, notice: "Business information updated successfully"
    else
      render :edit, status: :unprocessable_entity
    end
  end
  
  private
  
  def business_params
    params.require(:business).permit(
      :name, :business_type, :phone, :email, :website,
      :address_line_1, :address_line_2, :city, :state, :zip_code,
      :description, :tax_id, :license_number,
      :auto_quote_enabled, :require_approval_for_quotes,
      :default_quote_validity_days, :timezone
    )
  end
  
  def require_business_owner
    unless current_user.business_ownerships.find_by(business: current_business)&.owner?
      redirect_to admin_dashboard_path, alert: "Access denied"
    end
  end
end
```

### 2. Service Area Configuration
**File**: `app/models/service_area.rb`

**Implementation Notes**:
```ruby
class ServiceArea < ApplicationRecord
  belongs_to :business
  
  validates :name, presence: true, length: { maximum: 255 }
  validates :area_type, presence: true
  validates :zip_codes, presence: true, if: -> { area_type == 'zip_codes' }
  validates :radius_miles, presence: true, numericality: { greater_than: 0 }, if: -> { area_type == 'radius' }
  
  enum area_type: { zip_codes: 0, radius: 1, custom_boundary: 2 }
  
  scope :active, -> { where(is_active: true) }
  
  def covers_location?(zip_code: nil, lat: nil, lng: nil)
    case area_type
    when 'zip_codes'
      zip_codes_array.include?(zip_code.to_s)
    when 'radius'
      return false unless lat && lng && center_lat && center_lng
      distance = calculate_distance(lat, lng, center_lat, center_lng)
      distance <= radius_miles
    else
      false # custom_boundary not implemented yet
    end
  end
  
  def zip_codes_array
    return [] unless zip_codes.present?
    zip_codes.split(',').map(&:strip)
  end
  
  private
  
  def calculate_distance(lat1, lng1, lat2, lng2)
    # Haversine formula for distance calculation
    rad_per_deg = Math::PI / 180
    rlat1 = lat1 * rad_per_deg
    rlat2 = lat2 * rad_per_deg
    rlng1 = lng1 * rad_per_deg
    rlng2 = lng2 * rad_per_deg
    
    dlat = rlat2 - rlat1
    dlng = rlng2 - rlng1
    
    a = Math.sin(dlat/2)**2 + Math.cos(rlat1) * Math.cos(rlat2) * Math.sin(dlng/2)**2
    c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a))
    
    3959 * c # Earth's radius in miles
  end
end
```

### 3. Business Preferences Model
**File**: `app/models/business_preference.rb`

**Implementation Notes**:
```ruby
class BusinessPreference < ApplicationRecord
  belongs_to :business
  
  validates :key, presence: true, uniqueness: { scope: :business_id }
  validates :value_type, presence: true
  
  enum value_type: { string: 0, integer: 1, boolean: 2, json: 3 }
  
  def typed_value
    case value_type
    when 'integer'
      value.to_i
    when 'boolean'
      value == 'true'
    when 'json'
      JSON.parse(value)
    else
      value
    end
  end
  
  def self.for_business(business)
    where(business: business).pluck(:key, :value).to_h
  end
end
```

### 4. Business Configuration Views
**File**: `app/views/admin/business_settings/show.html.erb`

**Implementation Notes**:
```erb
<div class="max-w-4xl mx-auto py-6">
  <div class="md:flex md:items-center md:justify-between mb-8">
    <div class="flex-1 min-w-0">
      <h1 class="text-2xl font-bold leading-7 text-gray-900 sm:text-3xl sm:truncate">
        Business Settings
      </h1>
      <p class="mt-1 text-sm text-gray-500">
        Manage your business information and preferences
      </p>
    </div>
    <div class="mt-4 flex md:mt-0 md:ml-4">
      <%= link_to "Edit Settings", edit_admin_business_settings_path, 
          class: "bg-green-600 text-white px-4 py-2 rounded-md text-sm font-medium hover:bg-green-700" %>
    </div>
  </div>

  <div class="bg-white shadow overflow-hidden sm:rounded-md">
    <div class="px-4 py-5 sm:p-6">
      <div class="grid grid-cols-1 gap-6 sm:grid-cols-2">
        <!-- Business Information -->
        <div class="col-span-2">
          <h3 class="text-lg leading-6 font-medium text-gray-900 mb-4">Business Information</h3>
        </div>
        
        <div>
          <dt class="text-sm font-medium text-gray-500">Business Name</dt>
          <dd class="mt-1 text-sm text-gray-900"><%= @business.name %></dd>
        </div>
        
        <div>
          <dt class="text-sm font-medium text-gray-500">Business Type</dt>
          <dd class="mt-1 text-sm text-gray-900"><%= @business.business_type&.humanize %></dd>
        </div>
        
        <div>
          <dt class="text-sm font-medium text-gray-500">Phone</dt>
          <dd class="mt-1 text-sm text-gray-900"><%= @business.phone %></dd>
        </div>
        
        <div>
          <dt class="text-sm font-medium text-gray-500">Email</dt>
          <dd class="mt-1 text-sm text-gray-900"><%= @business.email %></dd>
        </div>
        
        <div class="col-span-2">
          <dt class="text-sm font-medium text-gray-500">Address</dt>
          <dd class="mt-1 text-sm text-gray-900">
            <%= @business.address_line_1 %><br>
            <% if @business.address_line_2.present? %>
              <%= @business.address_line_2 %><br>
            <% end %>
            <%= @business.city %>, <%= @business.state %> <%= @business.zip_code %>
          </dd>
        </div>
        
        <% if @business.website.present? %>
        <div>
          <dt class="text-sm font-medium text-gray-500">Website</dt>
          <dd class="mt-1 text-sm text-gray-900">
            <%= link_to @business.website, @business.website, target: "_blank", 
                class: "text-green-600 hover:text-green-500" %>
          </dd>
        </div>
        <% end %>
        
        <!-- Operational Preferences -->
        <div class="col-span-2 mt-8">
          <h3 class="text-lg leading-6 font-medium text-gray-900 mb-4">Operational Preferences</h3>
        </div>
        
        <div>
          <dt class="text-sm font-medium text-gray-500">Auto Quote</dt>
          <dd class="mt-1 text-sm text-gray-900">
            <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium 
                         <%= @business.auto_quote_enabled? ? 'bg-green-100 text-green-800' : 'bg-gray-100 text-gray-800' %>">
              <%= @business.auto_quote_enabled? ? 'Enabled' : 'Disabled' %>
            </span>
          </dd>
        </div>
        
        <div>
          <dt class="text-sm font-medium text-gray-500">Quote Validity</dt>
          <dd class="mt-1 text-sm text-gray-900"><%= @business.default_quote_validity_days || 30 %> days</dd>
        </div>
      </div>
    </div>
  </div>

  <!-- Service Areas -->
  <div class="mt-8 bg-white shadow overflow-hidden sm:rounded-md">
    <div class="px-4 py-5 sm:p-6">
      <div class="flex items-center justify-between mb-4">
        <h3 class="text-lg leading-6 font-medium text-gray-900">Service Areas</h3>
        <%= link_to "Add Service Area", new_admin_service_area_path, 
            class: "bg-green-600 text-white px-3 py-1 rounded text-sm hover:bg-green-700" %>
      </div>
      
      <% if @business.service_areas.active.any? %>
        <div class="space-y-3">
          <% @business.service_areas.active.each do |area| %>
            <div class="border border-gray-200 rounded-lg p-4">
              <div class="flex items-center justify-between">
                <div>
                  <h4 class="font-medium text-gray-900"><%= area.name %></h4>
                  <p class="text-sm text-gray-500">
                    <%= area.area_type.humanize %> - 
                    <% if area.zip_codes? %>
                      <%= area.zip_codes_array.count %> ZIP codes
                    <% elsif area.radius? %>
                      <%= area.radius_miles %> mile radius
                    <% end %>
                  </p>
                </div>
                <div class="flex space-x-2">
                  <%= link_to "Edit", edit_admin_service_area_path(area), 
                      class: "text-green-600 hover:text-green-500 text-sm" %>
                  <%= link_to "Delete", admin_service_area_path(area), 
                      method: :delete, 
                      confirm: "Are you sure?",
                      class: "text-red-600 hover:text-red-500 text-sm" %>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      <% else %>
        <p class="text-gray-500 text-sm">No service areas configured. Add your first service area to start receiving requests.</p>
      <% end %>
    </div>
  </div>
</div>
```

### 5. Service Area Controller
**File**: `app/controllers/admin/service_areas_controller.rb`

**Implementation Notes**:
```ruby
class Admin::ServiceAreasController < ApplicationController
  include BusinessContext
  
  before_action :require_business
  before_action :set_service_area, only: [:show, :edit, :update, :destroy]
  
  def index
    @service_areas = current_business.service_areas.includes(:business)
  end
  
  def new
    @service_area = current_business.service_areas.build
  end
  
  def create
    @service_area = current_business.service_areas.build(service_area_params)
    
    if @service_area.save
      redirect_to admin_business_settings_path, notice: "Service area created successfully"
    else
      render :new, status: :unprocessable_entity
    end
  end
  
  def edit
  end
  
  def update
    if @service_area.update(service_area_params)
      redirect_to admin_business_settings_path, notice: "Service area updated successfully"
    else
      render :edit, status: :unprocessable_entity
    end
  end
  
  def destroy
    @service_area.destroy
    redirect_to admin_business_settings_path, notice: "Service area deleted successfully"
  end
  
  private
  
  def set_service_area
    @service_area = current_business.service_areas.find(params[:id])
  end
  
  def service_area_params
    params.require(:service_area).permit(
      :name, :area_type, :zip_codes, :radius_miles, 
      :center_lat, :center_lng, :is_active
    )
  end
end
```

### 6. Database Migrations
**File**: `db/migrate/[timestamp]_add_configuration_fields_to_businesses.rb`

**Implementation Notes**:
```ruby
class AddConfigurationFieldsToBusinesses < ActiveRecord::Migration[8.0]
  def change
    add_column :businesses, :tax_id, :string
    add_column :businesses, :license_number, :string
    add_column :businesses, :auto_quote_enabled, :boolean, default: false
    add_column :businesses, :require_approval_for_quotes, :boolean, default: true
    add_column :businesses, :default_quote_validity_days, :integer, default: 30
    add_column :businesses, :timezone, :string, default: 'America/New_York'
    add_column :businesses, :setup_completed_at, :datetime
    
    add_index :businesses, :tax_id
    add_index :businesses, :setup_completed_at
  end
end
```

**File**: `db/migrate/[timestamp]_create_service_areas.rb`

**Implementation Notes**:
```ruby
class CreateServiceAreas < ActiveRecord::Migration[8.0]
  def change
    create_table :service_areas do |t|
      t.references :business, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :area_type, null: false, default: 0
      t.text :zip_codes
      t.decimal :radius_miles, precision: 8, scale: 2
      t.decimal :center_lat, precision: 10, scale: 6
      t.decimal :center_lng, precision: 10, scale: 6
      t.boolean :is_active, default: true
      
      t.timestamps
    end
    
    add_index :service_areas, [:business_id, :is_active]
  end
end
```

## Configuration Categories
- **Business Information**: Name, type, contact details, address
- **Operational Settings**: Auto-quote preferences, approval workflows
- **Service Areas**: ZIP codes, radius-based coverage, custom boundaries
- **Legal Information**: Tax ID, license numbers, compliance data
- **Preferences**: Timezone, quote validity periods, notification settings

## Validation Rules
- Business information must be complete for public visibility
- Service areas required for quote request routing
- Tax ID format validation based on business type
- Geographic coordinates validation for radius-based areas

## Integration Points
- Quote generation uses business configuration for templates
- Service area validation for incoming quote requests
- Staff permissions respect business ownership roles
- Customer-facing materials reflect business branding settings
