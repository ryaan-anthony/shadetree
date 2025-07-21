# Feature: Multi-Business Management

## Overview
Enable users to create, manage, and switch between multiple business entities within a single account, supporting entrepreneurs who operate multiple service businesses or franchises.

## User Stories
- As a business owner, I want to create multiple business profiles so I can manage different service companies
- As a franchise owner, I want to manage multiple locations with separate configurations
- As a user, I want to easily switch between my businesses without logging out
- As a business owner, I want to maintain separate staff, services, and customers for each business

## Tasks

### 1. Extend User Model for Multi-Business Support
**File**: `app/models/user.rb`

**Implementation Notes**:
```ruby
class User < ApplicationRecord
  has_many :business_ownerships, dependent: :destroy
  has_many :businesses, through: :business_ownerships
  has_many :owned_businesses, -> { where(business_ownerships: { role: 'owner' }) }, 
           through: :business_ownerships, source: :business
  
  validates :email, presence: true, uniqueness: true
  
  def can_create_business?
    # Could add subscription-based limits here
    businesses.count < 10
  end
  
  def primary_business
    business_ownerships.find_by(is_primary: true)&.business || businesses.first
  end
  
  def set_primary_business(business)
    return false unless businesses.include?(business)
    
    transaction do
      business_ownerships.update_all(is_primary: false)
      business_ownerships.find_by(business: business).update!(is_primary: true)
    end
  end
end
```

### 2. Create BusinessOwnership Join Model
**File**: `app/models/business_ownership.rb`

**Implementation Notes**:
```ruby
class BusinessOwnership < ApplicationRecord
  belongs_to :user
  belongs_to :business
  
  validates :user_id, uniqueness: { scope: :business_id }
  validates :role, presence: true
  validate :only_one_primary_per_user
  
  enum role: { owner: 0, admin: 1, manager: 2 }
  
  scope :primary, -> { where(is_primary: true) }
  
  private
  
  def only_one_primary_per_user
    return unless is_primary?
    
    existing_primary = user.business_ownerships.primary.where.not(id: id)
    if existing_primary.exists?
      errors.add(:is_primary, "User can only have one primary business")
    end
  end
end
```

### 3. Update Business Model
**File**: `app/models/business.rb`

**Implementation Notes**:
```ruby
class Business < ApplicationRecord
  has_many :business_ownerships, dependent: :destroy
  has_many :users, through: :business_ownerships
  has_many :staff_members, dependent: :destroy
  has_many :services, dependent: :destroy
  has_many :service_categories, dependent: :destroy
  has_many :customers, dependent: :destroy
  has_many :quotes, dependent: :destroy
  has_many :price_lists, dependent: :destroy
  has_many :quote_templates, dependent: :destroy
  
  validates :name, presence: true, length: { maximum: 255 }
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9-]+\z/ }
  validates :business_type, presence: true
  
  enum business_type: { 
    landscaping: 0, 
    lawn_care: 1, 
    tree_service: 2, 
    irrigation: 3, 
    general_contractor: 4,
    other: 99 
  }
  
  enum status: { active: 0, suspended: 1, archived: 2 }
  
  before_validation :generate_slug, if: -> { name.present? && slug.blank? }
  
  scope :active, -> { where(status: :active) }
  
  def owners
    users.joins(:business_ownerships).where(business_ownerships: { role: 'owner' })
  end
  
  def primary_owner
    owners.joins(:business_ownerships).find_by(business_ownerships: { is_primary: true }) || owners.first
  end
  
  private
  
  def generate_slug
    base_slug = name.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/-+/, '-').strip('-')
    counter = 1
    potential_slug = base_slug
    
    while Business.where(slug: potential_slug).where.not(id: id).exists?
      potential_slug = "#{base_slug}-#{counter}"
      counter += 1
    end
    
    self.slug = potential_slug
  end
end
```

### 4. Create Business Creation Controller
**File**: `app/controllers/admin/businesses_controller.rb`

