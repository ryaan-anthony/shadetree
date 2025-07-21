# Feature: Field Type Management

## Overview
Provide a comprehensive field type system that supports various input types for custom fields. This includes validation, rendering, and data storage for different field types used across quote forms, client profiles, and job records.

## User Stories
- As a business owner, I want to choose from different field types so I can collect the right kind of information
- As a developer, I want a flexible field type system that can be extended easily
- As a customer, I want form fields that are appropriate for the information being requested

## Tasks

### 1. Create FieldType Service
**File**: `app/services/field_type_service.rb`

**Implementation Notes**:
```ruby
class FieldTypeService
  FIELD_TYPES = {
    text_field: {
      label: 'Text Field',
      description: 'Single line text input',
      html_type: 'text',
      validation: :text_validation,
      max_length: 255
    },
    text_area: {
      label: 'Text Area',
      description: 'Multi-line text input',
      html_type: 'textarea',
      validation: :text_validation,
      max_length: 2000
    },
    select_field: {
      label: 'Select Dropdown',
      description: 'Choose one option from a list',
      html_type: 'select',
      validation: :select_validation,
      requires_options: true
    },
    checkbox: {
      label: 'Checkbox',
      description: 'True/false or yes/no selection',
      html_type: 'checkbox',
      validation: :boolean_validation
    },
    date_field: {
      label: 'Date Field',
      description: 'Date picker input',
      html_type: 'date',
      validation: :date_validation
    },
    number_field: {
      label: 'Number Field',
      description: 'Numeric input only',
      html_type: 'number',
      validation: :number_validation
    }
  }.freeze
  
  def self.available_types
    FIELD_TYPES.keys.map do |type|
      [FIELD_TYPES[type][:label], type]
    end
  end
  
  def self.type_config(field_type)
    FIELD_TYPES[field_type.to_sym]
  end
  
  def self.requires_options?(field_type)
    type_config(field_type)&.dig(:requires_options) || false
  end
  
  def self.validate_value(field_type, value)
    return true if value.blank?
    
    validation_method = type_config(field_type)&.dig(:validation)
    return true unless validation_method
    
    send(validation_method, value)
  end
  
  private
  
  def self.text_validation(value)
    value.is_a?(String) && value.length <= 2000
  end
  
  def self.select_validation(value)
    value.is_a?(String) && value.present?
  end
  
  def self.boolean_validation(value)
    ['true', 'false', '1', '0', true, false].include?(value)
  end
  
  def self.date_validation(value)
    Date.parse(value.to_s)
    true
  rescue ArgumentError
    false
  end
  
  def self.number_validation(value)
    Float(value.to_s)
    true
  rescue ArgumentError
    false
  end
end
```

### 2. Update CustomField Model with Field Type Logic
**File**: `app/models/custom_field.rb`

**Implementation Notes**:
```ruby
class CustomField < ApplicationRecord
  # ...existing code...
  
  validate :options_present_for_select_field
  validate :valid_field_type_configuration
  
  def field_type_config
    FieldTypeService.type_config(field_type)
  end
  
  def requires_options?
    FieldTypeService.requires_options?(field_type)
  end
  
  def html_input_type
    field_type_config&.dig(:html_type) || 'text'
  end
  
  def max_length
    field_type_config&.dig(:max_length)
  end
  
  def validate_value(value)
    FieldTypeService.validate_value(field_type, value)
  end
  
  private
  
  def options_present_for_select_field
    if requires_options? && options.blank?
      errors.add(:options, "must be provided for #{field_type.humanize}")
    end
  end
  
  def valid_field_type_configuration
    unless FieldTypeService.type_config(field_type)
      errors.add(:field_type, "is not a valid field type")
    end
  end
end
```

### 3. Create Field Renderer Component
**File**: `app/components/custom_field_component.rb`

**Implementation Notes**:
```ruby
class CustomFieldComponent < ViewComponent::Base
  def initialize(field:, form:, value: nil)
    @field = field
    @form = form
    @value = value
  end
  
  private
  
  attr_reader :field, :form, :value
  
  def field_name
    field.form_name
  end
  
  def field_options
    {
      required: field.required?,
      placeholder: field.placeholder,
      class: input_classes
    }
  end
  
  def input_classes
    "block w-full border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500"
  end
  
  def select_options
    return [] unless field.select_field?
    
    field.options_array.map { |option| [option, option] }
  end
  
  def checkbox_value
    return false if value.blank?
    ['true', '1', 'yes', 'on'].include?(value.to_s.downcase)
  end
end
```

### 4. Create Field Renderer Template
**File**: `app/components/custom_field_component.html.erb`

