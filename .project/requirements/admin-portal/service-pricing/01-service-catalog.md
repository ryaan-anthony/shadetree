# Feature: Service Catalog Management

## Overview
Enable business owners to create, manage, and organize their service offerings with detailed descriptions, durations, and pricing structures.

## User Stories
- As a business owner, I want to create services so customers can request specific offerings
- As a business owner, I want to organize services into categories for easy navigation
- As a staff member, I want to quickly find services when creating quotes

## Tasks

### 1. Create Service Model
**File**: `app/models/service.rb`

**Implementation Notes**:
```ruby
class Service < ApplicationRecord
  belongs_to :business
  belongs_to :service_category, optional: true
  has_many :quote_line_items, dependent: :restrict_with_error
  has_many :service_pricing_tiers, dependent: :destroy
  
  validates :name, presence: true, length: { maximum: 255 }
  validates :description, length: { maximum: 1000 }
  validates :duration_minutes, presence: true, numericality: { greater_than: 0 }
  validates :base_price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  
  scope :active, -> { where(is_active: true) }
  scope :by_category, ->(category) { where(service_category: category) }
  scope :search, ->(term) { where('name ILIKE ? OR description ILIKE ?', "%#{term}%", "%#{term}%") }
  
  enum pricing_type: { fixed: 0, hourly: 1, tiered: 2, custom: 3 }
  
  def formatted_duration
    hours = duration_minutes / 60
    minutes = duration_minutes % 60
    
    if hours > 0 && minutes > 0
      "#{hours}h #{minutes}m"
    elsif hours > 0
      "#{hours}h"
    else
      "#{minutes}m"
    end
  end
  
  def price_for_quantity(quantity = 1)
    case pricing_type
    when 'fixed'
      base_price
    when 'hourly'
      base_price * (duration_minutes / 60.0) * quantity
    when 'tiered'
      calculate_tiered_price(quantity)
    else
      base_price
    end
  end
  
  def can_be_deleted?
    quote_line_items.empty?
  end
  
  private
  
  def calculate_tiered_price(quantity)
    return base_price if service_pricing_tiers.empty?
    
    applicable_tier = service_pricing_tiers
                     .where('min_quantity <= ?', quantity)
                     .order(min_quantity: :desc)
                     .first
    
    applicable_tier&.price || base_price
  end
end
```

### 2. Create ServiceCategory Model
**File**: `app/models/service_category.rb`

**Implementation Notes**:
```ruby
class ServiceCategory < ApplicationRecord
  belongs_to :business
  has_many :services, dependent: :nullify
  
  validates :name, presence: true, length: { maximum: 255 }
  validates :name, uniqueness: { scope: :business_id }
  validates :description, length: { maximum: 500 }
  
  scope :active, -> { where(is_active: true) }
  scope :with_services, -> { joins(:services).where(services: { is_active: true }).distinct }
  
  def services_count
    services.active.count
  end
  
  def can_be_deleted?
    services.empty?
  end
end
```

### 3. Create ServicePricingTier Model
**File**: `app/models/service_pricing_tier.rb`

**Implementation Notes**:
```ruby
class ServicePricingTier < ApplicationRecord
  belongs_to :service
  
  validates :min_quantity, presence: true, numericality: { greater_than: 0 }
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :min_quantity, uniqueness: { scope: :service_id }
  
  scope :ordered, -> { order(:min_quantity) }
  
  def quantity_range
    next_tier = service.service_pricing_tiers
                      .where('min_quantity > ?', min_quantity)
                      .order(:min_quantity)
                      .first
    
    if next_tier
      "#{min_quantity} - #{next_tier.min_quantity - 1}"
    else
      "#{min_quantity}+"
    end
  end
end
```

### 4. Services Controller
**File**: `app/controllers/admin/services_controller.rb`

