# Feature: Workflow Engine

## Overview
Implement the core execution engine that processes workflows, manages state transitions, handles errors, and ensures reliable automation of business processes.

## User Stories
- As a business owner, I want workflows to execute automatically when triggered
- As a business owner, I want to see workflow execution status and handle failures
- As a developer, I want reliable workflow execution with error handling and retries

## Tasks

### 1. Create WorkflowExecution Model
**File**: `app/models/workflow_execution.rb`

**Implementation Notes**:
```ruby
class WorkflowExecution < ApplicationRecord
  belongs_to :workflow
  belongs_to :source, polymorphic: true
  belongs_to :triggered_by, class_name: 'User', optional: true
  has_many :workflow_step_executions, dependent: :destroy
  
  validates :status, presence: true
  
  enum status: { running: 0, completed: 1, failed: 2, cancelled: 3 }
  
  scope :active, -> { where(status: 'running') }
  scope :recent, -> { where(created_at: 1.week.ago..) }
  
  def current_step
    workflow_step_executions.running.first&.workflow_step
  end
  
  def progress_percentage
    total_steps = workflow.workflow_steps.count
    return 0 if total_steps.zero?
    
    completed_steps = workflow_step_executions.completed.count
    (completed_steps.to_f / total_steps * 100).round(1)
  end
  
  def execution_time
    return nil unless completed_at || failed_at
    
    end_time = completed_at || failed_at
    (end_time - created_at).round(2)
  end
  
  def next_step_to_execute
    # Find the next step that hasn't been executed yet
    executed_step_ids = workflow_step_executions.pluck(:workflow_step_id)
    
    workflow.workflow_steps
      .where.not(id: executed_step_ids)
      .joins('LEFT JOIN workflow_steps prev ON prev.id = workflow_steps.previous_step_id')
      .where('prev.id IS NULL OR prev.id IN (?)', executed_step_ids)
      .order(:display_order)
      .first
  end
end
```

### 2. Create WorkflowStepExecution Model
**File**: `app/models/workflow_step_execution.rb`

**Implementation Notes**:
```ruby
class WorkflowStepExecution < ApplicationRecord
  belongs_to :workflow_execution
  belongs_to :workflow_step
  
  validates :status, presence: true
  
  enum status: { pending: 0, running: 1, completed: 2, failed: 3, skipped: 4 }
  
  scope :completed, -> { where(status: 'completed') }
  scope :failed, -> { where(status: 'failed') }
  
  def execution_time
    return nil unless completed_at || failed_at
    
    end_time = completed_at || failed_at
    (end_time - started_at).round(2) if started_at
  end
  
  def mark_as_started!
    update!(status: :running, started_at: Time.current)
  end
  
  def mark_as_completed!(result_data = nil)
    update!(
      status: :completed,
      completed_at: Time.current,
      result_data: result_data
    )
  end
  
  def mark_as_failed!(error_message, result_data = nil)
    update!(
      status: :failed,
      failed_at: Time.current,
      error_message: error_message,
      result_data: result_data
    )
  end
  
  def mark_as_skipped!(reason)
    update!(
      status: :skipped,
      completed_at: Time.current,
      error_message: reason
    )
  end
end
```

### 3. Create WorkflowEngine Service
**File**: `app/services/workflow_engine.rb`

