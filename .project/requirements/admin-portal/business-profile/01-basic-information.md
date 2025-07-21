# Feature: Basic Business Information

## Description
Core business profile management including company name, description, contact information, and essential business details that appear across all customer-facing interfaces.

## User Stories
- As a business owner, I want to update my business name so it appears correctly everywhere
- As a business owner, I want to add my business description so customers understand what I offer
- As a business owner, I want to manage contact information so customers can reach me
- As a business owner, I want to set my business category so I appear in relevant searches

## Tasks

### Task 1: Create Business Profile Model
**Implementation Notes:**
- Create comprehensive business profile model with validation
- Include contact information, descriptions, and categorization
- Add support for multiple business types and categories

```ruby
# app/models/business_profile.rb
class BusinessProfile < ApplicationRecord
  belongs_to :business
  
  validates :business_name, presence: true, length: { minimum: 2, maximum: 100 }
  validates :business_description, length: { maximum: 1000 }
  validates :phone_number, presence: true, format: { with: /\A[\d\-\(\)\+\s]+\z/ }
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :business_category, presence: true
  
  enum business_type: {
    service_based: 0,
    product_based: 1,
    hybrid: 2
  }
  
  enum business_category: {
    beauty_wellness: 0,
    home_services: 1,
    professional_services: 2,
    fitness_health: 3,
    automotive: 4,
    pet_services: 5,
    consulting: 6,
    other: 99
  }
  
  def display_category
    business_category.humanize.titleize
  end
  
  def full_address
    [street_address, city, state, zip_code].compact.join(', ')
  end
end

# Migration
# rails g migration CreateBusinessProfiles business:references business_name:string business_description:text phone_number:string email:string website_url:string business_type:integer business_category:integer street_address:string city:string state:string zip_code:string country:string
class CreateBusinessProfiles < ActiveRecord::Migration[8.0]
  def change
    create_table :business_profiles do |t|
      t.references :business, null: false, foreign_key: true
      t.string :business_name, null: false
      t.text :business_description
      t.string :phone_number, null: false
      t.string :email, null: false
      t.string :website_url
      t.integer :business_type, default: 0
      t.integer :business_category, null: false
      t.string :street_address
      t.string :city
      t.string :state
      t.string :zip_code
      t.string :country, default: 'US'
      t.text :social_media_links
      t.timestamps
    end
    
    add_index :business_profiles, :business_id, unique: true
    add_index :business_profiles, :business_category
  end
end
```

### Task 2: Create Business Profile Controller
**Implementation Notes:**
- Handle business profile creation and updates
- Include proper authorization and validation
- Support both full page and AJAX updates

```ruby
# app/controllers/admin/business_profile_controller.rb
class Admin::BusinessProfileController < Admin::BaseController
  before_action :authenticate_admin!
  before_action :authorize_business_management!
  before_action :load_business_profile

  def show
    @business_profile = current_admin.business.business_profile || build_default_profile
  end

  def edit
    @business_profile = current_admin.business.business_profile || build_default_profile
  end

  def update
    @business_profile = current_admin.business.business_profile || build_default_profile
    
    if @business_profile.update(business_profile_params)
      track_profile_update
      redirect_to admin_business_profile_path, notice: 'Business profile updated successfully'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def create
    @business_profile = current_admin.business.build_business_profile(business_profile_params)
    
    if @business_profile.save
      track_profile_creation
      redirect_to admin_business_profile_path, notice: 'Business profile created successfully'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def business_profile_params
    params.require(:business_profile).permit(
      :business_name, :business_description, :phone_number, :email,
      :website_url, :business_type, :business_category,
      :street_address, :city, :state, :zip_code, :country,
      social_media_links: []
    )
  end

  def load_business_profile
    @business_profile = current_admin.business.business_profile
  end

  def build_default_profile
    current_admin.business.build_business_profile(
      business_name: current_admin.business.name,
      email: current_admin.email
    )
  end

  def track_profile_update
    Admin::ActivityTrackingService.new(current_admin.business)
                                  .track_business_setting_changed(
                                    'business_profile',
                                    current_admin,
                                    @business_profile.changes
                                  )
  end

  def track_profile_creation
    Admin::ActivityTrackingService.new(current_admin.business)
                                  .track_system_event(
                                    'business_profile_created',
                                    'Business profile information completed',
                                    priority: 'normal'
                                  )
  end
end
```

