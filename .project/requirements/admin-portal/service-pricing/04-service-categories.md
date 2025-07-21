# Feature: Service Categories

## Overview
Enable business owners to organize their services into logical categories for better organization, easier navigation, and improved quote generation workflow.

## User Stories
- As a business owner, I want to organize services into categories so customers can easily find what they need
- As a business owner, I want to apply category-wide pricing rules for efficient management
- As a staff member, I want to filter services by category when creating quotes

## Tasks

### 1. Extend ServiceCategory Model (Already Created)
**File**: `app/models/service_category.rb` (enhancement)

**Implementation Notes**:
```ruby
class ServiceCategory < ApplicationRecord
  # ...existing code...
  
  # Add color coding for visual organization
  validates :color_code, format: { with: /\A#[0-9a-fA-F]{6}\z/ }, allow_blank: true
  
  # Add category-specific settings
  def default_duration_minutes
    services.active.average(:duration_minutes)&.to_i || 60
  end
  
  def average_price
    services.active.average(:base_price) || 0
  end
  
  def most_popular_service
    # This would need to be connected to actual usage data
    services.active.first
  end
  
  def self.with_stats
    includes(:services)
      .left_joins(:services)
      .group('service_categories.id')
      .select('service_categories.*, 
               COUNT(services.id) as services_count,
               AVG(services.base_price) as avg_price,
               AVG(services.duration_minutes) as avg_duration')
  end
end
```

### 2. Create CategoryTemplate Model
**File**: `app/models/category_template.rb`

**Implementation Notes**:
```ruby
class CategoryTemplate < ApplicationRecord
  belongs_to :service_category
  
  validates :template_name, presence: true
  validates :description_template, presence: true
  
  def render_for_service(service)
    template = description_template.dup
    
    # Replace placeholders with service-specific data
    template.gsub!('{{service_name}}', service.name)
    template.gsub!('{{duration}}', service.formatted_duration)
    template.gsub!('{{price}}', ActionController::Base.helpers.number_to_currency(service.base_price))
    template.gsub!('{{category}}', service_category.name)
    
    template
  end
end
```

### 3. Enhanced Service Categories Controller
**File**: `app/controllers/admin/service_categories_controller.rb` (replacement)