**Implementation Notes**:
```ruby
class WorkflowEngine
  def self.trigger(event, source_object, triggered_by = nil)
    business = source_object.business
    workflows = business.workflows.active.for_event(event)
    
    workflows.each do |workflow|
      execution = WorkflowExecution.create!(
        workflow: workflow,
        source: source_object,
        triggered_by: triggered_by,
        status: :running
      )
      
      WorkflowExecutionJob.perform_later(execution.id)
    end
  end
  
  def initialize(execution)
    @execution = execution
    @workflow = execution.workflow
    @source = execution.source
  end
  
  def execute
    begin
      execute_workflow_steps
      @execution.update!(status: :completed, completed_at: Time.current)
    rescue WorkflowExecutionError => e
      @execution.update!(
        status: :failed,
        failed_at: Time.current,
        error_message: e.message
      )
      raise e
    rescue => e
      @execution.update!(
        status: :failed,
        failed_at: Time.current,
        error_message: "Unexpected error: #{e.message}"
      )
      Rails.logger.error "Workflow execution failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise e
    end
  end
  
  private
  
  def execute_workflow_steps
    current_step = @workflow.first_step
    
    while current_step
      step_execution = execute_step(current_step)
      
      case step_execution.status
      when 'completed'
        current_step = determine_next_step(current_step, step_execution)
      when 'failed'
        handle_step_failure(step_execution)
        break
      when 'skipped'
        current_step = current_step.next_steps.first
      end
    end
  end
  
  def execute_step(step)
    step_execution = @execution.workflow_step_executions.create!(
      workflow_step: step,
      status: :pending
    )
    
    step_execution.mark_as_started!
    
    begin
      result = WorkflowStepExecutor.new(step, @source, @execution).execute
      step_execution.mark_as_completed!(result)
    rescue => error
      step_execution.mark_as_failed!(error.message)
      raise WorkflowExecutionError.new("Step '#{step.name}' failed: #{error.message}")
    end
    
    step_execution
  end
  
  def determine_next_step(current_step, step_execution)
    # Simple linear execution for MVP
    # Future: Add conditional logic based on step results
    current_step.next_steps.first
  end
  
  def handle_step_failure(step_execution)
    step = step_execution.workflow_step
    
    # Check if step has retry configuration
    if step.configuration['retry_count'].to_i > 0
      attempt_retry(step_execution)
    else
      raise WorkflowExecutionError.new("Workflow failed at step: #{step.name}")
    end
  end
  
  def attempt_retry(step_execution)
    retry_count = step_execution.workflow_step.configuration['retry_count'].to_i
    current_attempts = @execution.workflow_step_executions
      .where(workflow_step: step_execution.workflow_step)
      .failed
      .count
    
    if current_attempts < retry_count
      # Schedule retry
      WorkflowStepRetryJob.perform_in(
        30.seconds,
        @execution.id,
        step_execution.workflow_step.id
      )
    else
      raise WorkflowExecutionError.new("Step failed after #{retry_count} retries")
    end
  end
end

class WorkflowExecutionError < StandardError; end
```

### 4. Create WorkflowStepExecutor Service
**File**: `app/services/workflow_step_executor.rb`

