# Feature: Pricing Configuration

## Overview
Enable business owners to set up flexible pricing models, manage price lists, and configure automatic pricing rules for their services.

## User Stories
- As a business owner, I want to set different pricing tiers so I can offer volume discounts
- As a business owner, I want to create price lists for different customer types
- As a business owner, I want to set up automatic pricing rules to streamline quote generation

## Tasks

### 1. Create PriceList Model
**File**: `app/models/price_list.rb`

**Implementation Notes**:
```ruby
class PriceList < ApplicationRecord
  belongs_to :business
  has_many :price_list_items, dependent: :destroy
  has_many :services, through: :price_list_items
  
  validates :name, presence: true, length: { maximum: 255 }
  validates :name, uniqueness: { scope: :business_id }
  validates :effective_date, presence: true
  validate :effective_date_not_in_past, on: :create
  validate :end_date_after_effective_date
  
  scope :active, -> { where(is_active: true) }
  scope :current, -> { where('effective_date <= ? AND (end_date IS NULL OR end_date >= ?)', Date.current, Date.current) }
  scope :for_customer_type, ->(customer_type) { where(customer_type: customer_type) }
  
  enum customer_type: { standard: 0, preferred: 1, commercial: 2, wholesale: 3 }
  enum discount_type: { percentage: 0, fixed_amount: 1, tiered: 2 }
  
  def current?
    Date.current >= effective_date && (end_date.nil? || Date.current <= end_date)
  end
  
  def apply_discount_to_price(base_price, quantity = 1)
    case discount_type
    when 'percentage'
      base_price * (1 - (discount_percentage / 100.0))
    when 'fixed_amount'
      [base_price - discount_amount, 0].max
    when 'tiered'
      apply_tiered_discount(base_price, quantity)
    else
      base_price
    end
  end
  
  def price_for_service(service, quantity = 1)
    price_list_item = price_list_items.find_by(service: service)
    
    if price_list_item
      price_list_item.calculate_price(quantity)
    else
      apply_discount_to_price(service.base_price, quantity)
    end
  end
  
  private
  
  def effective_date_not_in_past
    return unless effective_date
    
    if effective_date < Date.current
      errors.add(:effective_date, "cannot be in the past")
    end
  end
  
  def end_date_after_effective_date
    return unless effective_date && end_date
    
    if end_date < effective_date
      errors.add(:end_date, "must be after effective date")
    end
  end
  
  def apply_tiered_discount(base_price, quantity)
    # Implementation would use tiered discount rules
    base_price
  end
end
```

### 2. Create PriceListItem Model
**File**: `app/models/price_list_item.rb`

**Implementation Notes**:
```ruby
class PriceListItem < ApplicationRecord
  belongs_to :price_list
  belongs_to :service
  
  validates :service_id, uniqueness: { scope: :price_list_id }
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validate :price_different_from_base_price
  
  def calculate_price(quantity = 1)
    case price_list.discount_type
    when 'percentage'
      service.base_price * (1 - (discount_percentage / 100.0))
    when 'fixed_amount'
      price
    else
      price
    end
  end
  
  def discount_amount
    return 0 unless service
    service.base_price - price
  end
  
  def discount_percentage
    return 0 unless service && service.base_price > 0
    ((service.base_price - price) / service.base_price * 100).round(2)
  end
  
  private
  
  def price_different_from_base_price
    return unless service && price
    
    if price == service.base_price
      errors.add(:price, "should be different from base price to justify a price list")
    end
  end
end
```

### 3. Create PricingRule Model
**File**: `app/models/pricing_rule.rb`