**Implementation Notes**:
```ruby
class Admin::ServicesController < Admin::BaseController
  before_action :set_business
  before_action :ensure_can_manage_services
  before_action :set_service, only: [:show, :edit, :update, :destroy, :toggle_active]
  
  def index
    @services = @business.services.includes(:service_category, :service_pricing_tiers)
    @services = @services.by_category(params[:category_id]) if params[:category_id].present?
    @services = @services.search(params[:search]) if params[:search].present?
    @services = @services.page(params[:page]).per(20)
    
    @categories = @business.service_categories.active.with_services
    @total_services = @business.services.active.count
  end
  
  def show
  end
  
  def new
    @service = @business.services.build
    @service.service_pricing_tiers.build if @service.tiered?
  end
  
  def create
    @service = @business.services.build(service_params)
    
    if @service.save
      redirect_to admin_services_path, notice: 'Service created successfully.'
    else
      render :new, status: :unprocessable_entity
    end
  end
  
  def edit
  end
  
  def update
    if @service.update(service_params)
      redirect_to admin_service_path(@service), notice: 'Service updated successfully.'
    else
      render :edit, status: :unprocessable_entity
    end
  end
  
  def destroy
    if @service.can_be_deleted?
      @service.destroy
      redirect_to admin_services_path, notice: 'Service deleted successfully.'
    else
      redirect_to admin_services_path, alert: 'Cannot delete service that has been used in quotes.'
    end
  end
  
  def toggle_active
    @service.update!(is_active: !@service.is_active?)
    status = @service.is_active? ? 'activated' : 'deactivated'
    redirect_to admin_services_path, notice: "Service #{status} successfully."
  end
  
  def bulk_actions
    service_ids = params[:service_ids]
    action = params[:bulk_action]
    
    if service_ids.present? && action.present?
      services = @business.services.where(id: service_ids)
      
      case action
      when 'activate'
        services.update_all(is_active: true)
        redirect_to admin_services_path, notice: "#{services.count} services activated."
      when 'deactivate'
        services.update_all(is_active: false)
        redirect_to admin_services_path, notice: "#{services.count} services deactivated."
      when 'delete'
        deletable_services = services.select(&:can_be_deleted?)
        deletable_services.each(&:destroy)
        redirect_to admin_services_path, notice: "#{deletable_services.count} services deleted."
      end
    else
      redirect_to admin_services_path, alert: 'Please select services and an action.'
    end
  end
  
  private
  
  def set_business
    @business = current_user.owned_business || current_user.business
  end
  
  def ensure_can_manage_services
    business_user = current_user.business_users.find_by(business: @business)
    unless business_user&.can_manage_services?
      redirect_to admin_dashboard_path, alert: 'Not authorized to manage services'
    end
  end
  
  def set_service
    @service = @business.services.find(params[:id])
  end
  
  def service_params
    params.require(:service).permit(
      :name, :description, :duration_minutes, :base_price, :pricing_type,
      :service_category_id, :is_active, :requires_site_visit, :can_be_scheduled_online,
      service_pricing_tiers_attributes: [:id, :min_quantity, :price, :_destroy]
    )
  end
end
```

### 5. Service Categories Controller
**File**: `app/controllers/admin/service_categories_controller.rb`

**Implementation Notes**:
```ruby
class Admin::ServiceCategoriesController < Admin::BaseController
  before_action :set_business
  before_action :ensure_can_manage_services
  before_action :set_service_category, only: [:show, :edit, :update, :destroy]
  
  def index
    @service_categories = @business.service_categories.includes(:services).order(:name)
  end
  
  def new
    @service_category = @business.service_categories.build
  end
  
  def create
    @service_category = @business.service_categories.build(service_category_params)
    
    if @service_category.save
      redirect_to admin_service_categories_path, notice: 'Category created successfully.'
    else
      render :new, status: :unprocessable_entity
    end
  end
  
  def edit
  end
  
  def update
    if @service_category.update(service_category_params)
      redirect_to admin_service_categories_path, notice: 'Category updated successfully.'
    else
      render :edit, status: :unprocessable_entity
    end
  end
  
  def destroy
    if @service_category.can_be_deleted?
      @service_category.destroy
      redirect_to admin_service_categories_path, notice: 'Category deleted successfully.'
    else
      redirect_to admin_service_categories_path, alert: 'Cannot delete category that contains services.'
    end
  end
  
  private
  
  def set_business
    @business = current_user.owned_business || current_user.business
  end
  
  def ensure_can_manage_services
    business_user = current_user.business_users.find_by(business: @business)
    unless business_user&.can_manage_services?
      redirect_to admin_dashboard_path, alert: 'Not authorized to manage services'
    end
  end
  
  def set_service_category
    @service_category = @business.service_categories.find(params[:id])
  end
  
  def service_category_params
    params.require(:service_category).permit(:name, :description, :is_active)
  end
end
```