### Task 3: Create Business Profile Views
**Implementation Notes:**
- Create responsive forms for business information
- Include field validation and error handling
- Support social media links management

```erb
<!-- app/views/admin/business_profile/show.html.erb -->
<div class="max-w-4xl mx-auto p-6">
  <div class="bg-white shadow rounded-lg">
    <div class="px-6 py-4 border-b border-gray-200">
      <div class="flex justify-between items-center">
        <h2 class="text-xl font-semibold text-gray-900">Business Profile</h2>
        <%= link_to "Edit Profile", edit_admin_business_profile_path, 
                    class: "btn btn-primary" %>
      </div>
    </div>
    
    <div class="px-6 py-4">
      <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div>
          <h3 class="text-lg font-medium mb-4">Basic Information</h3>
          <dl class="space-y-3">
            <div>
              <dt class="text-sm font-medium text-gray-500">Business Name</dt>
              <dd class="text-sm text-gray-900"><%= @business_profile.business_name %></dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-gray-500">Category</dt>
              <dd class="text-sm text-gray-900"><%= @business_profile.display_category %></dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-gray-500">Phone</dt>
              <dd class="text-sm text-gray-900"><%= @business_profile.phone_number %></dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-gray-500">Email</dt>
              <dd class="text-sm text-gray-900"><%= @business_profile.email %></dd>
            </div>
            <% if @business_profile.website_url.present? %>
              <div>
                <dt class="text-sm font-medium text-gray-500">Website</dt>
                <dd class="text-sm text-gray-900">
                  <%= link_to @business_profile.website_url, @business_profile.website_url, 
                             target: "_blank", class: "text-blue-600 hover:text-blue-800" %>
                </dd>
              </div>
            <% end %>
          </dl>
        </div>
        
        <div>
          <h3 class="text-lg font-medium mb-4">Location</h3>
          <dl class="space-y-3">
            <div>
              <dt class="text-sm font-medium text-gray-500">Address</dt>
              <dd class="text-sm text-gray-900">
                <%= @business_profile.full_address.presence || "Not provided" %>
              </dd>
            </div>
          </dl>
          
          <% if @business_profile.business_description.present? %>
            <h3 class="text-lg font-medium mb-4 mt-6">Description</h3>
            <p class="text-sm text-gray-700"><%= @business_profile.business_description %></p>
          <% end %>
        </div>
      </div>
    </div>
  </div>
</div>
```

