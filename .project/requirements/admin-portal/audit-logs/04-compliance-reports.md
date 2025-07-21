# Feature: Compliance Reporting

## Overview
Create a comprehensive compliance reporting system that enables businesses to generate, schedule, and export audit reports for regulatory compliance purposes. This feature will help businesses demonstrate adherence to industry regulations, prepare for audits, and maintain proper documentation of system activities and changes.

## Goals
- Enable generation of compliance-ready audit reports
- Support various regulatory frameworks (GDPR, HIPAA, etc.)
- Provide scheduled report generation and distribution
- Allow custom report configuration for specific compliance needs
- Enable secure report archiving and retrieval

## User Stories
- As a business owner, I want to generate compliance reports to demonstrate regulatory adherence
- As a compliance officer, I want scheduled audit reports emailed to me monthly
- As an administrator, I want to export user activity reports for internal audits
- As a business owner, I want to archive compliance reports for the required retention period
- As a compliance officer, I want custom report templates for specific regulatory frameworks

## Tasks

### Task 1: Create Report Templates and Models
**Description:** Design the data models and templates for various compliance reports.

**Implementation Notes:**
- Create Report and ReportTemplate models
- Implement report configuration options
- Design default templates for common compliance needs

```ruby
# app/models/report_template.rb
class ReportTemplate < ApplicationRecord
  belongs_to :business, optional: true
  has_many :reports
  
  validates :name, :report_type, :template_definition, presence: true
  
  serialize :template_definition, Hash
  
  # System templates are available to all businesses
  scope :system_templates, -> { where(business_id: nil) }
  scope :custom_templates, -> { where.not(business_id: nil) }
  
  enum report_type: {
    user_activity: 0,
    data_changes: 1,
    security_events: 2,
    login_attempts: 3,
    permission_changes: 4,
    gdpr_processing: 5,
    hipaa_access: 6,
    pci_compliance: 7
  }
  
  def self.templates_for(business)
    where(business: [nil, business])
  end
end
```

```ruby
# app/models/report.rb
class Report < ApplicationRecord
  belongs_to :business
  belongs_to :report_template
  belongs_to :created_by, class_name: 'User'
  
  validates :name, :status, presence: true
  
  serialize :parameters, Hash
  serialize :result_metadata, Hash
  
  enum status: {
    queued: 0,
    generating: 1,
    completed: 2,
    failed: 3,
    expired: 4
  }
  
  enum format: {
    pdf: 0,
    csv: 1,
    excel: 2,
    json: 3
  }
  
  has_one_attached :report_file
  
  scope :recent, -> { where(created_at: 30.days.ago..) }
  
  def expired?
    expiry_date.present? && expiry_date < Date.current
  end
  
  def file_url
    Rails.application.routes.url_helpers.rails_blob_url(report_file) if report_file.attached?
  end
end
```

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_report_templates.rb
class CreateReportTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :report_templates do |t|
      t.references :business, null: true, foreign_key: true
      t.string :name, null: false
      t.integer :report_type, null: false
      t.text :description
      t.text :template_definition
      t.boolean :active, default: true
      
      t.timestamps null: false
    end
  end
end
```

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_reports.rb
class CreateReports < ActiveRecord::Migration[8.0]
  def change
    create_table :reports do |t|
      t.references :business, null: false, foreign_key: true
      t.references :report_template, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      
      t.string :name, null: false
      t.text :description
      t.text :parameters
      t.integer :status, default: 0, null: false
      t.integer :format, default: 0, null: false
      t.datetime :generated_at
      t.date :expiry_date
      t.text :result_metadata
      t.text :error_message
      
      t.timestamps null: false
    end
    
    add_index :reports, [:business_id, :created_at]
    add_index :reports, :status
  end
end
```

### Task 2: Implement Report Generation Service
**Description:** Create a service for generating compliance reports based on templates.

**Implementation Notes:**
- Build a flexible report generation engine
- Implement different output formats (PDF, CSV, Excel)
- Create data aggregation and filtering capabilities
- Handle large data sets efficiently