**Implementation Notes**:
```ruby
class PricingRule < ApplicationRecord
  belongs_to :business
  belongs_to :service, optional: true
  belongs_to :service_category, optional: true
  
  validates :name, presence: true
  validates :rule_type, presence: true
  validates :condition_field, presence: true
  validates :condition_operator, presence: true
  validates :condition_value, presence: true
  validates :action_type, presence: true
  validates :action_value, presence: true
  
  enum rule_type: { quantity_based: 0, date_based: 1, customer_based: 2, service_based: 3 }
  enum condition_operator: { equals: 0, greater_than: 1, less_than: 2, between: 3, in_list: 4 }
  enum action_type: { percentage_discount: 0, fixed_discount: 1, fixed_price: 2, percentage_markup: 3 }
  
  scope :active, -> { where(is_active: true) }
  scope :for_service, ->(service) { where(service: service) }
  scope :for_category, ->(category) { where(service_category: category) }
  
  def applies_to_service?(service)
    return false unless is_active?
    
    if self.service.present?
      self.service == service
    elsif service_category.present?
      service.service_category == service_category
    else
      true # Global rule
    end
  end
  
  def calculate_adjusted_price(base_price, context = {})
    return base_price unless condition_met?(context)
    
    case action_type
    when 'percentage_discount'
      base_price * (1 - (action_value / 100.0))
    when 'fixed_discount'
      [base_price - action_value, 0].max
    when 'fixed_price'
      action_value
    when 'percentage_markup'
      base_price * (1 + (action_value / 100.0))
    else
      base_price
    end
  end
  
  def condition_met?(context)
    value = context[condition_field.to_sym]
    return false unless value
    
    case condition_operator
    when 'equals'
      value == condition_value
    when 'greater_than'
      value > condition_value
    when 'less_than'
      value < condition_value
    when 'between'
      range = condition_value.split(',').map(&:to_f)
      value >= range[0] && value <= range[1]
    when 'in_list'
      condition_value.split(',').include?(value.to_s)
    else
      false
    end
  end
end
```

### 4. Pricing Configuration Controller
**File**: `app/controllers/admin/pricing_controller.rb`

**Implementation Notes**:
```ruby
class Admin::PricingController < Admin::BaseController
  before_action :set_business
  before_action :ensure_can_manage_services
  
  def index
    @price_lists = @business.price_lists.includes(:price_list_items, :services).order(:name)
    @pricing_rules = @business.pricing_rules.active.includes(:service, :service_category).order(:name)
    @services_count = @business.services.active.count
  end
  
  def price_calculator
    @services = @business.services.active.includes(:service_category)
    @price_lists = @business.price_lists.active.current
    
    if params[:service_id].present? && params[:quantity].present?
      @selected_service = @business.services.find(params[:service_id])
      @quantity = params[:quantity].to_i
      @pricing_breakdown = calculate_pricing_breakdown(@selected_service, @quantity)
    end
  end
  
  private
  
  def set_business
    @business = current_user.owned_business || current_user.business
  end
  
  def ensure_can_manage_services
    business_user = current_user.business_users.find_by(business: @business)
    unless business_user&.can_manage_services?
      redirect_to admin_dashboard_path, alert: 'Not authorized to manage pricing'
    end
  end
  
  def calculate_pricing_breakdown(service, quantity)
    base_price = service.base_price
    final_price = base_price
    applied_rules = []
    
    # Apply pricing rules
    @business.pricing_rules.active.each do |rule|
      next unless rule.applies_to_service?(service)
      
      context = { quantity: quantity, service_id: service.id }
      adjusted_price = rule.calculate_adjusted_price(final_price, context)
      
      if adjusted_price != final_price
        applied_rules << {
          rule: rule,
          original_price: final_price,
          adjusted_price: adjusted_price,
          discount: final_price - adjusted_price
        }
        final_price = adjusted_price
      end
    end
    
    # Check price lists
    price_list_prices = @business.price_lists.active.current.map do |price_list|
      {
        price_list: price_list,
        price: price_list.price_for_service(service, quantity)
      }
    end
    
    {
      base_price: base_price,
      final_price: final_price,
      total_discount: base_price - final_price,
      applied_rules: applied_rules,
      price_list_prices: price_list_prices
    }
  end
end
```

### 5. Price Lists Controller
**File**: `app/controllers/admin/price_lists_controller.rb`

