# Feature: Client Info Custom Fields

## Overview
Enable businesses to capture additional client information beyond standard contact details by adding custom fields to client profiles. This allows for better service personalization and customer relationship management.

## User Stories
- As a business owner, I want to capture additional client details so I can provide better service
- As a staff member, I want to see relevant client information when creating quotes
- As a business owner, I want to track client preferences and requirements

## Tasks

### 1. Extend Client Model with Custom Fields
**File**: `app/models/client.rb`

**Implementation Notes**:
```ruby
class Client < ApplicationRecord
  belongs_to :business
  has_many :custom_field_values, as: :record, dependent: :destroy
  has_many :quotes, dependent: :destroy
  
  validates :name, :email, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
  
  def custom_field_value_for(field)
    custom_field_values.find_by(custom_field: field)&.value
  end
  
  def set_custom_field_value(field, value)
    field_value = custom_field_values.find_or_initialize_by(custom_field: field)
    field_value.value = value
    field_value.save!
  end
  
  def custom_fields_data
    business.custom_fields.for_context('client_info').active.map do |field|
      {
        field: field,
        value: custom_field_value_for(field),
        formatted_value: custom_field_values.find_by(custom_field: field)&.formatted_value
      }
    end
  end
end
```

### 2. Create Client Custom Fields Controller
**File**: `app/controllers/admin/clients_controller.rb`

**Implementation Notes**:
```ruby
class Admin::ClientsController < Admin::BaseController
  before_action :set_client, only: [:show, :edit, :update, :destroy]
  
  def index
    @clients = current_business.clients.includes(:custom_field_values)
    @custom_fields = current_business.custom_fields.for_context('client_info').active
  end
  
  def show
    @custom_field_data = @client.custom_fields_data
  end
  
  def new
    @client = current_business.clients.build
    @custom_fields = current_business.custom_fields.for_context('client_info').active
  end
  
  def create
    @client = current_business.clients.build(client_params)
    
    if @client.save
      save_custom_field_values
      redirect_to admin_client_path(@client), notice: 'Client created successfully'
    else
      @custom_fields = current_business.custom_fields.for_context('client_info').active
      render :new, status: :unprocessable_entity
    end
  end
  
  def edit
    @custom_fields = current_business.custom_fields.for_context('client_info').active
  end
  
  def update
    if @client.update(client_params)
      save_custom_field_values
      redirect_to admin_client_path(@client), notice: 'Client updated successfully'
    else
      @custom_fields = current_business.custom_fields.for_context('client_info').active
      render :edit, status: :unprocessable_entity
    end
  end
  
  private
  
  def set_client
    @client = current_business.clients.find(params[:id])
  end
  
  def client_params
    params.require(:client).permit(:name, :email, :phone, :address, :notes)
  end
  
  def save_custom_field_values
    custom_field_params.each do |field_name, value|
      next if value.blank?
      
      field_id = field_name.gsub('custom_field_', '').to_i
      field = current_business.custom_fields.find(field_id)
      @client.set_custom_field_value(field, value)
    end
  end
  
  def custom_field_params
    params.permit(current_business.custom_fields.for_context('client_info').active.map(&:form_name))
  end
end
```

### 3. Create Client Form with Custom Fields
**File**: `app/views/admin/clients/_form.html.erb`

**Implementation Notes**:
```erb
<%= form_with model: [:admin, client], class: "space-y-6" do |form| %>
  <% if client.errors.any? %>
    <div class="bg-red-50 border border-red-300 rounded-md p-4">
      <ul class="list-disc list-inside text-red-700">
        <% client.errors.full_messages.each do |message| %>
          <li><%= message %></li>
        <% end %>
      </ul>
    </div>
  <% end %>

  <!-- Standard Client Fields -->
  <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
    <div>
      <%= form.label :name, class: "block text-sm font-medium text-gray-700 mb-1" %>
      <%= form.text_field :name, 
          class: "block w-full border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500",
          required: true %>
    </div>
    
    <div>
      <%= form.label :email, class: "block text-sm font-medium text-gray-700 mb-1" %>
      <%= form.email_field :email,
          class: "block w-full border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500",
          required: true %>
    </div>
    
    <div>
      <%= form.label :phone, class: "block text-sm font-medium text-gray-700 mb-1" %>
      <%= form.tel_field :phone,
          class: "block w-full border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500" %>
    </div>
    
    <div>
      <%= form.label :address, class: "block text-sm font-medium text-gray-700 mb-1" %>
      <%= form.text_area :address, rows: 2,
          class: "block w-full border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500" %>
    </div>
  </div>

  <!-- Custom Fields Section -->
  <% if @custom_fields.any? %>
    <div class="border-t border-gray-200 pt-6">
      <h3 class="text-lg font-medium text-gray-900 mb-4">Additional Information</h3>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
        <% @custom_fields.each do |field| %>
          <div>
            <%= render CustomFieldComponent.new(
              field: field,
              form: form,
              value: client.custom_field_value_for(field)
            ) %>
          </div>
        <% end %>
      </div>
    </div>
  <% end %>

  <!-- Notes -->
  <div>
    <%= form.label :notes, class: "block text-sm font-medium text-gray-700 mb-1" %>
    <%= form.text_area :notes, rows: 3,
        class: "block w-full border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500",
        placeholder: "Additional notes about this client..." %>
  </div>

  <div class="flex justify-end space-x-4">
    <%= link_to "Cancel", admin_clients_path,
        class: "px-4 py-2 border border-gray-300 rounded-md text-gray-700 hover:bg-gray-50" %>
    <%= form.submit client.persisted? ? "Update Client" : "Create Client",
        class: "px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700" %>
  </div>
<% end %>
```