```ruby
# app/services/report_generator_service.rb
class ReportGeneratorService
  attr_reader :report, :template, :parameters
  
  def initialize(report)
    @report = report
    @template = report.report_template
    @parameters = report.parameters.symbolize_keys
    @business = report.business
  end
  
  def generate
    return false if report.generating?
    
    begin
      report.update!(status: :generating)
      
      # Generate the appropriate report based on template type
      case template.report_type.to_sym
      when :user_activity
        generate_user_activity_report
      when :data_changes
        generate_data_changes_report
      when :security_events
        generate_security_events_report
      when :login_attempts
        generate_login_attempts_report
      when :permission_changes
        generate_permission_changes_report
      when :gdpr_processing
        generate_gdpr_processing_report
      when :hipaa_access
        generate_hipaa_access_report
      when :pci_compliance
        generate_pci_compliance_report
      else
        raise "Unknown report type: #{template.report_type}"
      end
      
      # Finalize the report
      report.update!(
        status: :completed,
        generated_at: Time.current,
        result_metadata: {
          record_count: @record_count,
          time_taken: Time.current - report.updated_at,
          parameters: parameters
        }
      )
      
      # Send notifications if requested
      notify_completion if parameters[:notify_on_completion]
      
      true
    rescue => e
      report.update!(
        status: :failed,
        error_message: "#{e.class}: #{e.message}"
      )
      
      Rails.logger.error "Report generation failed: #{e.message}\n#{e.backtrace.join("\n")}"
      false
    end
  end
  
  private
  
  def generate_user_activity_report
    # Query user activity logs based on parameters
    start_date = parameters[:start_date] ? Date.parse(parameters[:start_date]) : 30.days.ago.to_date
    end_date = parameters[:end_date] ? Date.parse(parameters[:end_date]) : Date.current
    
    query = @business.activity_logs
      .includes(:user)
      .where(created_at: start_date.beginning_of_day..end_date.end_of_day)
      
    if parameters[:user_ids].present?
      query = query.where(user_id: parameters[:user_ids])
    end
    
    if parameters[:action_types].present?
      query = query.where(action_type: parameters[:action_types])
    end
    
    @record_count = query.count
    
    # Generate the report in the specified format
    case report.format.to_sym
    when :pdf
      generate_pdf_report(query, "User Activity Report", user_activity_columns)
    when :csv
      generate_csv_report(query, user_activity_columns)
    when :excel
      generate_excel_report(query, "User Activity", user_activity_columns)
    when :json
      generate_json_report(query.as_json(include: :user))
    end
  end
  
  def generate_data_changes_report
    # Query audit logs based on parameters
    start_date = parameters[:start_date] ? Date.parse(parameters[:start_date]) : 30.days.ago.to_date
    end_date = parameters[:end_date] ? Date.parse(parameters[:end_date]) : Date.current
    
    query = @business.audit_logs
      .includes(:user)
      .where(created_at: start_date.beginning_of_day..end_date.end_of_day)
      
    if parameters[:user_ids].present?
      query = query.where(user_id: parameters[:user_ids])
    end
    
    if parameters[:table_names].present?
      query = query.where(table_name: parameters[:table_names])
    end
    
    if parameters[:actions].present?
      query = query.where(action: parameters[:actions])
    end
    
    @record_count = query.count
    
    # Generate the report in the specified format
    case report.format.to_sym
    when :pdf
      generate_pdf_report(query, "Data Changes Report", data_changes_columns)
    when :csv
      generate_csv_report(query, data_changes_columns)
    when :excel
      generate_excel_report(query, "Data Changes", data_changes_columns)
    when :json
      generate_json_report(query.as_json(include: :user))
    end
  end
  
  def generate_security_events_report
    # Similar implementation for security events
    # Implementation specific to security events report
  end
  
  def generate_login_attempts_report
    # Implementation specific to login attempts report
  end
  
  def generate_permission_changes_report
    # Implementation specific to permission changes report
  end
  
  def generate_gdpr_processing_report
    # Implementation specific to GDPR processing report
  end
  
  def generate_hipaa_access_report
    # Implementation specific to HIPAA access report
  end
  
  def generate_pci_compliance_report
    # Implementation specific to PCI compliance report
  end
  
  # Report format generators
  
  def generate_pdf_report(query, title, columns)
    pdf = ReportPdfGenerator.new(title, @business.name, columns, query)
    pdf_file = pdf.generate
    
    report.report_file.attach(
      io: File.open(pdf_file.path),
      filename: "#{report.name.parameterize}-#{Date.current}.pdf",
      content_type: "application/pdf"
    )
    
    File.delete(pdf_file.path) if File.exist?(pdf_file.path)
  end
  
  def generate_csv_report(query, columns)
    file = Tempfile.new(["report-#{report.id}", ".csv"])
    
    CSV.open(file.path, "wb") do |csv|
      # Add header row
      csv << columns.values
      
      # Add data rows
      query.find_each do |record|
        csv << columns.keys.map { |field| extract_field_value(record, field) }
      end
    end
    
    report.report_file.attach(
      io: File.open(file.path),
      filename: "#{report.name.parameterize}-#{Date.current}.csv",
      content_type: "text/csv"
    )
    
    file.close
    file.unlink
  end
  
  def generate_excel_report(query, sheet_name, columns)
    file = Tempfile.new(["report-#{report.id}", ".xlsx"])
    
    workbook = WriteXLSX.new(file.path)
    worksheet = workbook.add_worksheet(sheet_name)
    
    # Add header row with formatting
    header_format = workbook.add_format(bold: true, bg_color: '#D9D9D9')
    columns.values.each_with_index do |header, i|
      worksheet.write(0, i, header, header_format)
    end
    
    # Add data rows
    row = 1
    query.find_each do |record|
      columns.keys.each_with_index do |field, i|
        worksheet.write(row, i, extract_field_value(record, field))
      end
      row += 1
    end
    
    workbook.close
    
    report.report_file.attach(
      io: File.open(file.path),
      filename: "#{report.name.parameterize}-#{Date.current}.xlsx",
      content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    )
    
    file.close
    file.unlink
  end
  
  def generate_json_report(data)
    file = Tempfile.new(["report-#{report.id}", ".json"])
    
    File.write(file.path, JSON.pretty_generate(data))
    
    report.report_file.attach(
      io: File.open(file.path),
      filename: "#{report.name.parameterize}-#{Date.current}.json",
      content_type: "application/json"
    )
    
    file.close
    file.unlink
  end
  
  def notify_completion
    return unless report.completed?
    
    if parameters[:email_to].present?
      ReportMailer.report_ready(report, parameters[:email_to]).deliver_later
    end
    
    if parameters[:notify_user_id].present?
      user = User.find_by(id: parameters[:notify_user_id])
      if user
        Notification.create!(
          user: user,
          notification_type: :report_ready,
          title: "Report Ready: #{report.name}",
          message: "Your requested report has been generated and is ready to download.",
          metadata: { report_id: report.id }
        )
      end
    end
  end
  
  def user_activity_columns
    {
      'created_at' => 'Timestamp',
      'user.name' => 'User',
      'action_type' => 'Activity Type',
      'controller' => 'Area',
      'action' => 'Action',
      'ip_address' => 'IP Address'
    }
  end
  
  def data_changes_columns
    {
      'created_at' => 'Timestamp',
      'user.name' => 'Changed By',
      'action' => 'Change Type',
      'table_name' => 'Entity Type',
      'auditable_id' => 'Record ID',
      'changes_summary' => 'Changes'
    }
  end
  
  def extract_field_value(record, field)
    if field.include?('.')
      parts = field.split('.')
      value = record
      parts.each do |part|
        value = value.send(part) if value.respond_to?(part)
      end
      value
    else
      record.respond_to?(field) ? record.send(field) : nil
    end
  end
end
```

