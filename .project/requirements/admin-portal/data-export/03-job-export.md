# Feature: Job & Service Export

## Overview
Enable businesses to export job records and service history for project documentation, performance analysis, and compliance reporting.

## User Stories
- As a business owner, I want to export job records for project documentation
- As a manager, I want to analyze service performance with external tools
- As a business owner, I want to backup my service history data

## Tasks

### 1. Create JobExportService
**File**: `app/services/job_export_service.rb`

**Implementation Notes**:
```ruby
class JobExportService
  def initialize(business, format, parameters = {})
    @business = business
    @format = format
    @parameters = parameters
  end
  
  def generate
    jobs = @business.jobs.includes(:client, :assigned_staff, :custom_field_values)
    jobs = apply_filters(jobs)
    
    case @format
    when 'csv'
      generate_jobs_csv(jobs)
    when 'pdf'
      generate_jobs_pdf(jobs)
    end
  end
  
  private
  
  def apply_filters(relation)
    relation = relation.where(created_at: date_range) if @parameters[:date_range]
    relation = relation.where(status: @parameters[:status]) if @parameters[:status]
    relation = relation.where(assigned_staff: @parameters[:staff_ids]) if @parameters[:staff_ids]
    relation
  end
  
  def generate_jobs_csv(jobs)
    CSV.generate(headers: true) do |csv|
      headers = [
        'Job ID', 'Title', 'Client Name', 'Assigned Staff', 'Status',
        'Scheduled Date', 'Started At', 'Completed At', 'Duration (hours)',
        'Description', 'Notes'
      ]
      
      # Add custom field headers
      custom_fields = @business.custom_fields.for_context('job_record').active
      headers += custom_fields.map(&:label)
      
      csv << headers
      
      jobs.each do |job|
        duration = job.duration_hours || 0
        
        row = [
          job.id,
          job.title,
          job.client.name,
          job.assigned_staff&.name || 'Unassigned',
          job.status.humanize,
          job.scheduled_date&.strftime('%Y-%m-%d'),
          job.started_at&.strftime('%Y-%m-%d %H:%M'),
          job.completed_at&.strftime('%Y-%m-%d %H:%M'),
          duration,
          job.description,
          job.notes
        ]
        
        # Add custom field values
        custom_fields.each do |field|
          value = job.custom_field_values.find_by(custom_field: field)&.formatted_value
          row << value
        end
        
        csv << row
      end
    end
  end
  
  def generate_jobs_pdf(jobs)
    pdf = Prawn::Document.new(page_layout: :landscape)
    
    pdf.text "Job Records Export - #{@business.name}", size: 18, style: :bold
    pdf.text "Generated: #{Date.current.strftime('%B %d, %Y')}", size: 12
    pdf.move_down 20
    
    if jobs.any?
      table_data = [['Job ID', 'Title', 'Client', 'Staff', 'Status', 'Scheduled']]
      
      jobs.each do |job|
        table_data << [
          job.id.to_s,
          job.title.truncate(30),
          job.client.name.truncate(20),
          job.assigned_staff&.name&.truncate(15) || 'Unassigned',
          job.status.humanize,
          job.scheduled_date&.strftime('%m/%d/%Y') || 'TBD'
        ]
      end
      
      pdf.table(table_data, header: true, width: pdf.bounds.width) do
        row(0).font_style = :bold
        row(0).background_color = 'f0f0f0'
      end
    else
      pdf.text "No jobs found for the selected criteria.", size: 14
    end
    
    pdf.render
  end
  
  def date_range
    case @parameters[:date_range]
    when 'this_month'
      Date.current.beginning_of_month..Date.current.end_of_month
    when 'last_month'
      1.month.ago.beginning_of_month..1.month.ago.end_of_month
    when 'this_year'
      Date.current.beginning_of_year..Date.current.end_of_year
    when 'custom'
      Date.parse(@parameters[:start_date])..Date.parse(@parameters[:end_date])
    else
      nil
    end
  end
end
```

## Acceptance Criteria
- Job records export includes all relevant job data and custom fields
- Export can be filtered by date, status, and assigned staff
- Duration calculations are accurate for completed jobs
- PDF format is properly formatted for landscape orientation
- Large job datasets are processed efficiently

## Estimate
- Story Points: 5
- Timeline: 3 days
- Dependencies: Job model, custom fields system
