# Feature: Custom Export Builder

## Overview
Provide a flexible export builder that allows business owners to create custom exports with field selection, advanced filtering, and scheduling capabilities.

## User Stories
- As a business owner, I want to select specific fields for export so I only get the data I need
- As a business owner, I want to save export configurations so I can reuse them regularly
- As a business owner, I want to schedule recurring exports for regular reporting

## Tasks

### 1. Create ExportTemplate Model
**File**: `app/models/export_template.rb`

**Implementation Notes**:
```ruby
class ExportTemplate < ApplicationRecord
  belongs_to :business
  belongs_to :created_by, class_name: 'User'
  has_many :data_exports, dependent: :nullify
  
  validates :name, :export_type, :field_configuration, presence: true
  validates :name, uniqueness: { scope: :business_id }
  
  enum export_type: { quotes: 0, contacts: 1, jobs: 2, custom: 3 }
  
  scope :active, -> { where(active: true) }
  
  def available_fields
    case export_type
    when 'quotes'
      quote_fields
    when 'contacts'
      contact_fields
    when 'jobs'
      job_fields
    end
  end
  
  def selected_fields
    JSON.parse(field_configuration)['selected_fields'] || []
  end
  
  def filters
    JSON.parse(field_configuration)['filters'] || {}
  end
  
  private
  
  def quote_fields
    {
      'basic' => ['id', 'client_name', 'client_email', 'created_at', 'status', 'total_amount'],
      'details' => ['description', 'notes', 'due_date', 'payment_status'],
      'custom' => business.custom_fields.for_context('quote_form').pluck(:name, :label)
    }
  end
  
  def contact_fields
    {
      'basic' => ['name', 'email', 'phone', 'address', 'created_at'],
      'analytics' => ['total_quotes', 'total_revenue', 'last_contact_date'],
      'custom' => business.custom_fields.for_context('client_info').pluck(:name, :label)
    }
  end
  
  def job_fields
    {
      'basic' => ['id', 'title', 'client_name', 'assigned_staff', 'status'],
      'scheduling' => ['scheduled_date', 'started_at', 'completed_at', 'duration'],
      'details' => ['description', 'notes'],
      'custom' => business.custom_fields.for_context('job_record').pluck(:name, :label)
    }
  end
end
```

### 2. Create CustomExportBuilder Service
**File**: `app/services/custom_export_builder.rb`

**Implementation Notes**:
```ruby
class CustomExportBuilder
  def initialize(business, template, format)
    @business = business
    @template = template
    @format = format
  end
  
  def generate
    case @template.export_type
    when 'quotes'
      build_quote_export
    when 'contacts'
      build_contact_export
    when 'jobs'
      build_job_export
    end
  end
  
  private
  
  def build_quote_export
    quotes = @business.quotes.includes(:client, :quote_line_items, :custom_field_values)
    quotes = apply_template_filters(quotes, @template.filters)
    
    selected_fields = @template.selected_fields
    
    case @format
    when 'csv'
      generate_custom_csv(quotes, selected_fields, :quote)
    end
  end
  
  def build_contact_export
    contacts = @business.clients.includes(:quotes, :custom_field_values)
    contacts = apply_template_filters(contacts, @template.filters)
    
    selected_fields = @template.selected_fields
    
    case @format
    when 'csv'
      generate_custom_csv(contacts, selected_fields, :contact)
    end
  end
  
  def generate_custom_csv(records, selected_fields, record_type)
    CSV.generate(headers: true) do |csv|
      # Dynamic headers based on selected fields
      headers = selected_fields.map { |field| field_label(field, record_type) }
      csv << headers
      
      records.each do |record|
        row = selected_fields.map { |field| extract_field_value(record, field, record_type) }
        csv << row
      end
    end
  end
  
  def extract_field_value(record, field, record_type)
    case record_type
    when :quote
      extract_quote_field(record, field)
    when :contact
      extract_contact_field(record, field)
    when :job
      extract_job_field(record, field)
    end
  end
  
  def extract_quote_field(quote, field)
    case field
    when 'id' then quote.id
    when 'client_name' then quote.client.name
    when 'client_email' then quote.client.email
    when 'created_at' then quote.created_at.strftime('%Y-%m-%d')
    when 'status' then quote.status.humanize
    when 'total_amount' then quote.total_amount
    when 'description' then quote.description
    when 'notes' then quote.notes
    else
      # Custom field
      custom_field = @business.custom_fields.find_by(name: field)
      quote.custom_field_values.find_by(custom_field: custom_field)&.value if custom_field
    end
  end
  
  def field_label(field, record_type)
    case field
    when 'id' then 'ID'
    when 'client_name' then 'Client Name'
    when 'client_email' then 'Client Email'
    when 'created_at' then 'Created Date'
    when 'total_amount' then 'Total Amount'
    else
      # Check if it's a custom field
      custom_field = @business.custom_fields.find_by(name: field)
      custom_field&.label || field.humanize
    end
  end
  
  def apply_template_filters(relation, filters)
    filters.each do |filter_type, filter_value|
      case filter_type
      when 'date_range'
        relation = relation.where(created_at: parse_date_range(filter_value))
      when 'status'
        relation = relation.where(status: filter_value)
      end
    end
    
    relation
  end
  
  def parse_date_range(range_value)
    case range_value
    when 'this_month'
      Date.current.beginning_of_month..Date.current.end_of_month
    when 'last_month'
      1.month.ago.beginning_of_month..1.month.ago.end_of_month
    when 'this_year'
      Date.current.beginning_of_year..Date.current.end_of_year
    end
  end
end
```