```ruby
# app/jobs/generate_report_job.rb
class GenerateReportJob < ApplicationJob
  queue_as :reports
  
  def perform(report_id)
    report = Report.find_by(id: report_id)
    return unless report
    
    ReportGeneratorService.new(report).generate
  end
end
```

### Task 3: Build Report Management Interface
**Description:** Create an admin interface for managing report templates and generating reports.

**Implementation Notes:**
- Create controllers for report template management
- Implement report generation interface
- Add report scheduling capabilities
- Build report viewing and download interface

```ruby
# app/controllers/admin/reports_controller.rb
class Admin::ReportsController < Admin::BaseController
  before_action :require_admin
  before_action :set_report, only: [:show, :download, :destroy]
  
  def index
    @reports = current_business.reports
      .includes(:report_template, :created_by)
      .order(created_at: :desc)
      .paginate(page: params[:page], per_page: 20)
  end
  
  def new
    @report = current_business.reports.new
    @templates = ReportTemplate.templates_for(current_business)
    @users = current_business.users.order(:name)
  end
  
  def create
    @report = current_business.reports.new(report_params)
    @report.created_by = current_user
    
    if @report.save
      GenerateReportJob.perform_later(@report.id)
      
      flash[:success] = "Report generation has been queued."
      redirect_to admin_reports_path
    else
      @templates = ReportTemplate.templates_for(current_business)
      @users = current_business.users.order(:name)
      
      flash.now[:error] = "Failed to create report: #{@report.errors.full_messages.join(', ')}"
      render :new
    end
  end
  
  def show
    if @report.report_file.attached?
      # Get metadata for display
      @metadata = @report.result_metadata || {}
    end
  end
  
  def download
    if @report.report_file.attached?
      redirect_to rails_blob_url(@report.report_file, disposition: "attachment")
    else
      flash[:error] = "Report file not found"
      redirect_to admin_report_path(@report)
    end
  end
  
  def destroy
    if @report.destroy
      flash[:success] = "Report deleted successfully."
    else
      flash[:error] = "Failed to delete report."
    end
    
    redirect_to admin_reports_path
  end
  
  private
  
  def set_report
    @report = current_business.reports.find(params[:id])
  end
  
  def report_params
    params.require(:report).permit(
      :name, 
      :description, 
      :report_template_id, 
      :format,
      :expiry_date,
      parameters: [
        :start_date, 
        :end_date, 
        :notify_on_completion,
        :email_to, 
        :notify_user_id,
        { user_ids: [], action_types: [], table_names: [] }
      ]
    )
  end
end
```