### 4. Create Client Show View with Custom Fields
**File**: `app/views/admin/clients/show.html.erb`

**Implementation Notes**:
```erb
<div class="max-w-4xl mx-auto">
  <div class="bg-white shadow rounded-lg">
    <div class="px-6 py-4 border-b border-gray-200">
      <div class="flex justify-between items-center">
        <h1 class="text-2xl font-bold text-gray-900"><%= @client.name %></h1>
        <div class="flex space-x-3">
          <%= link_to "Edit", edit_admin_client_path(@client),
              class: "px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700" %>
          <%= link_to "Back to Clients", admin_clients_path,
              class: "px-4 py-2 border border-gray-300 rounded-md text-gray-700 hover:bg-gray-50" %>
        </div>
      </div>
    </div>

    <div class="px-6 py-6">
      <!-- Standard Client Information -->
      <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mb-8">
        <div>
          <h3 class="text-sm font-medium text-gray-500 mb-1">Email</h3>
          <p class="text-sm text-gray-900">
            <a href="mailto:<%= @client.email %>" class="text-blue-600 hover:text-blue-500">
              <%= @client.email %>
            </a>
          </p>
        </div>
        
        <% if @client.phone.present? %>
          <div>
            <h3 class="text-sm font-medium text-gray-500 mb-1">Phone</h3>
            <p class="text-sm text-gray-900">
              <a href="tel:<%= @client.phone %>" class="text-blue-600 hover:text-blue-500">
                <%= @client.phone %>
              </a>
            </p>
          </div>
        <% end %>
        
        <% if @client.address.present? %>
          <div class="md:col-span-2">
            <h3 class="text-sm font-medium text-gray-500 mb-1">Address</h3>
            <p class="text-sm text-gray-900"><%= @client.address %></p>
          </div>
        <% end %>
      </div>

      <!-- Custom Fields Information -->
      <% if @custom_field_data.any? %>
        <div class="border-t border-gray-200 pt-6">
          <h3 class="text-lg font-medium text-gray-900 mb-4">Additional Information</h3>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
            <% @custom_field_data.each do |data| %>
              <% if data[:value].present? %>
                <div>
                  <h4 class="text-sm font-medium text-gray-500 mb-1">
                    <%= data[:field].label %>
                  </h4>
                  <p class="text-sm text-gray-900">
                    <%= data[:formatted_value] || data[:value] %>
                  </p>
                </div>
              <% end %>
            <% end %>
          </div>
        </div>
      <% end %>

      <!-- Notes -->
      <% if @client.notes.present? %>
        <div class="border-t border-gray-200 pt-6 mt-6">
          <h3 class="text-lg font-medium text-gray-900 mb-2">Notes</h3>
          <p class="text-sm text-gray-700 whitespace-pre-wrap"><%= @client.notes %></p>
        </div>
      <% end %>
    </div>
  </div>
</div>
```

### 5. Update Database Migration
**File**: `db/migrate/xxx_create_clients.rb`

**Implementation Notes**:
```ruby
class CreateClients < ActiveRecord::Migration[8.0]
  def change
    create_table :clients do |t|
      t.references :business, null: false, foreign_key: true
      t.string :name, null: false
      t.string :email, null: false
      t.string :phone
      t.text :address
      t.text :notes
      t.datetime :last_contacted_at
      
      t.timestamps
    end
    
    add_index :clients, [:business_id, :email], unique: true
    add_index :clients, [:business_id, :name]
    add_index :clients, [:business_id, :created_at]
  end
end
```

## Acceptance Criteria
- Clients can have custom field values in addition to standard fields
- Custom fields appear in client creation and editing forms
- Custom field values are displayed in client detail view
- Client custom fields are business-scoped
- Custom field validation applies to client data
- Existing clients can be updated with custom field values

## Estimate
- Story Points: 5
- Timeline: 3 days
- Dependencies: CustomField system, Client model