### 3. Create ExportTemplatesController
**File**: `app/controllers/admin/export_templates_controller.rb`

**Implementation Notes**:
```ruby
class Admin::ExportTemplatesController < Admin::BaseController
  before_action :set_export_template, only: [:show, :edit, :update, :destroy, :generate_export]
  before_action :ensure_can_manage_exports
  
  def index
    @templates = current_business.export_templates
      .includes(:created_by)
      .order(:export_type, :name)
  end
  
  def new
    @template = current_business.export_templates.build
    @export_types = export_type_options
  end
  
  def create
    @template = current_business.export_templates.build(template_params)
    @template.created_by = current_user
    
    if @template.save
      redirect_to admin_export_templates_path, notice: 'Export template created successfully'
    else
      @export_types = export_type_options
      render :new, status: :unprocessable_entity
    end
  end
  
  def edit
    @available_fields = @template.available_fields
  end
  
  def update
    if @template.update(template_params)
      redirect_to admin_export_templates_path, notice: 'Export template updated successfully'
    else
      @available_fields = @template.available_fields
      render :edit, status: :unprocessable_entity
    end
  end
  
  def generate_export
    export = current_business.data_exports.create!(
      export_type: 'custom',
      format: params[:format] || 'csv',
      parameters: { template_id: @template.id }.to_json,
      created_by: current_user,
      status: :pending
    )
    
    CustomExportJob.perform_later(export.id)
    
    redirect_to admin_data_exports_path, 
                notice: 'Custom export started using template'
  end
  
  private
  
  def set_export_template
    @template = current_business.export_templates.find(params[:id])
  end
  
  def template_params
    params.require(:export_template).permit(
      :name, :description, :export_type, :active,
      field_configuration: {}
    )
  end
  
  def export_type_options
    [
      ['Quotes', 'quotes'],
      ['Contacts', 'contacts'],
      ['Jobs', 'jobs']
    ]
  end
  
  def ensure_can_manage_exports
    unless current_business_user.can_manage_services?
      redirect_to admin_dashboard_path, alert: 'Access denied'
    end
  end
end
```

### 4. Create Database Migration
**File**: `db/migrate/xxx_create_export_templates.rb`

**Implementation Notes**:
```ruby
class CreateExportTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :export_templates do |t|
      t.references :business, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.text :description
      t.integer :export_type, null: false
      t.json :field_configuration, null: false
      t.boolean :active, default: true
      
      t.timestamps
    end
    
    add_index :export_templates, [:business_id, :name], unique: true
    add_index :export_templates, [:business_id, :export_type]
  end
end
```

## Acceptance Criteria
- Users can create reusable export templates with custom field selection
- Templates support filtering by common criteria (date, status)
- Export generation uses template configuration for field selection
- Templates can be edited and updated without losing existing exports
- Template-based exports maintain the same quality as standard exports

## Estimate
- Story Points: 8
- Timeline: 1 week
- Dependencies: DataExport system, custom fields, background jobs