```ruby
# app/controllers/admin/report_templates_controller.rb
class Admin::ReportTemplatesController < Admin::BaseController
  before_action :require_admin
  before_action :set_template, only: [:show, :edit, :update, :destroy]
  
  def index
    @system_templates = ReportTemplate.system_templates.order(:name)
    @custom_templates = current_business.report_templates.order(:name)
  end
  
  def show
  end
  
  def new
    @template = current_business.report_templates.new
  end
  
  def create
    @template = current_business.report_templates.new(template_params)
    
    if @template.save
      flash[:success] = "Report template created successfully."
      redirect_to admin_report_templates_path
    else
      flash.now[:error] = "Failed to create template: #{@template.errors.full_messages.join(', ')}"
      render :new
    end
  end
  
  def edit
  end
  
  def update
    if @template.update(template_params)
      flash[:success] = "Report template updated successfully."
      redirect_to admin_report_templates_path
    else
      flash.now[:error] = "Failed to update template: #{@template.errors.full_messages.join(', ')}"
      render :edit
    end
  end
  
  def destroy
    if @template.destroy
      flash[:success] = "Report template deleted successfully."
    else
      flash[:error] = "Failed to delete template."
    end
    
    redirect_to admin_report_templates_path
  end
  
  private
  
  def set_template
    @template = current_business.report_templates.find(params[:id])
  end
  
  def template_params
    params.require(:report_template).permit(
      :name,
      :report_type,
      :description,
      :active,
      template_definition: {}
    )
  end
end
```

```ruby
# app/controllers/admin/scheduled_reports_controller.rb
class Admin::ScheduledReportsController < Admin::BaseController
  before_action :require_admin
  before_action :set_scheduled_report, only: [:show, :edit, :update, :destroy, :toggle_active]
  
  def index
    @scheduled_reports = current_business.scheduled_reports
      .includes(:report_template, :created_by)
      .order(next_run_at: :asc)
      .paginate(page: params[:page], per_page: 20)
  end
  
  def new
    @scheduled_report = current_business.scheduled_reports.new
    @templates = ReportTemplate.templates_for(current_business)
    @users = current_business.users.order(:name)
  end
  
  def create
    @scheduled_report = current_business.scheduled_reports.new(scheduled_report_params)
    @scheduled_report.created_by = current_user
    
    if @scheduled_report.save
      flash[:success] = "Scheduled report created successfully."
      redirect_to admin_scheduled_reports_path
    else
      @templates = ReportTemplate.templates_for(current_business)
      @users = current_business.users.order(:name)
      
      flash.now[:error] = "Failed to create scheduled report: #{@scheduled_report.errors.full_messages.join(', ')}"
      render :new
    end
  end
  
  def edit
    @templates = ReportTemplate.templates_for(current_business)
    @users = current_business.users.order(:name)
  end
  
  def update
    if @scheduled_report.update(scheduled_report_params)
      flash[:success] = "Scheduled report updated successfully."
      redirect_to admin_scheduled_reports_path
    else
      @templates = ReportTemplate.templates_for(current_business)
      @users = current_business.users.order(:name)
      
      flash.now[:error] = "Failed to update scheduled report: #{@scheduled_report.errors.full_messages.join(', ')}"
      render :edit
    end
  end
  
  def destroy
    if @scheduled_report.destroy
      flash[:success] = "Scheduled report deleted successfully."
    else
      flash[:error] = "Failed to delete scheduled report."
    end
    
    redirect_to admin_scheduled_reports_path
  end
  
  def toggle_active
    if @scheduled_report.update(active: !@scheduled_report.active)
      flash[:success] = "Scheduled report #{@scheduled_report.active? ? 'activated' : 'deactivated'} successfully."
    else
      flash[:error] = "Failed to update scheduled report status."
    end
    
    redirect_to admin_scheduled_reports_path
  end
  
  private
  
  def set_scheduled_report
    @scheduled_report = current_business.scheduled_reports.find(params[:id])
  end
  
  def scheduled_report_params
    params.require(:scheduled_report).permit(
      :name, 
      :description, 
      :report_template_id, 
      :schedule_type,
      :day_of_week,
      :day_of_month,
      :hour_of_day,
      :format,
      :expiry_days,
      :active,
      :notify_on_completion,
      :email_to,
      :notify_user_id,
      parameters: [
        :notify_on_completion,
        :email_to, 
        :notify_user_id,
        { user_ids: [], action_types: [], table_names: [] }
      ]
    )
  end
end
```