**Implementation Notes**:
```ruby
class Admin::ServiceCategoriesController < Admin::BaseController
  before_action :set_business
  before_action :ensure_can_manage_services
  before_action :set_service_category, only: [:show, :edit, :update, :destroy, :reorder_services]
  
  def index
    @service_categories = @business.service_categories
                                  .with_stats
                                  .order(:display_order, :name)
    @uncategorized_services = @business.services.where(service_category: nil).count
    @total_services = @business.services.active.count
  end
  
  def show
    @services = @service_category.services.active.order(:name)
    @category_stats = calculate_category_stats
  end
  
  def new
    @service_category = @business.service_categories.build
    @next_display_order = @business.service_categories.maximum(:display_order).to_i + 1
  end
  
  def create
    @service_category = @business.service_categories.build(service_category_params)
    @service_category.display_order = @business.service_categories.maximum(:display_order).to_i + 1
    
    if @service_category.save
      create_default_templates if params[:create_templates]
      redirect_to admin_service_categories_path, notice: 'Category created successfully.'
    else
      @next_display_order = @business.service_categories.maximum(:display_order).to_i + 1
      render :new, status: :unprocessable_entity
    end
  end
  
  def edit
    @services = @service_category.services.order(:name)
  end
  
  def update
    if @service_category.update(service_category_params)
      redirect_to admin_service_category_path(@service_category), notice: 'Category updated successfully.'
    else
      @services = @service_category.services.order(:name)
      render :edit, status: :unprocessable_entity
    end
  end
  
  def destroy
    if @service_category.can_be_deleted?
      @service_category.destroy
      redirect_to admin_service_categories_path, notice: 'Category deleted successfully.'
    else
      redirect_to admin_service_categories_path, 
                  alert: 'Cannot delete category that contains services. Move services to another category first.'
    end
  end
  
  def reorder
    params[:category_order].each_with_index do |category_id, index|
      @business.service_categories.find(category_id).update!(display_order: index + 1)
    end
    
    head :ok
  end
  
  def reorder_services
    return unless params[:service_order]
    
    params[:service_order].each_with_index do |service_id, index|
      service = @service_category.services.find(service_id)
      service.update!(display_order: index + 1)
    end
    
    head :ok
  end
  
  def move_services
    source_category = @business.service_categories.find(params[:source_category_id])
    target_category = if params[:target_category_id].present?
                       @business.service_categories.find(params[:target_category_id])
                     else
                       nil # Move to uncategorized
                     end
    
    service_ids = params[:service_ids] || []
    services = source_category.services.where(id: service_ids)
    
    services.update_all(service_category_id: target_category&.id)
    
    redirect_to admin_service_categories_path, 
                notice: "#{services.count} services moved successfully."
  end
  
  def bulk_assign
    service_ids = params[:service_ids] || []
    target_category = params[:target_category_id].present? ? 
                     @business.service_categories.find(params[:target_category_id]) : nil
    
    @business.services.where(id: service_ids)
             .update_all(service_category_id: target_category&.id)
    
    redirect_to admin_service_categories_path,
                notice: "#{service_ids.count} services assigned to category."
  end
  
  private
  
  def set_business
    @business = current_user.owned_business || current_user.business
  end
  
  def ensure_can_manage_services
    business_user = current_user.business_users.find_by(business: @business)
    unless business_user&.can_manage_services?
      redirect_to admin_dashboard_path, alert: 'Not authorized to manage categories'
    end
  end
  
  def set_service_category
    @service_category = @business.service_categories.find(params[:id])
  end
  
  def service_category_params
    params.require(:service_category).permit(:name, :description, :color_code, 
                                            :is_active, :display_order, :icon_name)
  end
  
  def calculate_category_stats
    services = @service_category.services.active
    
    {
      total_services: services.count,
      average_price: services.average(:base_price)&.round(2) || 0,
      average_duration: services.average(:duration_minutes)&.to_i || 0,
      price_range: {
        min: services.minimum(:base_price) || 0,
        max: services.maximum(:base_price) || 0
      }
    }
  end
  
  def create_default_templates
    @service_category.category_templates.create!(
      template_name: 'Standard Description',
      description_template: "Professional {{service_name}} service. Duration: {{duration}}. Starting at {{price}}."
    )
  end
end
```

### 4. Service Categories Index View
**File**: `app/views/admin/service_categories/index.html.erb`