```erb
<!-- app/views/admin/business_profile/edit.html.erb -->
<div class="max-w-4xl mx-auto p-6">
  <div class="bg-white shadow rounded-lg">
    <div class="px-6 py-4 border-b border-gray-200">
      <h2 class="text-xl font-semibold text-gray-900">Edit Business Profile</h2>
    </div>
    
    <%= form_with model: [@business_profile.business, @business_profile], 
                  url: @business_profile.persisted? ? admin_business_profile_path : admin_business_profile_index_path,
                  method: @business_profile.persisted? ? :patch : :post,
                  local: true,
                  class: "px-6 py-4" do |form| %>
      
      <% if @business_profile.errors.any? %>
        <div class="mb-6 bg-red-50 border border-red-200 rounded-md p-4">
          <h3 class="text-sm font-medium text-red-800">Please fix the following errors:</h3>
          <ul class="mt-2 text-sm text-red-700 list-disc list-inside">
            <% @business_profile.errors.full_messages.each do |message| %>
              <li><%= message %></li>
            <% end %>
          </ul>
        </div>
      <% end %>
      
      <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div>
          <h3 class="text-lg font-medium mb-4">Basic Information</h3>
          
          <div class="mb-4">
            <%= form.label :business_name, class: "block text-sm font-medium text-gray-700 mb-2" %>
            <%= form.text_field :business_name, 
                               required: true,
                               class: "w-full border-gray-300 rounded-md shadow-sm focus:border-blue-500 focus:ring-blue-500" %>
          </div>
          
          <div class="mb-4">
            <%= form.label :business_category, class: "block text-sm font-medium text-gray-700 mb-2" %>
            <%= form.select :business_category,
                           options_for_select(BusinessProfile.business_categories.map { |key, value| [key.humanize.titleize, key] }, @business_profile.business_category),
                           { prompt: "Select a category" },
                           { required: true, class: "w-full border-gray-300 rounded-md shadow-sm focus:border-blue-500 focus:ring-blue-500" } %>
          </div>
          
          <div class="mb-4">
            <%= form.label :phone_number, class: "block text-sm font-medium text-gray-700 mb-2" %>
            <%= form.telephone_field :phone_number, 
                                   required: true,
                                   class: "w-full border-gray-300 rounded-md shadow-sm focus:border-blue-500 focus:ring-blue-500" %>
          </div>
          
          <div class="mb-4">
            <%= form.label :email, class: "block text-sm font-medium text-gray-700 mb-2" %>
            <%= form.email_field :email, 
                               required: true,
                               class: "w-full border-gray-300 rounded-md shadow-sm focus:border-blue-500 focus:ring-blue-500" %>
          </div>
          
          <div class="mb-4">
            <%= form.label :website_url, class: "block text-sm font-medium text-gray-700 mb-2" %>
            <%= form.url_field :website_url, 
                             placeholder: "https://",
                             class: "w-full border-gray-300 rounded-md shadow-sm focus:border-blue-500 focus:ring-blue-500" %>
          </div>
        </div>
        
        <div>
          <h3 class="text-lg font-medium mb-4">Location & Details</h3>
          
          <div class="mb-4">
            <%= form.label :street_address, class: "block text-sm font-medium text-gray-700 mb-2" %>
            <%= form.text_field :street_address, 
                              class: "w-full border-gray-300 rounded-md shadow-sm focus:border-blue-500 focus:ring-blue-500" %>
          </div>
          
          <div class="grid grid-cols-2 gap-4 mb-4">
            <div>
              <%= form.label :city, class: "block text-sm font-medium text-gray-700 mb-2" %>
              <%= form.text_field :city, 
                                class: "w-full border-gray-300 rounded-md shadow-sm focus:border-blue-500 focus:ring-blue-500" %>
            </div>
            <div>
              <%= form.label :state, class: "block text-sm font-medium text-gray-700 mb-2" %>
              <%= form.text_field :state, 
                                class: "w-full border-gray-300 rounded-md shadow-sm focus:border-blue-500 focus:ring-blue-500" %>
            </div>
          </div>
          
          <div class="mb-4">
            <%= form.label :zip_code, class: "block text-sm font-medium text-gray-700 mb-2" %>
            <%= form.text_field :zip_code, 
                              class: "w-full border-gray-300 rounded-md shadow-sm focus:border-blue-500 focus:ring-blue-500" %>
          </div>
          
          <div class="mb-4">
            <%= form.label :business_description, class: "block text-sm font-medium text-gray-700 mb-2" %>
            <%= form.text_area :business_description, 
                             rows: 4,
                             placeholder: "Describe your business and services...",
                             class: "w-full border-gray-300 rounded-md shadow-sm focus:border-blue-500 focus:ring-blue-500" %>
          </div>
        </div>
      </div>
      
      <div class="flex justify-end space-x-3 pt-6 border-t border-gray-200">
        <%= link_to "Cancel", admin_business_profile_path, 
                    class: "btn btn-secondary" %>
        <%= form.submit @business_profile.persisted? ? "Update Profile" : "Create Profile", 
                       class: "btn btn-primary" %>
      </div>
    <% end %>
  </div>
</div>
```

### Task 4: Add Routes
**Implementation Notes:**
- Add RESTful routes for business profile management
- Include proper nesting under admin namespace

```ruby
# Add to config/routes.rb
namespace :admin do
  # ...existing routes...
  resource :business_profile, only: [:show, :edit, :update, :create]
end
```

## Acceptance Criteria
- [ ] Business owners can view and edit all core business information
- [ ] Form validation prevents invalid data entry
- [ ] Changes are tracked in the activity log
- [ ] Contact information updates reflect across all customer touchpoints
- [ ] Address validation ensures proper formatting
- [ ] Mobile-responsive interface works on all devices

## Testing Requirements
- Unit tests for BusinessProfile model validations
- Integration tests for controller actions
- Feature tests for form submission workflows
- Validation tests for all required fields
- Activity tracking verification