### Task 4: Implement Report Scheduling System
**Description:** Create a system for scheduling recurring compliance reports.

**Implementation Notes:**
- Create scheduled report model
- Implement scheduling logic for different frequencies
- Add background job for automatic report generation
- Build email delivery for scheduled reports

```ruby
# app/models/scheduled_report.rb
class ScheduledReport < ApplicationRecord
  belongs_to :business
  belongs_to :report_template
  belongs_to :created_by, class_name: 'User'
  has_many :reports, dependent: :nullify
  
  validates :name, :schedule_type, :hour_of_day, presence: true
  validates :day_of_week, presence: true, if: -> { schedule_type == 'weekly' }
  validates :day_of_month, presence: true, if: -> { schedule_type == 'monthly' }
  validates :hour_of_day, numericality: { greater_than_or_equal_to: 0, less_than: 24 }
  validates :day_of_week, numericality: { greater_than_or_equal_to: 0, less_than: 7 }, allow_nil: true
  validates :day_of_month, numericality: { greater_than_or_equal_to: 1, less_than_or_equal_to: 31 }, allow_nil: true
  
  serialize :parameters, Hash
  
  enum schedule_type: {
    daily: 0,
    weekly: 1,
    monthly: 2
  }
  
  enum format: {
    pdf: 0,
    csv: 1,
    excel: 2,
    json: 3
  }
  
  scope :active, -> { where(active: true) }
  scope :due_for_generation, -> { active.where('next_run_at <= ?', Time.current) }
  
  before_save :set_next_run_at, if: -> { schedule_type_changed? || hour_of_day_changed? || day_of_week_changed? || day_of_month_changed? || (active_changed? && active) || new_record? }
  
  def trigger_report_generation
    return false unless active?
    
    # Create a new report based on the scheduled report
    report = business.reports.create!(
      name: "#{name} - #{Date.current}",
      description: description,
      report_template: report_template,
      created_by: created_by,
      format: format,
      parameters: parameters,
      expiry_date: expiry_days.present? ? Date.current + expiry_days.days : nil
    )
    
    # Queue the report generation
    GenerateReportJob.perform_later(report.id)
    
    # Update the next run time
    update_next_run_at!
    
    report
  end
  
  def update_next_run_at!
    update!(next_run_at: calculate_next_run)
  end
  
  private
  
  def set_next_run_at
    self.next_run_at = calculate_next_run
  end
  
  def calculate_next_run
    now = Time.current
    target_hour = hour_of_day
    
    case schedule_type
    when 'daily'
      if now.hour >= target_hour
        # If we're past the target hour today, schedule for tomorrow
        Date.current.tomorrow.to_time.change(hour: target_hour)
      else
        # Schedule for today
        Date.current.to_time.change(hour: target_hour)
      end
    when 'weekly'
      target_day = day_of_week
      current_day = now.wday
      
      if current_day > target_day || (current_day == target_day && now.hour >= target_hour)
        # If we're past the target day/hour this week, schedule for next week
        days_to_add = 7 - current_day + target_day
      else
        # Schedule for this week
        days_to_add = target_day - current_day
      end
      
      (Date.current + days_to_add.days).to_time.change(hour: target_hour)
    when 'monthly'
      target_day = day_of_month
      current_day = now.day
      
      # Find the next occurrence of this day in the current or next month
      if current_day > target_day || (current_day == target_day && now.hour >= target_hour)
        # Move to next month
        next_month = now.next_month
      else
        # Stay in current month
        next_month = now
      end
      
      # Handle cases where the day might not exist in the month (e.g., February 30th)
      days_in_month = Date.new(next_month.year, next_month.month, -1).day
      target_day = [target_day, days_in_month].min
      
      Date.new(next_month.year, next_month.month, target_day).to_time.change(hour: target_hour)
    else
      now + 1.day
    end
  end
end
```

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_scheduled_reports.rb
class CreateScheduledReports < ActiveRecord::Migration[8.0]
  def change
    create_table :scheduled_reports do |t|
      t.references :business, null: false, foreign_key: true
      t.references :report_template, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      
      t.string :name, null: false
      t.text :description
      t.integer :schedule_type, default: 0, null: false
      t.integer :day_of_week
      t.integer :day_of_month
      t.integer :hour_of_day, null: false
      t.integer :format, default: 0, null: false
      t.integer :expiry_days
      t.boolean :active, default: true
      t.datetime :next_run_at
      t.datetime :last_run_at
      t.text :parameters
      
      t.timestamps null: false
    end
    
    add_index :scheduled_reports, [:business_id, :active]
    add_index :scheduled_reports, :next_run_at
  end