**Implementation Notes**:
```erb
<div class="max-w-7xl mx-auto py-8">
  <div class="flex justify-between items-center mb-6">
    <div>
      <h1 class="text-2xl font-bold text-gray-900">Service Categories</h1>
      <p class="text-gray-600">
        <%= @service_categories.count %> categories organizing <%= @total_services %> services
        <% if @uncategorized_services > 0 %>
          | <span class="text-yellow-600"><%= @uncategorized_services %> uncategorized services</span>
        <% end %>
      </p>
    </div>
    <div class="flex space-x-3">
      <% if @uncategorized_services > 0 %>
        <%= link_to "Organize Uncategorized", "#", 
                    class: "bg-yellow-600 hover:bg-yellow-700 text-white font-medium py-2 px-4 rounded-md",
                    data: { action: "click->categories#showBulkAssign" } %>
      <% end %>
      <%= link_to "New Category", new_admin_service_category_path,
                  class: "bg-blue-600 hover:bg-blue-700 text-white font-medium py-2 px-4 rounded-md" %>
    </div>
  </div>
  
  <!-- Categories Grid -->
  <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 mb-8" data-controller="sortable" data-sortable-url-value="<%= reorder_admin_service_categories_path %>">
    <% @service_categories.each do |category| %>
      <div class="bg-white rounded-lg shadow-sm border border-gray-200 hover:shadow-md transition-shadow" data-sortable-id="<%= category.id %>">
        <!-- Category Header -->
        <div class="p-4 border-b border-gray-100">
          <div class="flex items-center justify-between">
            <div class="flex items-center">
              <% if category.color_code.present? %>
                <div class="w-4 h-4 rounded-full mr-3" style="background-color: <%= category.color_code %>"></div>
              <% else %>
                <div class="w-4 h-4 rounded-full bg-gray-300 mr-3"></div>
              <% end %>
              <h3 class="text-lg font-medium text-gray-900"><%= category.name %></h3>
            </div>
            <div class="flex items-center space-x-2">
              <span class="<%= category.is_active? ? 'text-green-500' : 'text-gray-400' %>">
                <%= category.is_active? ? '●' : '○' %>
              </span>
              <button class="text-gray-400 hover:text-gray-600 cursor-move" data-sortable-handle>
                <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                  <path d="M10 6a2 2 0 110-4 2 2 0 010 4zM10 12a2 2 0 110-4 2 2 0 010 4zM10 18a2 2 0 110-4 2 2 0 010 4z"/>
                </svg>
              </button>
            </div>
          </div>
          <% if category.description.present? %>
            <p class="text-sm text-gray-600 mt-2"><%= truncate(category.description, length: 80) %></p>
          <% end %>
        </div>
        
        <!-- Category Stats -->
        <div class="p-4">
          <div class="grid grid-cols-2 gap-4 mb-4">
            <div class="text-center">
              <div class="text-2xl font-bold text-gray-900"><%= category.services_count || 0 %></div>
              <div class="text-xs text-gray-500">Services</div>
            </div>
            <div class="text-center">
              <div class="text-2xl font-bold text-gray-900">
                <%= number_to_currency(category.avg_price || 0) %>
              </div>
              <div class="text-xs text-gray-500">Avg Price</div>
            </div>
          </div>
          
          <!-- Recent Services -->
          <% if category.services.active.any? %>
            <div class="space-y-1 mb-4">
              <h4 class="text-xs font-medium text-gray-500 uppercase tracking-wider">Recent Services</h4>
              <% category.services.active.limit(3).each do |service| %>
                <div class="flex justify-between items-center text-sm">
                  <span class="text-gray-700 truncate"><%= truncate(service.name, length: 20) %></span>
                  <span class="text-gray-500"><%= number_to_currency(service.base_price) %></span>
                </div>
              <% end %>
              <% if category.services.active.count > 3 %>
                <div class="text-xs text-gray-500">+ <%= category.services.active.count - 3 %> more</div>
              <% end %>
            </div>
          <% end %>
          
          <!-- Actions -->
          <div class="flex justify-between items-center">
            <%= link_to "View Details", admin_service_category_path(category),
                        class: "text-blue-600 hover:text-blue-900 text-sm font-medium" %>
            <div class="flex space-x-2">
              <%= link_to "Edit", edit_admin_service_category_path(category),
                          class: "text-blue-600 hover:text-blue-900 text-sm" %>
              <% if category.can_be_deleted? %>
                <%= link_to "Delete", admin_service_category_path(category), method: :delete,
                            confirm: "Are you sure you want to delete this category?",
                            class: "text-red-600 hover:text-red-900 text-sm" %>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    <% end %>
  </div>
  
  <!-- Uncategorized Services -->
  <% if @uncategorized_services > 0 %>
    <div class="bg-yellow-50 border border-yellow-200 rounded-lg p-6">
      <div class="flex items-center justify-between">
        <div>
          <h3 class="text-lg font-medium text-yellow-800">Uncategorized Services</h3>
          <p class="text-yellow-700">
            You have <%= @uncategorized_services %> services that haven't been assigned to a category.
          </p>
        </div>
        <div class="flex space-x-3">
          <%= link_to "View Services", admin_services_path(category_id: 'uncategorized'),
                      class: "bg-yellow-600 hover:bg-yellow-700 text-white font-medium py-2 px-4 rounded-md" %>
          <%= link_to "Bulk Assign", "#",
                      class: "bg-blue-600 hover:bg-blue-700 text-white font-medium py-2 px-4 rounded-md",
                      data: { action: "click->categories#showBulkAssign" } %>
        </div>
      </div>
    </div>
  <% end %>
</div>

<!-- Bulk Assignment Modal -->
<div id="bulk-assign-modal" class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 hidden">
  <div class="bg-white rounded-lg shadow-xl max-w-2xl w-full mx-4">
    <div class="p-6">
      <h3 class="text-lg font-medium text-gray-900 mb-4">Assign Services to Categories</h3>
      
      <%= form_with url: bulk_assign_admin_service_categories_path, method: :patch, local: true,
                    class: "space-y-4" do |form| %>
        
        <!-- Service Selection -->
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">Select Services</label>
          <div class="max-h-40 overflow-y-auto border border-gray-300 rounded-md p-3">
            <% @business.services.where(service_category: nil).each do |service| %>
              <label class="flex items-center py-1">
                <input type="checkbox" name="service_ids[]" value="<%= service.id %>"
                       class="rounded border-gray-300 text-blue-600 focus:ring-blue-500 mr-2">
                <span class="text-sm text-gray-700"><%= service.name %></span>
              </label>
            <% end %>
          </div>
        </div>
        
        <!-- Category Selection -->
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Assign to Category</label>
          <%= form.select :target_category_id,
                         options_from_collection_for_select(@service_categories, :id, :name),
                         { prompt: "Select a category" },
                         { class: "block w-full border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500" } %>
        </div>
        
        <div class="flex justify-end space-x-3">
          <button type="button" onclick="document.getElementById('bulk-assign-modal').classList.add('hidden')"
                  class="bg-gray-300 hover:bg-gray-400 text-gray-700 font-medium py-2 px-4 rounded-md">
            Cancel
          </button>
          <%= form.submit "Assign Services",
                          class: "bg-blue-600 hover:bg-blue-700 text-white font-medium py-2 px-4 rounded-md" %>
        </div>
      <% end %>
    </div>
  </div>
</div>

<script data-turbo-track="reload">
  // Stimulus controller for categories management
  class CategoriesController extends Stimulus.Controller {
    showBulkAssign() {
      document.getElementById('bulk-assign-modal').classList.remove('hidden');
    }
  }
  
  // Stimulus controller for sortable categories
  class SortableController extends Stimulus.Controller {
    static values = { url: String }
    
    connect() {
      this.sortable = new Sortable(this.element, {
        handle: '[data-sortable-handle]',
        animation: 150,
        onEnd: this.handleSort.bind(this)
      });
    }
    
    handleSort(event) {
      const categoryOrder = Array.from(this.element.children).map(
        child => child.dataset.sortableId
      );
      
      fetch(this.urlValue, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        },
        body: JSON.stringify({ category_order: categoryOrder })
      });
    }
    
    disconnect() {
      if (this.sortable) {
        this.sortable.destroy();
      }
    }
  }
  
  Stimulus.register("categories", CategoriesController);
  Stimulus.register("sortable", SortableController);
</script>
```

### 5. Add Migration for Category Enhancements
**File**: Database migration

**Implementation Notes**:
```ruby
# Migration: Add enhanced fields to service_categories
class AddEnhancedFieldsToServiceCategories < ActiveRecord::Migration[8.0]
  def change
    add_column :service_categories, :color_code, :string
    add_column :service_categories, :display_order, :integer, default: 0
    add_column :service_categories, :icon_name, :string
    add_column :services, :display_order, :integer, default: 0
    
    add_index :service_categories, :display_order
    add_index :services, :display_order
  end
end
```

## Acceptance Criteria
- [ ] Business owners can create and organize service categories
- [ ] Categories can be visually distinguished with colors
- [ ] Services can be moved between categories via drag-and-drop
- [ ] Uncategorized services are clearly identified and can be bulk-assigned
- [ ] Category statistics provide useful business insights
- [ ] Categories can be reordered for logical organization

## Testing Requirements
- Model tests for category relationships and validations
- Controller tests for category management operations
- Service assignment and bulk operations tests
- Category ordering and statistics calculation tests
- JavaScript functionality tests for drag-and-drop