**Implementation Notes**:
```ruby
class WorkflowStepExecutor
  def initialize(step, source_object, execution)
    @step = step
    @source = source_object
    @execution = execution
    @business = execution.workflow.business
  end
  
  def execute
    case @step.action_type
    when 'send_notification'
      execute_send_notification
    when 'create_appointment'
      execute_create_appointment
    when 'generate_invoice'
      execute_generate_invoice
    when 'assign_staff'
      execute_assign_staff
    when 'update_status'
      execute_update_status
    when 'create_task'
      execute_create_task
    when 'wait_for_approval'
      execute_wait_for_approval
    else
      raise "Unknown action type: #{@step.action_type}"
    end
  end
  
  private
  
  def execute_send_notification
    config = @step.configuration
    event_type = config['event_type'] || 'workflow_notification'
    
    NotificationService.trigger(event_type, @source, @business)
    
    { action: 'notification_sent', event_type: event_type }
  end
  
  def execute_create_appointment
    config = @step.configuration
    
    # Extract client from source object
    client = case @source
    when Quote then @source.client
    when Job then @source.client
    else
      raise "Cannot create appointment: no client found"
    end
    
    appointment = @business.appointments.create!(
      client: client,
      title: generate_appointment_title,
      scheduled_at: calculate_appointment_date(config),
      duration: config['duration'] || 60,
      status: 'scheduled'
    )
    
    { action: 'appointment_created', appointment_id: appointment.id }
  end
  
  def execute_generate_invoice
    config = @step.configuration
    
    # Only works with quotes that have been accepted
    unless @source.is_a?(Quote) && @source.accepted?
      raise "Cannot generate invoice: source must be an accepted quote"
    end
    
    invoice = @business.invoices.create!(
      quote: @source,
      client: @source.client,
      amount: @source.total_amount,
      due_date: calculate_due_date(config),
      status: 'draft'
    )
    
    # Auto-send if configured
    if config['auto_send']
      invoice.update!(status: 'sent', sent_at: Time.current)
      NotificationService.trigger('invoice_sent', invoice, @business)
    end
    
    { action: 'invoice_generated', invoice_id: invoice.id }
  end
  
  def execute_assign_staff
    config = @step.configuration
    
    staff_member = case config['assignment_method']
    when 'round_robin'
      assign_round_robin
    when 'least_busy'
      assign_least_busy
    when 'specific_staff'
      User.find(config['staff_id'])
    else
      raise "Unknown assignment method: #{config['assignment_method']}"
    end
    
    # Update source object with assigned staff
    case @source
    when Quote
      @source.update!(assigned_to: staff_member)
    when Job
      @source.update!(assigned_staff: staff_member)
    when Appointment
      @source.update!(assigned_staff: staff_member)
    end
    
    # Notify staff member
    NotificationService.trigger('staff_assigned', @source, @business)
    
    { action: 'staff_assigned', staff_id: staff_member.id }
  end
  
  def execute_update_status
    config = @step.configuration
    new_status = config['new_status']
    
    if @source.respond_to?(:status=)
      @source.update!(status: new_status)
      { action: 'status_updated', old_status: @source.status_was, new_status: new_status }
    else
      raise "Source object does not support status updates"
    end
  end
  
  def execute_create_task
    config = @step.configuration
    
    task = @business.tasks.create!(
      title: config['title'] || "Follow up on #{@source.class.name} ##{@source.id}",
      description: config['description'],
      due_date: config['due_days'].days.from_now,
      assigned_to: determine_task_assignee(config),
      source: @source
    )
    
    { action: 'task_created', task_id: task.id }
  end
  
  def execute_wait_for_approval
    config = @step.configuration
    
    # Create approval request
    approval = @business.approval_requests.create!(
      source: @source,
      requested_by: @execution.triggered_by,
      approver: determine_approver(config),
      status: 'pending',
      expires_at: config['expires_hours'].hours.from_now
    )
    
    # Send notification to approver
    NotificationService.trigger('approval_requested', approval, @business)
    
    { action: 'approval_requested', approval_id: approval.id }
  end
  
  # Helper methods
  
  def generate_appointment_title
    case @source
    when Quote then "Service appointment for quote ##{@source.id}"
    when Job then @source.title
    else "Appointment"
    end
  end
  
  def calculate_appointment_date(config)
    buffer_days = config['buffer_days'] || 1
    
    if config['auto_schedule']
      # Find next available slot
      buffer_days.days.from_now.beginning_of_day + 9.hours
    else
      # Just set a default time
      buffer_days.days.from_now
    end
  end
  
  def calculate_due_date(config)
    payment_terms = config['payment_terms'] || 30
    payment_terms.days.from_now
  end
  
  def assign_round_robin
    staff_members = @business.users.where(business_users: { role: ['admin', 'staff'] })
    
    # Simple round-robin based on last assignment
    staff_members.order(:last_assigned_at).first.tap do |staff|
      staff.update!(last_assigned_at: Time.current)
    end
  end
  
  def assign_least_busy
    # Count current active assignments
    @business.users
      .where(business_users: { role: ['admin', 'staff'] })
      .left_joins(:assigned_jobs)
      .group('users.id')
      .order('COUNT(jobs.id)')
      .first
  end
  
  def determine_task_assignee(config)
    if config['assignee_id'].present?
      User.find(config['assignee_id'])
    else
      @execution.triggered_by || @business.users.where(business_users: { role: 'owner' }).first
    end
  end
  
  def determine_approver(config)
    if config['approver_id'].present?
      User.find(config['approver_id'])
    else
      @business.users.where(business_users: { role: 'owner' }).first
    end
  end
end
```