end
```

```ruby
# app/jobs/process_scheduled_reports_job.rb
class ProcessScheduledReportsJob < ApplicationJob
  queue_as :reports
  
  def perform
    # Find all scheduled reports that are due for generation
    ScheduledReport.due_for_generation.find_each do |scheduled_report|
      # Trigger report generation for each scheduled report
      report = scheduled_report.trigger_report_generation
      
      # Log the result
      if report
        Rails.logger.info "Generated scheduled report: #{report.id} for schedule: #{scheduled_report.id}"
      else
        Rails.logger.error "Failed to generate report for schedule: #{scheduled_report.id}"
      end
    end
  end
end
```

```ruby
# config/initializers/scheduler.rb
if defined?(Rails::Server) && !Rails.env.test?
  require 'rufus-scheduler'
  
  # Create a scheduler instance
  scheduler = Rufus::Scheduler.singleton
  
  # Schedule the job to run every 10 minutes
  scheduler.every '10m' do
    ProcessScheduledReportsJob.perform_later
  end
end
```

### Task 5: Add Report Archiving and Compliance Validation
**Description:** Implement a system for securely archiving reports and validating compliance.

**Implementation Notes:**
- Create report archiving capabilities
- Implement compliance validation checks
- Build retention policy management
- Add digital signatures for report integrity

```ruby
# app/models/report_archive.rb
class ReportArchive < ApplicationRecord
  belongs_to :business
  belongs_to :created_by, class_name: 'User'
  
  validates :name, :archive_date, presence: true
  
  has_one_attached :archive_file
  has_one_attached :signature_file
  
  enum status: {
    preparing: 0,
    completed: 1,
    failed: 2
  }
  
  serialize :metadata, Hash
  
  scope :by_year, ->(year) { where('extract(year from archive_date) = ?', year) }
  scope :by_month, ->(month) { where('extract(month from archive_date) = ?', month) }
  scope :by_date_range, ->(start_date, end_date) { where(archive_date: start_date..end_date) }
  
  def file_url
    Rails.application.routes.url_helpers.rails_blob_url(archive_file) if archive_file.attached?
  end
  
  def signature_url
    Rails.application.routes.url_helpers.rails_blob_url(signature_file) if signature_file.attached?
  end
  
  def verify_signature
    return false unless archive_file.attached? && signature_file.attached?
    
    # Implementation would depend on the digital signature method used
    # Example using OpenSSL for a simple verification:
    begin
      digest = OpenSSL::Digest::SHA256.new
      public_key = OpenSSL::PKey::RSA.new(File.read(Rails.root.join('config', 'certs', 'report_signing_public.pem')))
      
      archive_data = StringIO.new
      archive_file.download { |chunk| archive_data << chunk }
      
      signature_data = StringIO.new
      signature_file.download { |chunk| signature_data << chunk }
      
      public_key.verify(digest, signature_data.string, archive_data.string)
    rescue => e
      Rails.logger.error "Signature verification failed: #{e.message}"
      false
    end
  end
