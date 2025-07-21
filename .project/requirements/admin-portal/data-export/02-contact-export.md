# Feature: Contact & Client Export

## Overview
Enable businesses to export their client and contact database in standard formats for CRM integration, marketing campaigns, and backup purposes.

## User Stories
- As a business owner, I want to export my contact list so I can use it in marketing tools
- As a business owner, I want to backup my client data for security purposes
- As a sales manager, I want to analyze client data in external tools

## Tasks

### 1. Extend DataExportService for Contacts
**File**: `app/services/contact_export_service.rb`

**Implementation Notes**:
```ruby
class ContactExportService
  def initialize(business, format, parameters = {})
    @business = business
    @format = format
    @parameters = parameters
  end
  
  def generate
    contacts = @business.clients.includes(:quotes, :custom_field_values)
    contacts = apply_filters(contacts)
    
    case @format
    when 'csv'
      generate_contacts_csv(contacts)
    when 'excel'
      generate_contacts_excel(contacts)
    when 'pdf'
      generate_contacts_pdf(contacts)
    end
  end
  
  private
  
  def apply_filters(relation)
    relation = relation.where(created_at: date_range) if @parameters[:date_range]
    relation = relation.joins(:quotes).where(quotes: { status: @parameters[:quote_status] }) if @parameters[:quote_status]
    relation
  end
  
  def generate_contacts_csv(contacts)
    CSV.generate(headers: true) do |csv|
      headers = [
        'Name', 'Email', 'Phone', 'Address', 'Total Quotes', 'Total Revenue',
        'Last Contact', 'Customer Since', 'Notes'
      ]
      
      # Add custom field headers
      custom_fields = @business.custom_fields.for_context('client_info').active
      headers += custom_fields.map(&:label)
      
      csv << headers
      
      contacts.each do |contact|
        row = [
          contact.name,
          contact.email,
          contact.phone,
          contact.full_address,
          contact.quotes.count,
          contact.quotes.accepted.sum(:total_amount),
          contact.quotes.maximum(:created_at)&.strftime('%Y-%m-%d'),
          contact.created_at.strftime('%Y-%m-%d'),
          contact.notes
        ]
        
        # Add custom field values
        custom_fields.each do |field|
          value = contact.custom_field_values.find_by(custom_field: field)&.value
          row << value
        end
        
        csv << row
      end
    end
  end
  
  def generate_contacts_excel(contacts)
    # Excel generation using spreadsheet gem or similar
    require 'spreadsheet'
    
    book = Spreadsheet::Workbook.new
    sheet = book.create_worksheet(name: 'Contacts')
    
    # Headers
    headers = ['Name', 'Email', 'Phone', 'Address', 'Total Quotes', 'Total Revenue']
    headers.each_with_index { |header, index| sheet[0, index] = header }
    
    # Data rows
    contacts.each_with_index do |contact, row_index|
      sheet[row_index + 1, 0] = contact.name
      sheet[row_index + 1, 1] = contact.email
      sheet[row_index + 1, 2] = contact.phone
      sheet[row_index + 1, 3] = contact.full_address
      sheet[row_index + 1, 4] = contact.quotes.count
      sheet[row_index + 1, 5] = contact.quotes.accepted.sum(:total_amount)
    end
    
    # Return as string
    StringIO.new.tap { |io| book.write(io); io.rewind }.read
  end
end
```

### 2. Create DataExportJob
**File**: `app/jobs/data_export_job.rb`

**Implementation Notes**:
```ruby
class DataExportJob < ApplicationJob
  queue_as :exports
  
  def perform(export_id)
    export = DataExport.find(export_id)
    export.update!(status: :processing)
    
    begin
      file_content = generate_export_content(export)
      
      # Create temporary file
      temp_file = Tempfile.new([export.export_type, ".#{export.format}"])
      temp_file.write(file_content)
      temp_file.rewind
      
      # Attach file to export record
      export.export_file.attach(
        io: temp_file,
        filename: generate_filename(export),
        content_type: content_type_for_format(export.format)
      )
      
      export.update!(
        status: :completed,
        completed_at: Time.current,
        file_size: temp_file.size
      )
      
      # Send notification to user
      ExportCompletedMailer.notify(export).deliver_now
      
    rescue => e
      export.update!(
        status: :failed,
        error_message: e.message
      )
      Rails.logger.error "Export failed: #{e.message}"
    ensure
      temp_file&.close
      temp_file&.unlink
    end
  end
  
  private
  
  def generate_export_content(export)
    service_class = case export.export_type
    when 'quotes', 'invoices'
      QuoteInvoiceExportService
    when 'contacts'
      ContactExportService
    when 'jobs'
      JobExportService
    else
      raise "Unknown export type: #{export.export_type}"
    end
    
    service = service_class.new(
      export.business,
      export.format,
      JSON.parse(export.parameters)
    )
    
    service.generate
  end
  
  def generate_filename(export)
    timestamp = export.created_at.strftime('%Y%m%d_%H%M%S')
    "#{export.export_type}_#{timestamp}.#{export.format}"
  end
  
  def content_type_for_format(format)
    case format
    when 'csv'
      'text/csv'
    when 'pdf'
      'application/pdf'
    when 'excel'
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    end
  end
end
```

## Acceptance Criteria
- Contact data can be exported with all standard fields
- Custom fields are included in contact exports
- Export filters work for date ranges and quote status
- Excel format maintains proper formatting and data types
- Large contact lists are processed efficiently in background

## Estimate
- Story Points: 5
- Timeline: 3 days
- Dependencies: Contact model, custom fields system, Excel generation library
