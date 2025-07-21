# Epic: Custom Fields & Forms

## Overview
Enable business owners to create custom fields for quote forms, client information, and job records. This allows businesses to collect specific information relevant to their service type and operational needs while maintaining professional presentation.

## Goals
- Enable businesses to customize quote request forms for their specific needs
- Support collection of custom client information beyond basic contact details
- Allow job-specific data capture for service delivery and reporting
- Maintain data integrity and validation for custom fields
- Provide flexible field types for diverse business requirements

## Success Metrics
- Custom field setup completion time < 5 minutes
- Form completion rate increase > 15% with relevant custom fields
- Custom field usage adoption > 60% of businesses
- Form validation error rate < 5%
- Customer form abandonment rate decrease > 20%

## User Stories
- As a business owner, I want to add custom fields to quote forms so I can collect service-specific information
- As a business owner, I want to capture additional client details so I can provide better service
- As a business owner, I want to record job-specific information so I can track project details
- As a customer, I want relevant form fields so I can provide accurate information for my service request
- As a staff member, I want to see custom field data when creating quotes and managing jobs

## Features

### MVP Phase (P1 - Early Value)
1. [Quote Form Custom Fields](custom-fields/01-quote-form-fields.md) - Add custom fields to quote request forms
2. [Field Type Management](custom-fields/02-field-types.md) - Support basic field types (text, select, checkbox, date)

### Growth Phase (P2 - Advanced Features)
3. [Client Info Custom Fields](custom-fields/03-client-custom-fields.md) - Custom fields for client profiles
4. [Job Record Custom Fields](custom-fields/04-job-custom-fields.md) - Custom data capture for job management

## Technical Architecture

### Core Models
```ruby
# Custom field definition
class CustomField < ApplicationRecord
  belongs_to :business
  has_many :custom_field_values, dependent: :destroy
  
  validates :name, :field_type, :context, presence: true
  validates :name, uniqueness: { scope: [:business_id, :context] }
  
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
end

# Store custom field values
class CustomFieldValue < ApplicationRecord
  belongs_to :custom_field
  belongs_to :record, polymorphic: true  # quote_request, client, job, etc.
  
  validates :custom_field_id, uniqueness: { scope: [:record_type, :record_id] }
  validate :value_format_valid
  
  private
  
  def value_format_valid
    case custom_field.field_type
    when 'date_field'
      Date.parse(value) rescue errors.add(:value, 'must be a valid date')
    when 'number_field'
      Float(value) rescue errors.add(:value, 'must be a number')
    end
  end
end
```

### Form Builder Service
```ruby
class CustomFormBuilder
  def initialize(business, context)
    @business = business
    @context = context
  end
  
  def render_fields(form_object, record = nil)
    custom_fields.map do |field|
      existing_value = record&.custom_field_values&.find_by(custom_field: field)&.value
      
      case field.field_type
      when 'text_field'
        form_object.text_field field.form_name, 
          value: existing_value,
          required: field.required?,
          placeholder: field.placeholder
      when 'select_field'
        form_object.select field.form_name,
          options_for_select(field.options, existing_value),
          { prompt: field.placeholder },
          { required: field.required? }
      # ... other field types
      end
    end.join.html_safe
  end
  
  private
  
  def custom_fields
    @custom_fields ||= @business.custom_fields.for_context(@context).order(:display_order)
  end
end
```

## Integration Points
- Quote Request Forms (customer-facing form customization)
- Client Management (extended client profiles)
- Job Management (service-specific data capture)
- Admin Dashboard (custom field usage metrics)
- Reports & Analytics (custom field data in reports)

## Security Considerations
- Validate custom field definitions to prevent code injection
- Sanitize user input for custom field values
- Ensure business scoping for all custom field operations
- Audit custom field creation and modification

## MVP Scope (P1 Priority)
**Included in MVP:**
- Quote form custom fields only
- 6 basic field types (text, textarea, select, checkbox, date, number)
- Simple field management interface
- Basic validation and required field support

**Deferred to Growth Phase:**
- Client info and job record custom fields
- Advanced field types (file upload, multi-select)
- Conditional field display logic
- Field dependency validation

## Technical Implementation Notes
```ruby
# Migration for custom fields
class CreateCustomFields < ActiveRecord::Migration[8.0]
  def change
    create_table :custom_fields do |t|
      t.references :business, null: false, foreign_key: true
      t.string :name, null: false
      t.string :label
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
  end
end

# Migration for custom field values
class CreateCustomFieldValues < ActiveRecord::Migration[8.0]
  def change
    create_table :custom_field_values do |t|
      t.references :custom_field, null: false, foreign_key: true
      t.references :record, polymorphic: true, null: false
      t.text :value
      
      t.timestamps
    end
    
    add_index :custom_field_values, [:record_type, :record_id]
    add_index :custom_field_values, [:custom_field_id, :record_type, :record_id], 
              unique: true, name: 'unique_custom_field_per_record'
  end
end
```

## Dependencies
- Business Profile Management (business scoping)
- Quote Request System (form integration)
- Admin Dashboard (field management interface)

## Estimate
- MVP Features: 13 story points (1.5 weeks)
- Growth Features: 8 story points (1 week)
- Total: 21 story points (2.5 weeks)