### 5. Create Background Jobs
**File**: `app/jobs/workflow_execution_job.rb`

**Implementation Notes**:
```ruby
class WorkflowExecutionJob < ApplicationJob
  queue_as :workflows
  
  def perform(execution_id)
    execution = WorkflowExecution.find(execution_id)
    
    # Check if execution is still valid
    unless execution.running?
      Rails.logger.warn "Skipping workflow execution #{execution_id}: status is #{execution.status}"
      return
    end
    
    engine = WorkflowEngine.new(execution)
    engine.execute
    
  rescue WorkflowExecutionError => e
    Rails.logger.error "Workflow execution failed: #{e.message}"
    # Error already handled by engine
  rescue => e
    Rails.logger.error "Unexpected workflow execution error: #{e.message}"
    execution.update!(
      status: :failed,
      failed_at: Time.current,
      error_message: "System error: #{e.message}"
    )
    raise e
  end
end
```

**File**: `app/jobs/workflow_step_retry_job.rb`

**Implementation Notes**:
```ruby
class WorkflowStepRetryJob < ApplicationJob
  queue_as :workflows
  
  def perform(execution_id, step_id)
    execution = WorkflowExecution.find(execution_id)
    step = WorkflowStep.find(step_id)
    
    # Only retry if execution is still running
    return unless execution.running?
    
    # Execute the step again
    engine = WorkflowEngine.new(execution)
    engine.send(:execute_step, step)
    
  rescue => error
    Rails.logger.error "Workflow step retry failed: #{error.message}"
    execution.update!(
      status: :failed,
      failed_at: Time.current,
      error_message: "Retry failed: #{error.message}"
    )
  end
end
```

### 6. Create Database Migrations
**File**: `db/migrate/xxx_create_workflow_executions.rb`

**Implementation Notes**:
```ruby
class CreateWorkflowExecutions < ActiveRecord::Migration[8.0]
  def change
    create_table :workflow_executions do |t|
      t.references :workflow, null: false, foreign_key: true
      t.references :source, polymorphic: true, null: false
      t.references :triggered_by, null: true, foreign_key: { to_table: :users }
      t.integer :status, default: 0
      t.datetime :completed_at
      t.datetime :failed_at
      t.text :error_message
      
      t.timestamps
    end
    
    add_index :workflow_executions, [:workflow_id, :status]
    add_index :workflow_executions, [:source_type, :source_id]
    add_index :workflow_executions, :created_at
  end
end

class CreateWorkflowStepExecutions < ActiveRecord::Migration[8.0]
  def change
    create_table :workflow_step_executions do |t|
      t.references :workflow_execution, null: false, foreign_key: true
      t.references :workflow_step, null: false, foreign_key: true
      t.integer :status, default: 0
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :failed_at
      t.text :error_message
      t.json :result_data
      
      t.timestamps
    end
    
    add_index :workflow_step_executions, [:workflow_execution_id, :status]
    add_index :workflow_step_executions, :workflow_step_id
  end
end
```

## Acceptance Criteria
- Workflows execute automatically when triggered by business events
- Step execution is tracked with detailed status and timing
- Failed steps can be retried based on configuration
- Execution errors are logged and reported
- Workflow progress can be monitored in real-time
- Different action types execute correctly with proper error handling

## Estimate
- Story Points: 13
- Timeline: 1.5 weeks
- Dependencies: Workflow models, background job system, notification system
