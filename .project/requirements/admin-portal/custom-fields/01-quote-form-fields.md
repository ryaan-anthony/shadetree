# Feature: Quote Form Custom Fields

## Overview
Enable business owners to add custom fields to their quote request forms to collect service-specific information from customers. This allows businesses to gather relevant details that help them provide accurate quotes and better service.

## User Stories
- As a business owner, I want to add custom fields to quote forms so I can collect service-specific information
- As a customer, I want relevant form fields so I can provide accurate information for my service request
- As a staff member, I want to see custom field data when creating quotes

## Tasks

### 1. Create CustomField Model
**File**: `app/models/custom_field.rb`

**Implementation Notes**:
```ruby
class CustomField < ApplicationRecord
  belongs_to :business
  has_many :custom_field_values, dependent: :destroy
  
  validates :name, :field_type, :context, presence: true
  validates :name, uniqueness: { scope: [:business_id, :context] }
  validates :label, presence: true
  
  enum field_type: {
    text_field: 0,
    text_area: 1,
    select_field: 2,
    checkbox: 3,
    date_field: 4,
    number_field: 5
  }
  
  enum context: { quote_form: 0, client_info: 1, job_record: 2 }
  
  scope :for_context, ->(context) { where(context: context) }
  scope :required, -> { where(required: true) }
  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:display_order) }
  
  def form_name
    "custom_field_#{id}"
  end
  
  def options_array
    return [] unless select_field?
    options.is_a?(String) ? options.split("\n").map(&:strip) : options
  end
end
```

### 2. Create CustomFieldValue Model
**File**: `app/models/custom_field_value.rb`

**Implementation Notes**:
```ruby
class CustomFieldValue < ApplicationRecord
  belongs_to :custom_field
  belongs_to :record, polymorphic: true
  
  validates :custom_field_id, uniqueness: { scope: [:record_type, :record_id] }
  validate :value_format_valid
  validate :required_field_present
  
  scope :for_custom_field, ->(field) { where(custom_field: field) }
  
  private
  
  def value_format_valid
    return if value.blank?
    
    case custom_field.field_type
    when 'date_field'
      Date.parse(value)
    when 'number_field'
      Float(value)
    end
  rescue ArgumentError
    errors.add(:value, "must be a valid #{custom_field.field_type.humanize.downcase}")
  end
  
  def required_field_present
    if custom_field.required? && value.blank?
      errors.add(:value, "is required")
    end
  end
end
```

### 3. Create CustomFields Controller
**File**: `app/controllers/admin/custom_fields_controller.rb`

**Implementation Notes**:
```ruby
class Admin::CustomFieldsController < Admin::BaseController
  before_action :set_custom_field, only: [:show, :edit, :update, :destroy]
  before_action :ensure_can_manage_custom_fields
  
  def index
    @custom_fields = current_business.custom_fields
      .for_context(params[:context] || 'quote_form')
      .ordered
      .includes(:custom_field_values)
  end
  
  def new
    @custom_field = current_business.custom_fields.build(
      context: params[:context] || 'quote_form'
    )
  end
  
  def create
    @custom_field = current_business.custom_fields.build(custom_field_params)
    
    if @custom_field.save
      redirect_to admin_custom_fields_path(context: @custom_field.context),
                  notice: 'Custom field created successfully'
    else
      render :new, status: :unprocessable_entity
    end
  end
  
  def edit
  end
  
  def update
    if @custom_field.update(custom_field_params)
      redirect_to admin_custom_fields_path(context: @custom_field.context),
                  notice: 'Custom field updated successfully'
    else
      render :edit, status: :unprocessable_entity
    end
  end
  
  def destroy
    context = @custom_field.context
    @custom_field.destroy
    redirect_to admin_custom_fields_path(context: context),
                notice: 'Custom field deleted successfully'
  end
  
  def reorder
    params[:custom_field_ids].each_with_index do |id, index|
      current_business.custom_fields.find(id).update!(display_order: index)
    end
    
    head :ok
  end
  
  private
  
  def set_custom_field
    @custom_field = current_business.custom_fields.find(params[:id])
  end
  
  def custom_field_params
    params.require(:custom_field).permit(
      :name, :label, :field_type, :context, :required, :placeholder,
      :display_order, :active, options: []
    )
  end
  
  def ensure_can_manage_custom_fields
    unless current_business_user.can_manage_services?
      redirect_to admin_dashboard_path, alert: 'Access denied'
    end
  end
end
```