**Implementation Notes**:
```ruby
class Admin::PriceListsController < Admin::BaseController
  before_action :set_business
  before_action :ensure_can_manage_services
  before_action :set_price_list, only: [:show, :edit, :update, :destroy, :duplicate]
  
  def index
    @price_lists = @business.price_lists.includes(:price_list_items).order(:name)
  end
  
  def show
    @price_list_items = @price_list.price_list_items.includes(:service).order('services.name')
  end
  
  def new
    @price_list = @business.price_lists.build
    @services = @business.services.active.order(:name)
  end
  
  def create
    @price_list = @business.price_lists.build(price_list_params)
    
    if @price_list.save
      create_price_list_items if params[:selected_services].present?
      redirect_to admin_price_list_path(@price_list), notice: 'Price list created successfully.'
    else
      @services = @business.services.active.order(:name)
      render :new, status: :unprocessable_entity
    end
  end
  
  def edit
    @services = @business.services.active.order(:name)
    @price_list_items = @price_list.price_list_items.includes(:service)
  end
  
  def update
    if @price_list.update(price_list_params)
      update_price_list_items if params[:price_list_items].present?
      redirect_to admin_price_list_path(@price_list), notice: 'Price list updated successfully.'
    else
      @services = @business.services.active.order(:name)
      render :edit, status: :unprocessable_entity
    end
  end
  
  def destroy
    @price_list.destroy
    redirect_to admin_price_lists_path, notice: 'Price list deleted successfully.'
  end
  
  def duplicate
    new_price_list = @price_list.dup
    new_price_list.name = "#{@price_list.name} (Copy)"
    new_price_list.effective_date = Date.current
    new_price_list.end_date = nil
    
    if new_price_list.save
      # Duplicate price list items
      @price_list.price_list_items.each do |item|
        new_price_list.price_list_items.create!(
          service: item.service,
          price: item.price
        )
      end
      
      redirect_to edit_admin_price_list_path(new_price_list), 
                  notice: 'Price list duplicated successfully.'
    else
      redirect_to admin_price_lists_path, alert: 'Failed to duplicate price list.'
    end
  end
  
  private
  
  def set_business
    @business = current_user.owned_business || current_user.business
  end
  
  def ensure_can_manage_services
    business_user = current_user.business_users.find_by(business: @business)
    unless business_user&.can_manage_services?
      redirect_to admin_dashboard_path, alert: 'Not authorized to manage pricing'
    end
  end
  
  def set_price_list
    @price_list = @business.price_lists.find(params[:id])
  end
  
  def price_list_params
    params.require(:price_list).permit(:name, :description, :customer_type, :discount_type,
                                      :discount_percentage, :discount_amount, :effective_date,
                                      :end_date, :is_active)
  end
  
  def create_price_list_items
    service_ids = params[:selected_services].reject(&:blank?)
    
    service_ids.each do |service_id|
      service = @business.services.find(service_id)
      price_params = params[:service_prices][service_id]
      
      @price_list.price_list_items.create!(
        service: service,
        price: price_params[:price].presence || service.base_price
      )
    end
  end
  
  def update_price_list_items
    params[:price_list_items].each do |item_id, item_params|
      if item_id == 'new'
        # Create new item
        service = @business.services.find(item_params[:service_id])
        @price_list.price_list_items.create!(
          service: service,
          price: item_params[:price]
        )
      else
        # Update existing item
        item = @price_list.price_list_items.find(item_id)
        if item_params[:_destroy] == '1'
          item.destroy
        else
          item.update!(price: item_params[:price])
        end
      end
    end
  end
end
```

### 6. Pricing Configuration View
**File**: `app/views/admin/pricing/index.html.erb`

