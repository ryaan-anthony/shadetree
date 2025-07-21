# Feature: Job Record Custom Fields

## Overview
Enable businesses to capture job-specific information and project details through custom fields attached to job records. This allows for better project tracking, service documentation, and operational insights.

## User Stories
- As a business owner, I want to record job-specific information so I can track project details
- As a staff member, I want to capture service delivery details for documentation
- As a business owner, I want to analyze job data to improve service delivery

## Tasks

### 1. Create Job Model with Custom Fields
**File**: `app/models/job.rb`

**Implementation Notes**:
```ruby
class Job < ApplicationRecord
  belongs_to :business
  belongs_to :client
  belongs_to :quote, optional: true
  belongs_to :assigned_staff, class_name: 'User', optional: true
  has_many :custom_field_values, as: :record, dependent: :destroy
  
  validates :title, :status, presence: true
  validates :scheduled_date, presence: true, if: :scheduled?
  
  enum status: { 
    pending: 0, 
    scheduled: 1, 
    in_progress: 2, 
    completed: 3, 
    cancelled: 4 
  }
  
  scope :active, -> { where.not(status: :cancelled) }
  scope :upcoming, -> { where(status: [:pending, :scheduled]).where('scheduled_date > ?', Time.current) }
  
  def custom_field_value_for(field)
    custom_field_values.find_by(custom_field: field)&.value
  end
  
  def set_custom_field_value(field, value)
    field_value = custom_field_values.find_or_initialize_by(custom_field: field)
    field_value.value = value
    field_value.save!
  end
  
  def custom_fields_data
    business.custom_fields.for_context('job_record').active.map do |field|
      {
        field: field,
        value: custom_field_value_for(field),
        formatted_value: custom_field_values.find_by(custom_field: field)&.formatted_value
      }
    end
  end
  
  def duration_hours
    return nil unless completed_at && started_at
    ((completed_at - started_at) / 1.hour).round(2)
  end
end
```

### 2. Create Jobs Controller with Custom Fields
**File**: `app/controllers/admin/jobs_controller.rb`

**Implementation Notes**:
```ruby
class Admin::JobsController < Admin::BaseController
  before_action :set_job, only: [:show, :edit, :update, :destroy, :start, :complete]
  
  def index
    @jobs = current_business.jobs
      .includes(:client, :assigned_staff, :custom_field_values)
      .order(scheduled_date: :asc)
    @custom_fields = current_business.custom_fields.for_context('job_record').active
  end
  
  def show
    @custom_field_data = @job.custom_fields_data
  end
  
  def new
    @job = current_business.jobs.build
    @job.client_id = params[:client_id] if params[:client_id]
    @job.quote_id = params[:quote_id] if params[:quote_id]
    @custom_fields = current_business.custom_fields.for_context('job_record').active
  end
  
  def create
    @job = current_business.jobs.build(job_params)
    
    if @job.save
      save_custom_field_values
      redirect_to admin_job_path(@job), notice: 'Job created successfully'
    else
      @custom_fields = current_business.custom_fields.for_context('job_record').active
      render :new, status: :unprocessable_entity
    end
  end
  
  def edit
    @custom_fields = current_business.custom_fields.for_context('job_record').active
  end
  
  def update
    if @job.update(job_params)
      save_custom_field_values
      redirect_to admin_job_path(@job), notice: 'Job updated successfully'
    else
      @custom_fields = current_business.custom_fields.for_context('job_record').active
      render :edit, status: :unprocessable_entity
    end
  end
  
  def start
    @job.update!(status: 'in_progress', started_at: Time.current)
    redirect_to admin_job_path(@job), notice: 'Job started'
  end
  
  def complete
    @job.update!(status: 'completed', completed_at: Time.current)
    save_custom_field_values if params[:job]
    redirect_to admin_job_path(@job), notice: 'Job completed'
  end
  
  private
  
  def set_job
    @job = current_business.jobs.find(params[:id])
  end
  
  def job_params
    params.require(:job).permit(
      :title, :description, :client_id, :quote_id, :assigned_staff_id,
      :scheduled_date, :estimated_duration, :status, :notes
    )
  end
  
  def save_custom_field_values
    custom_field_params.each do |field_name, value|
      next if value.blank?
      
      field_id = field_name.gsub('custom_field_', '').to_i
      field = current_business.custom_fields.find(field_id)
      @job.set_custom_field_value(field, value)
    end
  end
  
  def custom_field_params
    params.permit(current_business.custom_fields.for_context('job_record').active.map(&:form_name))
  end
end
```

### 3. Create Job Completion Form with Custom Fields
**File**: `app/views/admin/jobs/_completion_form.html.erb`