### 4. Create CustomFormBuilder Service
**File**: `app/services/custom_form_builder.rb`

**Implementation Notes**:
```ruby
class CustomFormBuilder
  def initialize(business, context)
    @business = business
    @context = context
  end
  
  def render_fields(form_object, record = nil)
    custom_fields.map do |field|
      existing_value = existing_value_for(field, record)
      render_field(form_object, field, existing_value)
    end.join.html_safe
  end
  
  def save_values(record, params)
    custom_fields.each do |field|
      value = params[field.form_name]
      next if value.blank? && !field.required?
      
      field_value = record.custom_field_values.find_or_initialize_by(
        custom_field: field
      )
      field_value.value = value
      field_value.save!
    end
  end
  
  private
  
  def custom_fields
    @custom_fields ||= @business.custom_fields
      .for_context(@context)
      .active
      .ordered
  end
  
  def existing_value_for(field, record)
    return nil unless record
    record.custom_field_values.find_by(custom_field: field)&.value
  end
  
  def render_field(form_object, field, existing_value)
    case field.field_type
    when 'text_field'
      render_text_field(form_object, field, existing_value)
    when 'text_area'
      render_text_area(form_object, field, existing_value)
    when 'select_field'
      render_select_field(form_object, field, existing_value)
    when 'checkbox'
      render_checkbox(form_object, field, existing_value)
    when 'date_field'
      render_date_field(form_object, field, existing_value)
    when 'number_field'
      render_number_field(form_object, field, existing_value)
    end
  end
  
  def render_text_field(form_object, field, existing_value)
    form_object.text_field(
      field.form_name,
      value: existing_value,
      required: field.required?,
      placeholder: field.placeholder,
      class: "block w-full border-gray-300 rounded-md shadow-sm"
    )
  end
  
  def render_select_field(form_object, field, existing_value)
    options = field.options_array.map { |opt| [opt, opt] }
    
    form_object.select(
      field.form_name,
      options_for_select(options, existing_value),
      { prompt: field.placeholder || "Select #{field.label}" },
      { 
        required: field.required?,
        class: "block w-full border-gray-300 rounded-md shadow-sm"
      }
    )
  end
  
  # Additional render methods for other field types...
end
```

### 5. Create Database Migration
**File**: `db/migrate/xxx_create_custom_fields.rb`

**Implementation Notes**:
```ruby
class CreateCustomFields < ActiveRecord::Migration[8.0]
  def change
    create_table :custom_fields do |t|
      t.references :business, null: false, foreign_key: true
      t.string :name, null: false
      t.string :label, null: false
      t.integer :field_type, null: false
      t.integer :context, null: false
      t.text :options # JSON array for select options
      t.string :placeholder
      t.boolean :required, default: false
      t.integer :display_order, default: 0
      t.boolean :active, default: true
      
      t.timestamps
    end
    
    add_index :custom_fields, [:business_id, :context]
    add_index :custom_fields, [:business_id, :context, :display_order]
    add_index :custom_fields, [:business_id, :name], unique: true
  end
end

class CreateCustomFieldValues < ActiveRecord::Migration[8.0]
  def change
    create_table :custom_field_values do |t|
      t.references :custom_field, null: false, foreign_key: true
      t.references :record, polymorphic: true, null: false
      t.text :value
      
      t.timestamps
    end
    
    add_index :custom_field_values, [:record_type, :record_id]
    add_index :custom_field_values, 
              [:custom_field_id, :record_type, :record_id], 
              unique: true, 
              name: 'unique_custom_field_per_record'
  end
end
```

## Acceptance Criteria
- Business owners can add custom fields to quote forms
- Six field types supported: text, textarea, select, checkbox, date, number
- Fields can be marked as required or optional
- Field order can be changed via drag-and-drop
- Custom field values are saved with quote requests
- Form validation works for all field types

## Estimate
- Story Points: 8
- Timeline: 1 week
- Dependencies: Business model, quote request system