**Implementation Notes**:
```erb
<div class="max-w-7xl mx-auto py-8">
  <div class="flex justify-between items-center mb-6">
    <h1 class="text-2xl font-bold text-gray-900">Pricing Configuration</h1>
    <div class="flex space-x-3">
      <%= link_to "Price Calculator", price_calculator_admin_pricing_path,
                  class: "bg-green-600 hover:bg-green-700 text-white font-medium py-2 px-4 rounded-md" %>
      <%= link_to "New Price List", new_admin_price_list_path,
                  class: "bg-blue-600 hover:bg-blue-700 text-white font-medium py-2 px-4 rounded-md" %>
    </div>
  </div>
  
  <!-- Price Lists Section -->
  <div class="bg-white shadow rounded-lg mb-8">
    <div class="px-6 py-4 border-b border-gray-200">
      <h2 class="text-lg font-medium text-gray-900">Price Lists</h2>
      <p class="text-sm text-gray-600">Manage different pricing for customer types</p>
    </div>
    
    <div class="p-6">
      <% if @price_lists.any? %>
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          <% @price_lists.each do |price_list| %>
            <div class="border border-gray-200 rounded-lg p-4 hover:shadow-md transition-shadow">
              <div class="flex justify-between items-start mb-3">
                <h3 class="text-lg font-medium text-gray-900"><%= price_list.name %></h3>
                <span class="inline-flex px-2 py-1 text-xs font-semibold rounded-full 
                  <%= price_list.current? ? 'bg-green-100 text-green-800' : 'bg-gray-100 text-gray-800' %>">
                  <%= price_list.current? ? 'Current' : 'Inactive' %>
                </span>
              </div>
              
              <div class="text-sm text-gray-600 mb-3">
                <p><strong>Customer Type:</strong> <%= price_list.customer_type.titleize %></p>
                <p><strong>Items:</strong> <%= price_list.price_list_items.count %> services</p>
                <p><strong>Effective:</strong> <%= price_list.effective_date.strftime('%B %d, %Y') %></p>
              </div>
              
              <div class="flex justify-between items-center">
                <%= link_to "View", admin_price_list_path(price_list),
                            class: "text-blue-600 hover:text-blue-900 text-sm font-medium" %>
                <%= link_to "Edit", edit_admin_price_list_path(price_list),
                            class: "text-blue-600 hover:text-blue-900 text-sm font-medium" %>
                <%= link_to "Duplicate", duplicate_admin_price_list_path(price_list), method: :post,
                            class: "text-green-600 hover:text-green-900 text-sm font-medium" %>
              </div>
            </div>
          <% end %>
        </div>
      <% else %>
        <div class="text-center py-8">
          <p class="text-gray-500 mb-4">No price lists created yet</p>
          <%= link_to "Create Your First Price List", new_admin_price_list_path,
                      class: "bg-blue-600 hover:bg-blue-700 text-white font-medium py-2 px-4 rounded-md" %>
        </div>
      <% end %>
    </div>
  </div>
  
  <!-- Pricing Rules Section -->
  <div class="bg-white shadow rounded-lg">
    <div class="px-6 py-4 border-b border-gray-200">
      <div class="flex justify-between items-center">
        <div>
          <h2 class="text-lg font-medium text-gray-900">Pricing Rules</h2>
          <p class="text-sm text-gray-600">Automatic pricing adjustments based on conditions</p>
        </div>
        <%= link_to "New Pricing Rule", new_admin_pricing_rule_path,
                    class: "bg-blue-600 hover:bg-blue-700 text-white font-medium py-2 px-4 rounded-md" %>
      </div>
    </div>
    
    <div class="p-6">
      <% if @pricing_rules.any? %>
        <div class="space-y-4">
          <% @pricing_rules.each do |rule| %>
            <div class="border border-gray-200 rounded-lg p-4">
              <div class="flex justify-between items-start">
                <div>
                  <h3 class="text-sm font-medium text-gray-900"><%= rule.name %></h3>
                  <p class="text-sm text-gray-600 mt-1">
                    <strong>Type:</strong> <%= rule.rule_type.humanize %> |
                    <strong>Action:</strong> <%= rule.action_type.humanize %> (<%= rule.action_value %>)
                  </p>
                  <% if rule.service %>
                    <p class="text-xs text-gray-500 mt-1">Applies to: <%= rule.service.name %></p>
                  <% elsif rule.service_category %>
                    <p class="text-xs text-gray-500 mt-1">Applies to: <%= rule.service_category.name %> category</p>
                  <% else %>
                    <p class="text-xs text-gray-500 mt-1">Applies to: All services</p>
                  <% end %>
                </div>
                <div class="flex space-x-2">
                  <%= link_to "Edit", edit_admin_pricing_rule_path(rule),
                              class: "text-blue-600 hover:text-blue-900 text-sm" %>
                  <%= link_to "Delete", admin_pricing_rule_path(rule), method: :delete,
                              confirm: "Are you sure?",
                              class: "text-red-600 hover:text-red-900 text-sm" %>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      <% else %>
        <div class="text-center py-8">
          <p class="text-gray-500 mb-4">No pricing rules configured</p>
          <%= link_to "Create Your First Rule", new_admin_pricing_rule_path,
                      class: "bg-blue-600 hover:bg-blue-700 text-white font-medium py-2 px-4 rounded-md" %>
        </div>
      <% end %>
    </div>
  </div>
</div>
```

## Acceptance Criteria
- [ ] Business owners can create price lists for different customer types
- [ ] Price list items can be individually configured per service
- [ ] Pricing rules automatically adjust prices based on conditions
- [ ] Price calculator shows breakdown of all pricing factors
- [ ] Price lists can be duplicated and have effective date ranges
- [ ] Multiple pricing rules can be applied in sequence

## Testing Requirements
- Model validations for price lists and pricing rules
- Price calculation tests for all discount types
- Rule application tests with various conditions
- Controller tests for price list management
- Integration tests for pricing calculator