**Implementation Notes**:
```erb
<%= form_with model: [:admin, job], url: complete_admin_job_path(job), 
              class: "space-y-6", data: { turbo_method: :patch } do |form| %>
  
  <div class="bg-white shadow rounded-lg p-6">
    <h3 class="text-lg font-medium text-gray-900 mb-4">Complete Job</h3>
    
    <!-- Job Completion Details -->
    <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mb-6">
      <div>
        <label class="block text-sm font-medium text-gray-700 mb-1">
          Actual Duration (hours)
        </label>
        <input type="number" name="actual_duration" step="0.25" 
               class="block w-full border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500"
               placeholder="e.g. 2.5">
      </div>
      
      <div>
        <label class="block text-sm font-medium text-gray-700 mb-1">
          Completion Quality
        </label>
        <select name="completion_quality" 
                class="block w-full border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500">
          <option value="">Select quality rating</option>
          <option value="excellent">Excellent</option>
          <option value="good">Good</option>
          <option value="satisfactory">Satisfactory</option>
          <option value="needs_improvement">Needs Improvement</option>
        </select>
      </div>
    </div>

    <!-- Custom Fields for Job Completion -->
    <% completion_fields = current_business.custom_fields.for_context('job_record').active %>
    <% if completion_fields.any? %>
      <div class="border-t border-gray-200 pt-6">
        <h4 class="text-md font-medium text-gray-900 mb-4">Job Details</h4>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
          <% completion_fields.each do |field| %>
            <div>
              <%= render CustomFieldComponent.new(
                field: field,
                form: form,
                value: job.custom_field_value_for(field)
              ) %>
            </div>
          <% end %>
        </div>
      </div>
    <% end %>

    <!-- Completion Notes -->
    <div class="border-t border-gray-200 pt-6">
      <label class="block text-sm font-medium text-gray-700 mb-1">
        Completion Notes
      </label>
      <textarea name="completion_notes" rows="4"
                class="block w-full border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500"
                placeholder="Any additional notes about the completed work..."></textarea>
    </div>

    <div class="flex justify-end space-x-4 pt-6">
      <%= link_to "Cancel", admin_job_path(job),
          class: "px-4 py-2 border border-gray-300 rounded-md text-gray-700 hover:bg-gray-50" %>
      <%= form.submit "Complete Job",
          class: "px-4 py-2 bg-green-600 text-white rounded-md hover:bg-green-700" %>
    </div>
  </div>
<% end %>
```

### 4. Create Job Analytics Service
**File**: `app/services/job_analytics_service.rb`

**Implementation Notes**:
```ruby
class JobAnalyticsService
  def initialize(business)
    @business = business
  end
  
  def custom_field_analytics
    job_custom_fields = @business.custom_fields.for_context('job_record').active
    
    job_custom_fields.map do |field|
      {
        field: field,
        usage_count: field.custom_field_values.count,
        completion_rate: calculate_completion_rate(field),
        common_values: most_common_values(field)
      }
    end
  end
  
  def job_efficiency_metrics
    completed_jobs = @business.jobs.completed.includes(:custom_field_values)
    
    {
      average_duration: calculate_average_duration(completed_jobs),
      quality_distribution: calculate_quality_distribution(completed_jobs),
      custom_field_insights: extract_custom_field_insights(completed_jobs)
    }
  end
  
  private
  
  def calculate_completion_rate(field)
    total_jobs = @business.jobs.count
    return 0 if total_jobs.zero?
    
    jobs_with_field = field.custom_field_values
      .where(record_type: 'Job')
      .where('value IS NOT NULL AND value != ""')
      .count
      
    (jobs_with_field.to_f / total_jobs * 100).round(2)
  end
  
  def most_common_values(field)
    field.custom_field_values
      .where(record_type: 'Job')
      .where('value IS NOT NULL AND value != ""')
      .group(:value)
      .order('count_value DESC')
      .limit(5)
      .count(:value)
  end
  
  def calculate_average_duration(jobs)
    durations = jobs.filter_map(&:duration_hours)
    return 0 if durations.empty?
    
    (durations.sum / durations.length).round(2)
  end
  
  def extract_custom_field_insights(jobs)
    insights = {}
    
    jobs.each do |job|
      job.custom_fields_data.each do |data|
        field_name = data[:field].name
        value = data[:value]
        
        next if value.blank?
        
        insights[field_name] ||= { values: [], jobs_count: 0 }
        insights[field_name][:values] << value
        insights[field_name][:jobs_count] += 1
      end
    end
    
    insights
  end
end
```

### 5. Create Database Migration
**File**: `db/migrate/xxx_create_jobs.rb`

**Implementation Notes**:
```ruby
class CreateJobs < ActiveRecord::Migration[8.0]
  def change
    create_table :jobs do |t|
      t.references :business, null: false, foreign_key: true
      t.references :client, null: false, foreign_key: true
      t.references :quote, null: true, foreign_key: true
      t.references :assigned_staff, null: true, foreign_key: { to_table: :users }
      
      t.string :title, null: false
      t.text :description
      t.integer :status, default: 0
      t.datetime :scheduled_date
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :estimated_duration # in minutes
      t.text :notes
      
      t.timestamps
    end
    
    add_index :jobs, [:business_id, :status]
    add_index :jobs, [:business_id, :scheduled_date]
    add_index :jobs, [:business_id, :client_id]
    add_index :jobs, [:assigned_staff_id, :status]
  end
end
```

## Acceptance Criteria
- Jobs can have custom field values for project-specific data
- Custom fields appear in job creation, editing, and completion forms
- Job completion captures additional custom field data
- Custom field values are displayed in job detail view
- Job analytics include custom field insights
- Custom field validation applies to job data

## Estimate
- Story Points: 8
- Timeline: 1 week
- Dependencies: CustomField system, Job model, Client model