end
```

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_report_archives.rb
class CreateReportArchives < ActiveRecord::Migration[8.0]
  def change
    create_table :report_archives do |t|
      t.references :business, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      
      t.string :name, null: false
      t.text :description
      t.date :archive_date, null: false
      t.date :retention_date
      t.integer :status, default: 0, null: false
      t.text :metadata
      t.text :compliance_frameworks
      
      t.timestamps null: false
    end
    
    add_index :report_archives, [:business_id, :archive_date]
    add_index :report_archives, :retention_date
  end
end
```

```ruby
# app/services/report_archiver_service.rb
class ReportArchiverService
  attr_reader :archive, :business, :date_range, :compliance_frameworks
  
  def initialize(archive)
    @archive = archive
    @business = archive.business
    @date_range = archive.metadata[:start_date]..archive.metadata[:end_date]
    @compliance_frameworks = archive.metadata[:compliance_frameworks] || []
  end
  
  def archive_reports
    return false if archive.preparing?
    
    begin
      archive.update!(status: :preparing)
      
      # Find reports to archive
      reports = business.reports
        .where(created_at: date_range)
        .where(status: :completed)
        .where.not(report_file_attachment: nil)
      
      if reports.empty?
        archive.update!(
          status: :failed,
          metadata: archive.metadata.merge(
            error_message: "No completed reports found in the specified date range"
          )
        )
        return false
      end
      
      # Create a zip file containing all reports
      zip_file = create_archive_zip(reports)
      
      # Generate a digital signature for the zip
      signature_file = generate_signature(zip_file.path)
      
      # Attach files to the archive record
      archive.archive_file.attach(
        io: File.open(zip_file.path),
        filename: "#{archive.name.parameterize}-#{Date.current}.zip",
        content_type: "application/zip"
      )
      
      archive.signature_file.attach(
        io: File.open(signature_file.path),
        filename: "#{archive.name.parameterize}-#{Date.current}.sig",
        content_type: "application/octet-stream"
      )
      
      # Update archive metadata
      archive.update!(
        status: :completed,
        metadata: archive.metadata.merge(
          report_count: reports.count,
          report_ids: reports.pluck(:id),
          file_size: File.size(zip_file.path),
          signature_algorithm: "RSA-SHA256",
          completed_at: Time.current
        )
      )
      
      # Cleanup temp files
      File.delete(zip_file.path) if File.exist?(zip_file.path)
      File.delete(signature_file.path) if File.exist?(signature_file.path)
      
      true
    rescue => e
      archive.update!(
        status: :failed,
        metadata: archive.metadata.merge(
          error_message: "#{e.class}: #{e.message}"
        )
      )
      
      Rails.logger.error "Archive creation failed: #{e.message}\n#{e.backtrace.join("\n")}"
      false
    end
  end
  
  private
  
  def create_archive_zip(reports)
    temp_zip = Tempfile.new(["archive-#{archive.id}", ".zip"])
    
    Zip::File.open(temp_zip.path, Zip::File::CREATE) do |zipfile|
      reports.find_each do |report|
        next unless report.report_file.attached?
        
        # Download the report file to a temp location
        temp_file = Tempfile.new(["report-#{report.id}", File.extname(report.report_file.filename.to_s)])
        report.report_file.download { |chunk| temp_file.write(chunk) }
        temp_file.close
        
        # Add report file to zip
        zipfile.add(
          "#{report.id}-#{report.report_file.filename}",
          temp_file.path
        )
        
        # Add report metadata as JSON
        report_metadata = {
          id: report.id,
          name: report.name,
          description: report.description,
          template: report.report_template.name,
          generated_at: report.generated_at,
          created_by: report.created_by.name,
          format: report.format,
          parameters: report.parameters
        }.to_json
        
        metadata_file = Tempfile.new(["metadata-#{report.id}", ".json"])
        metadata_file.write(report_metadata)
        metadata_file.close
        
        zipfile.add(
          "#{report.id}-metadata.json",
          metadata_file.path
        )
        
        # Clean up temp files
        File.delete(temp_file.path) if File.exist?(temp_file.path)
        File.delete(metadata_file.path) if File.exist?(metadata_file.path)
      end
      
      # Add manifest file
      manifest = {
        archive_id: archive.id,
        business_id: business.id,
        business_name: business.name,
        created_at: Time.current,
        created_by: archive.created_by.name,
        report_count: reports.count,
        date_range: {
          start_date: date_range.begin,
          end_date: date_range.end
        },
        compliance_frameworks: compliance_frameworks
      }.to_json
      
      manifest_file = Tempfile.new(["manifest", ".json"])
      manifest_file.write(manifest)
      manifest_file.close
      
      zipfile.add("manifest.json", manifest_file.path)
      
      # Clean up manifest file
      File.delete(manifest_file.path) if File.exist?(manifest_file.path)
    end
    
    temp_zip
  end
  
  def generate_signature(file_path)
    # Implementation depends on the signing method
    # Example using OpenSSL for a simple signature:
    digest = OpenSSL::Digest::SHA256.new
    private_key = OpenSSL::PKey::RSA.new(File.read(Rails.root.join('config', 'certs', 'report_signing_private.pem')))
    
    file_data = File.read(file_path)
    signature = private_key.sign(digest, file_data)
    
    temp_sig = Tempfile.new(["signature-#{archive.id}", ".sig"])
    temp_sig.write(signature)
    temp_sig.close
    
    temp_sig
  end
end
```