**Implementation Notes**:
```ruby
class Admin::BusinessesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_business, only: [:show, :edit, :update, :destroy, :switch_to]
  
  def index
    @businesses = current_user.businesses.includes(:business_ownerships)
    @current_business = current_user.primary_business
  end
  
  def show
    @business = current_business
  end
  
  def new
    unless current_user.can_create_business?
      redirect_to admin_businesses_path, alert: "Maximum number of businesses reached"
      return
    end
    
    @business = Business.new
  end
  
  def create
    unless current_user.can_create_business?
      redirect_to admin_businesses_path, alert: "Maximum number of businesses reached"
      return
    end
    
    @business = Business.new(business_params)
    
    if @business.save
      # Create ownership relationship
      BusinessOwnership.create!(
        user: current_user,
        business: @business,
        role: 'owner',
        is_primary: current_user.businesses.empty?
      )
      
      # Set up default data for new business
      BusinessSetupService.new(@business).call
      
      redirect_to admin_business_path(@business), notice: "Business created successfully!"
    else
      render :new, status: :unprocessable_entity
    end
  end
  
  def edit
  end
  
  def update
    if @business.update(business_params)
      redirect_to admin_business_path(@business), notice: "Business updated successfully!"
    else
      render :edit, status: :unprocessable_entity
    end
  end
  
  def switch_to
    current_user.set_primary_business(@business)
    session[:current_business_id] = @business.id
    redirect_to admin_dashboard_path, notice: "Switched to #{@business.name}"
  end
  
  def destroy
    if current_user.businesses.count == 1
      redirect_to admin_businesses_path, alert: "Cannot delete your only business"
      return
    end
    
    if @business.primary_owner == current_user && @business.owners.count == 1
      @business.destroy
      # Switch to another business if this was primary
      if current_user.primary_business == @business
        current_user.set_primary_business(current_user.businesses.first)
      end
      redirect_to admin_businesses_path, notice: "Business deleted successfully"
    else
      redirect_to admin_businesses_path, alert: "Cannot delete business with other owners"
    end
  end
  
  private
  
  def set_business
    @business = current_user.businesses.find(params[:id])
  end
  
  def business_params
    params.require(:business).permit(
      :name, :business_type, :phone, :email, :website,
      :address_line_1, :address_line_2, :city, :state, :zip_code,
      :description, :logo
    )
  end
end
```

### 5. Add Business Context Helper
**File**: `app/controllers/concerns/business_context.rb`

**Implementation Notes**:
```ruby
module BusinessContext
  extend ActiveSupport::Concern
  
  included do
    before_action :set_current_business
    helper_method :current_business
  end
  
  private
  
  def set_current_business
    @current_business ||= find_current_business
  end
  
  def current_business
    @current_business
  end
  
  def find_current_business
    # Try session first (for business switching)
    if session[:current_business_id]
      business = current_user.businesses.find_by(id: session[:current_business_id])
      return business if business
    end
    
    # Fall back to primary business
    current_user.primary_business
  end
  
  def require_business
    unless current_business
      redirect_to new_admin_business_path, alert: "Please create a business first"
    end
  end
end
```

### 6. Create Business Setup Service
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
    end
  end
  
  private
  
  attr_reader :business
  
  def create_default_service_categories
    default_categories = [
      { name: "Lawn Care", description: "Mowing, edging, and basic lawn maintenance", color_code: "#10B981" },
      { name: "Landscaping", description: "Design and installation services", color_code: "#8B5CF6" },
      { name: "Tree Services", description: "Tree trimming, removal, and care", color_code: "#F59E0B" },
      { name: "Irrigation", description: "Sprinkler systems and water management", color_code: "#3B82F6" }
    ]
    
    default_categories.each do |category_attrs|
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
end
```

### 7. Add Database Migrations
**File**: `db/migrate/[timestamp]_create_business_ownerships.rb`

**Implementation Notes**:
```ruby
class CreateBusinessOwnerships < ActiveRecord::Migration[8.0]
  def change
    create_table :business_ownerships do |t|
      t.references :user, null: false, foreign_key: true
      t.references :business, null: false, foreign_key: true
      t.integer :role, null: false, default: 0
      t.boolean :is_primary, default: false
      t.datetime :joined_at, default: -> { 'CURRENT_TIMESTAMP' }
      
      t.timestamps
    end
    
    add_index :business_ownerships, [:user_id, :business_id], unique: true
    add_index :business_ownerships, [:user_id, :is_primary], where: 'is_primary = true'
  end
end
```

**File**: `db/migrate/[timestamp]_add_slug_to_businesses.rb`

**Implementation Notes**:
```ruby
class AddSlugToBusinesses < ActiveRecord::Migration[8.0]
  def change
    add_column :businesses, :slug, :string
    add_column :businesses, :status, :integer, default: 0
    add_column :businesses, :business_type, :integer
    
    add_index :businesses, :slug, unique: true
    add_index :businesses, :status
  end
end
```

### 8. Update Routes
**File**: `config/routes.rb`

**Implementation Notes**:
```ruby
Rails.application.routes.draw do
  namespace :admin do
    resources :businesses do
      member do
        patch :switch_to
      end
    end
    
    # Existing admin routes should be scoped to current business
    scope ':business_slug', constraints: { business_slug: /[a-z0-9-]+/ } do
      resources :staff_members
      resources :services
      resources :quotes
      # ... other business-scoped routes
    end
  end
end
```

## Business Context Integration

All existing admin controllers should include the `BusinessContext` concern and scope data to the current business:

**Example Controller Update**:
```ruby
class Admin::StaffMembersController < ApplicationController
  include BusinessContext
  
  before_action :require_business
  
  def index
    @staff_members = current_business.staff_members.includes(:user)
  end
  
  # ... rest of controller
end
```

## UI Components

The admin navigation should include a business switcher dropdown that shows all businesses the user has access to, with the ability to create new businesses and switch between existing ones.

## Security Considerations

- All business data must be properly scoped to prevent cross-business data access
- Business ownership verification on all admin actions
- Audit logging for business creation/deletion
- Role-based permissions within each business context