### 6. Services Index View
**File**: `app/views/admin/services/index.html.erb`

**Implementation Notes**:
```erb
<div class="max-w-7xl mx-auto py-8">
  <div class="flex justify-between items-center mb-6">
    <div>
      <h1 class="text-2xl font-bold text-gray-900">Services</h1>
      <p class="text-gray-600"><%= @total_services %> active services</p>
    </div>
    <div class="flex space-x-3">
      <%= link_to "Manage Categories", admin_service_categories_path,
                  class: "bg-gray-600 hover:bg-gray-700 text-white font-medium py-2 px-4 rounded-md" %>
      <%= link_to "New Service", new_admin_service_path,
                  class: "bg-blue-600 hover:bg-blue-700 text-white font-medium py-2 px-4 rounded-md" %>
    </div>
  </div>
  
  <!-- Filters and Search -->
  <div class="bg-white shadow rounded-lg p-4 mb-6">
    <%= form_with url: admin_services_path, method: :get, local: true, 
                  class: "flex flex-wrap items-center gap-4" do |form| %>
      <div class="flex-1 min-w-64">
        <%= form.text_field :search, value: params[:search], placeholder: "Search services...",
                           class: "w-full border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500" %>
      </div>
      <div>
        <%= form.select :category_id,
                       options_from_collection_for_select(@categories, :id, :name, params[:category_id]),
                       { prompt: "All Categories" },
                       { class: "border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500" } %>
      </div>
      <div>
        <%= form.submit "Filter", class: "bg-blue-600 hover:bg-blue-700 text-white font-medium py-2 px-4 rounded-md" %>
      </div>
      <% if params[:search].present? || params[:category_id].present? %>
        <%= link_to "Clear", admin_services_path, class: "text-gray-600 hover:text-gray-900" %>
      <% end %>
    <% end %>
  </div>
  
  <!-- Services List -->
  <div class="bg-white shadow rounded-lg">
    <div class="px-6 py-4 border-b border-gray-200">
      <div class="flex justify-between items-center">
        <h2 class="text-lg font-medium text-gray-900">Service Catalog</h2>
        <div class="flex items-center space-x-2" id="bulk-actions" style="display: none;">
          <%= form_with url: bulk_actions_admin_services_path, method: :patch, local: true, 
                        class: "flex items-center space-x-2" do |form| %>
            <%= form.hidden_field :service_ids, value: "", id: "selected-service-ids" %>
            <%= form.select :bulk_action,
                           [['Activate', 'activate'], ['Deactivate', 'deactivate'], ['Delete', 'delete']],
                           { prompt: "Bulk Actions" },
                           { class: "border-gray-300 rounded-md text-sm" } %>
            <%= form.submit "Apply", class: "bg-blue-600 hover:bg-blue-700 text-white font-medium py-1 px-3 rounded text-sm" %>
          <% end %>
        </div>
      </div>
    </div>
    
    <div class="overflow-x-auto">
      <table class="min-w-full divide-y divide-gray-200">
        <thead class="bg-gray-50">
          <tr>
            <th class="px-6 py-3 text-left">
              <input type="checkbox" id="select-all" class="rounded border-gray-300 text-blue-600 focus:ring-blue-500">
            </th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Service</th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Category</th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Duration</th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Pricing</th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Status</th>
            <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">Actions</th>
          </tr>
        </thead>
        <tbody class="bg-white divide-y divide-gray-200">
          <% @services.each do |service| %>
            <tr class="<%= 'opacity-50' unless service.is_active? %>">
              <td class="px-6 py-4 whitespace-nowrap">
                <input type="checkbox" value="<%= service.id %>" class="service-checkbox rounded border-gray-300 text-blue-600 focus:ring-blue-500">
              </td>
              <td class="px-6 py-4">
                <div class="text-sm font-medium text-gray-900"><%= service.name %></div>
                <div class="text-sm text-gray-500"><%= truncate(service.description, length: 60) %></div>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                <%= service.service_category&.name || "Uncategorized" %>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                <%= service.formatted_duration %>
              </td>
              <td class="px-6 py-4 whitespace-nowrap">
                <div class="text-sm text-gray-900">
                  <%= number_to_currency(service.base_price) %>
                  <span class="text-gray-500">(<%= service.pricing_type.titleize %>)</span>
                </div>
              </td>
              <td class="px-6 py-4 whitespace-nowrap">
                <span class="inline-flex px-2 py-1 text-xs font-semibold rounded-full 
                  <%= service.is_active? ? 'bg-green-100 text-green-800' : 'bg-gray-100 text-gray-800' %>">
                  <%= service.is_active? ? 'Active' : 'Inactive' %>
                </span>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                <%= link_to "View", admin_service_path(service), class: "text-blue-600 hover:text-blue-900 mr-3" %>
                <%= link_to "Edit", edit_admin_service_path(service), class: "text-blue-600 hover:text-blue-900 mr-3" %>
                <%= link_to service.is_active? ? "Deactivate" : "Activate", 
                            toggle_active_admin_service_path(service), method: :patch,
                            class: "text-yellow-600 hover:text-yellow-900 mr-3" %>
                <% if service.can_be_deleted? %>
                  <%= link_to "Delete", admin_service_path(service), method: :delete,
                              confirm: "Are you sure you want to delete this service?",
                              class: "text-red-600 hover:text-red-900" %>
                <% end %>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    
    <% if @services.respond_to?(:current_page) %>
      <div class="px-6 py-4 border-t border-gray-200">
        <%= paginate @services %>
      </div>
    <% end %>
  </div>
</div>

<script data-turbo-track="reload">
  // Handle bulk selection and actions
  document.addEventListener('DOMContentLoaded', function() {
    const selectAllCheckbox = document.getElementById('select-all');
    const serviceCheckboxes = document.querySelectorAll('.service-checkbox');
    const bulkActions = document.getElementById('bulk-actions');
    const selectedIdsField = document.getElementById('selected-service-ids');
    
    function updateBulkActions() {
      const checkedBoxes = document.querySelectorAll('.service-checkbox:checked');
      const selectedIds = Array.from(checkedBoxes).map(cb => cb.value);
      
      if (selectedIds.length > 0) {
        bulkActions.style.display = 'flex';
        selectedIdsField.value = selectedIds.join(',');
      } else {
        bulkActions.style.display = 'none';
        selectedIdsField.value = '';
      }
    }
    
    selectAllCheckbox.addEventListener('change', function() {
      serviceCheckboxes.forEach(checkbox => {
        checkbox.checked = this.checked;
      });
      updateBulkActions();
    });
    
    serviceCheckboxes.forEach(checkbox => {
      checkbox.addEventListener('change', updateBulkActions);
    });
  });
</script>
```

## Acceptance Criteria
- [ ] Business owners can create services with detailed information
- [ ] Services can be organized into categories
- [ ] Different pricing types (fixed, hourly, tiered) are supported
- [ ] Services can be activated/deactivated without deletion
- [ ] Bulk actions work for multiple services
- [ ] Search and filtering help find services quickly
- [ ] Services used in quotes cannot be deleted

## Testing Requirements
- Model validations for services and categories
- Pricing calculation tests for all pricing types
- Controller tests for CRUD operations
- Authorization tests for service management
- Bulk action functionality tests