```ruby
# app/controllers/admin/report_archives_controller.rb
class Admin::ReportArchivesController < Admin::BaseController
  before_action :require_admin
  before_action :set_archive, only: [:show, :download, :verify, :destroy]
  
  def index
    @archives = current_business.report_archives
      .includes(:created_by)
      .order(archive_date: :desc)
      .paginate(page: params[:page], per_page: 20)
      
    # Group archives by year for better organization
    @archives_by_year = @archives.to_a.group_by { |a| a.archive_date.year }
  end
  
  def new
    @archive = current_business.report_archives.new
    @archive.archive_date = Date.current
    @compliance_frameworks = compliance_frameworks_options
  end
  
  def create
    @archive = current_business.report_archives.new(archive_params)
    @archive.created_by = current_user
    
    # Set metadata with date range and compliance frameworks
    start_date = Date.parse(params[:start_date]) if params[:start_date].present?
    end_date = Date.parse(params[:end_date]) if params[:end_date].present?
    
    @archive.metadata = {
      start_date: start_date || 30.days.ago.to_date,
      end_date: end_date || Date.current,
      compliance_frameworks: params[:compliance_frameworks] || []
    }
    
    if @archive.save
      # Queue the archiving process
      ArchiveReportsJob.perform_later(@archive.id)
      
      flash[:success] = "Archive creation has been queued."
      redirect_to admin_report_archives_path
    else
      @compliance_frameworks = compliance_frameworks_options
      
      flash.now[:error] = "Failed to create archive: #{@archive.errors.full_messages.join(', ')}"
      render :new
    end
  end
  
  def show
  end
  
  def download
    if @archive.archive_file.attached?
      redirect_to rails_blob_url(@archive.archive_file, disposition: "attachment")
    else
      flash[:error] = "Archive file not found"
      redirect_to admin_report_archive_path(@archive)
    end
  end
  
  def verify
    if @archive.archive_file.attached? && @archive.signature_file.attached?
      valid = @archive.verify_signature
      
      if valid
        flash[:success] = "Archive signature is valid and verified."
      else
        flash[:error] = "Archive signature validation failed. The archive may have been tampered with."
      end
    else
      flash[:error] = "Archive or signature file is missing."
    end
    
    redirect_to admin_report_archive_path(@archive)
  end
  
  def destroy
    if @archive.destroy
      flash[:success] = "Archive deleted successfully."
    else
      flash[:error] = "Failed to delete archive."
    end
    
    redirect_to admin_report_archives_path
  end
  
  private
  
  def set_archive
    @archive = current_business.report_archives.find(params[:id])
  end
  
  def archive_params
    params.require(:report_archive).permit(
      :name,
      :description,
      :archive_date,
      :retention_date
    )
  end
  
  def compliance_frameworks_options
    [
      { id: 'gdpr', name: 'GDPR' },
      { id: 'hipaa', name: 'HIPAA' },
      { id: 'pci', name: 'PCI DSS' },
      { id: 'sox', name: 'Sarbanes-Oxley' }
    ]
  end
end
```

## Security Considerations
- Ensure report data is encrypted at rest
- Implement digital signatures for report integrity verification
- Establish strict access controls for compliance reports
- Log all report generation and access events
- Maintain secure archiving for the required retention period
- Apply proper retention and deletion policies

## Testing Strategy
- Unit tests for report generation logic
- Integration tests for report scheduling
- Security testing for archived report integrity
- Performance testing for large report generation
- Validation tests for compliance requirements

## Rollout Plan
1. Deploy report template system
2. Add on-demand report generation
3. Implement report scheduling
4. Add report archiving functionality
5. Create compliance-specific report templates
6. Documentation for compliance officers