**Implementation Notes**:
```erb
<div class="mb-4">
  <label for="<%= field_name %>" class="block text-sm font-medium text-gray-700 mb-1">
    <%= field.label %>
    <% if field.required? %>
      <span class="text-red-500">*</span>
    <% end %>
  </label>
  
  <% case field.field_type %>
  <% when 'text_field' %>
    <%= form.text_field field_name, field_options.merge(value: value) %>
    
  <% when 'text_area' %>
    <%= form.text_area field_name, field_options.merge(
      value: value,
      rows: 3,
      maxlength: field.max_length
    ) %>
    
  <% when 'select_field' %>
    <%= form.select field_name,
        options_for_select(select_options, value),
        { prompt: field.placeholder || "Select #{field.label}" },
        field_options %>
        
  <% when 'checkbox' %>
    <div class="flex items-center">
      <%= form.check_box field_name, 
          { checked: checkbox_value },
          'true', 'false' %>
      <label for="<%= field_name %>" class="ml-2 text-sm text-gray-600">
        <%= field.placeholder || "Check if yes" %>
      </label>
    </div>
    
  <% when 'date_field' %>
    <%= form.date_field field_name, field_options.merge(value: value) %>
    
  <% when 'number_field' %>
    <%= form.number_field field_name, field_options.merge(
      value: value,
      step: :any
    ) %>
  <% end %>
  
  <% if field.placeholder && !['checkbox', 'select_field'].include?(field.field_type) %>
    <p class="mt-1 text-xs text-gray-500"><%= field.placeholder %></p>
  <% end %>
</div>
```

### 5. Create Field Type Validator
**File**: `app/validators/custom_field_value_validator.rb`

**Implementation Notes**:
```ruby
class CustomFieldValueValidator < ActiveModel::Validator
  def validate(record)
    return unless record.custom_field && record.value.present?
    
    field = record.custom_field
    value = record.value
    
    # Type-specific validation
    case field.field_type
    when 'text_field', 'text_area'
      validate_text_field(record, field, value)
    when 'select_field'
      validate_select_field(record, field, value)
    when 'date_field'
      validate_date_field(record, field, value)
    when 'number_field'
      validate_number_field(record, field, value)
    when 'checkbox'
      validate_checkbox_field(record, field, value)
    end
  end
  
  private
  
  def validate_text_field(record, field, value)
    max_length = field.max_length || 255
    if value.length > max_length
      record.errors.add(:value, "is too long (maximum is #{max_length} characters)")
    end
  end
  
  def validate_select_field(record, field, value)
    valid_options = field.options_array
    unless valid_options.include?(value)
      record.errors.add(:value, "is not a valid option")
    end
  end
  
  def validate_date_field(record, field, value)
    Date.parse(value.to_s)
  rescue ArgumentError
    record.errors.add(:value, "must be a valid date")
  end
  
  def validate_number_field(record, field, value)
    Float(value.to_s)
  rescue ArgumentError
    record.errors.add(:value, "must be a valid number")
  end
  
  def validate_checkbox_field(record, field, value)
    valid_values = ['true', 'false', '1', '0', 'yes', 'no', 'on', 'off']
    unless valid_values.include?(value.to_s.downcase)
      record.errors.add(:value, "must be a valid boolean value")
    end
  end
end
```

### 6. Update CustomFieldValue Model
**File**: `app/models/custom_field_value.rb`

**Implementation Notes**:
```ruby
class CustomFieldValue < ApplicationRecord
  # ...existing code...
  
  validates_with CustomFieldValueValidator
  
  def formatted_value
    case custom_field.field_type
    when 'checkbox'
      boolean_value? ? 'Yes' : 'No'
    when 'date_field'
      date_value&.strftime('%B %d, %Y')
    when 'number_field'
      number_value&.to_s
    else
      value
    end
  end
  
  def boolean_value?
    ['true', '1', 'yes', 'on'].include?(value.to_s.downcase)
  end
  
  def date_value
    return nil if value.blank?
    Date.parse(value.to_s)
  rescue ArgumentError
    nil
  end
  
  def number_value
    return nil if value.blank?
    Float(value.to_s)
  rescue ArgumentError
    nil
  end
end
```

## Acceptance Criteria
- Six field types are supported with proper validation
- Each field type renders appropriate HTML input
- Field type configuration is centralized and extensible
- Value validation works correctly for each type
- Field types that require options (select) are properly validated
- Form rendering handles all field types correctly

## Estimate
- Story Points: 5
- Timeline: 3 days
- Dependencies: CustomField model, form rendering system
