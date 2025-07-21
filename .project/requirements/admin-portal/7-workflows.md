# Epic: Workflow Builder

## Overview
Enable business owners to define custom workflows that automate their quote-to-payment process. Provide a simple, visual way to configure business logic flows without requiring technical expertise, while maintaining flexibility for diverse service business models.

## Goals
- Automate repetitive business processes and reduce manual work
- Enable customization of quote-to-payment workflows per business type
- Provide visual workflow configuration that non-technical users can manage
- Ensure reliable workflow execution with proper error handling
- Support common service business workflow patterns out-of-the-box

## Success Metrics
- Workflow setup completion time < 20 minutes
- Process automation adoption rate > 70% of businesses
- Manual task reduction > 50% for workflow-enabled processes
- Workflow execution success rate > 95%
- Time to complete quote-to-payment cycle reduction > 30%

## User Stories
- As a business owner, I want to automate my quote approval process so I can respond faster to clients
- As a business owner, I want to automatically schedule appointments when quotes are accepted
- As a business owner, I want to trigger invoice generation when work is completed
- As a staff member, I want automatic task assignments so I know what needs my attention
- As a business owner, I want to customize workflows to match my business processes

## Features

### Growth Phase (P2 - Advanced Features)
1. [Workflow Designer](workflows/01-workflow-designer.md) - Visual workflow configuration interface
2. [Workflow Engine](workflows/02-workflow-engine.md) - Core workflow execution and state management
3. [Workflow Templates](workflows/03-workflow-templates.md) - Pre-built workflows for common business types
4. [Workflow Monitoring](workflows/04-workflow-monitoring.md) - Execution tracking and error handling

## Technical Architecture

### Core Models
```ruby
# Workflow definition
class Workflow < ApplicationRecord
  belongs_to :business
  has_many :workflow_steps, dependent: :destroy
  has_many :workflow_executions, dependent: :destroy
  
  validates :name, :trigger_event, presence: true
  validates :name, uniqueness: { scope: :business_id }
  
  enum trigger_event: {
    quote_sent: 0,
    quote_accepted: 1,
    appointment_scheduled: 2,
    work_completed: 3,
    payment_received: 4
  }
  
  enum status: { draft: 0, active: 1, paused: 2, archived: 3 }
  
  scope :active, -> { where(status: 'active') }
end

# Individual workflow steps
class WorkflowStep < ApplicationRecord
  belongs_to :workflow
  belongs_to :previous_step, class_name: 'WorkflowStep', optional: true
  has_many :next_steps, class_name: 'WorkflowStep', foreign_key: 'previous_step_id'
  
  validates :step_type, :action_type, presence: true
  
  enum step_type: { action: 0, condition: 1, delay: 2 }
  enum action_type: {
    send_notification: 0,
    create_appointment: 1,
    generate_invoice: 2,
    assign_staff: 3,
    update_status: 4,
    create_task: 5
  }
  
  # JSON field for step configuration
  # Example: { "template_id": 123, "delay_hours": 24, "condition": "quote.total > 1000" }
  validates :configuration, presence: true
end

# Workflow execution tracking
class WorkflowExecution < ApplicationRecord
  belongs_to :workflow
  belongs_to :source, polymorphic: true # Quote, Appointment, etc.
  has_many :workflow_step_executions, dependent: :destroy
  
  validates :status, presence: true
  
  enum status: { running: 0, completed: 1, failed: 2, cancelled: 3 }
  
  scope :active, -> { where(status: 'running') }
  scope :recent, -> { where(created_at: 1.week.ago..) }
end

class WorkflowStepExecution < ApplicationRecord
  belongs_to :workflow_execution
  belongs_to :workflow_step
  
  validates :status, presence: true
  
  enum status: { pending: 0, running: 1, completed: 2, failed: 3, skipped: 4 }
end
```

### Workflow Engine Service
```ruby
class WorkflowEngine
  def self.trigger(event, source_object)
    business = source_object.business
    workflows = business.workflows.active.where(trigger_event: event)
    
    workflows.each do |workflow|
      execution = WorkflowExecution.create!(
        workflow: workflow,
        source: source_object,
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
    current_step = @workflow.workflow_steps.where(previous_step: nil).first
    
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
    
    @execution.update!(status: :completed) if current_step.nil?
  rescue => e
    @execution.update!(status: :failed, error_message: e.message)
    Rails.logger.error "Workflow execution failed: #{e.message}"
  end
  
  private
  
  def execute_step(step)
    step_execution = WorkflowStepExecution.create!(
      workflow_execution: @execution,
      workflow_step: step,
      status: :running
    )
    
    begin
      case step.action_type
      when 'send_notification'
        execute_notification_action(step)
      when 'create_appointment'
        execute_appointment_action(step)
      when 'generate_invoice'
        execute_invoice_action(step)
      when 'assign_staff'
        execute_staff_assignment_action(step)
      when 'update_status'
        execute_status_update_action(step)
      end
      
      step_execution.update!(status: :completed)
    rescue => e
      step_execution.update!(status: :failed, error_message: e.message)
    end
    
    step_execution
  end
  
  def execute_notification_action(step)
    config = step.configuration
    NotificationService.trigger(
      config['event_type'],
      @source,
      @workflow.business
    )
  end
  
  def execute_appointment_action(step)
    config = step.configuration
    # Create appointment based on configuration
    AppointmentService.create_from_quote(@source, config)
  end
end
```

### Workflow Templates
```ruby
class WorkflowTemplate
  TEMPLATES = {
    'standard_service' => {
      name: 'Standard Service Workflow',
      description: 'Quote → Accept → Schedule → Complete → Invoice',
      steps: [
        {
          trigger: 'quote_accepted',
          action: 'send_notification',
          config: { template: 'quote_accepted_confirmation' }
        },
        {
          action: 'create_appointment',
          config: { auto_schedule: true, buffer_days: 2 }
        },
        {
          trigger: 'work_completed',
          action: 'generate_invoice',
          config: { payment_terms: 30 }
        }
      ]
    },
    'consultation_first' => {
      name: 'Consultation-First Workflow',
      description: 'Quote → Accept → Consultation → Final Quote → Schedule',
      steps: [
        {
          trigger: 'quote_accepted',
          action: 'create_appointment',
          config: { appointment_type: 'consultation' }
        },
        {
          trigger: 'consultation_completed',
          action: 'send_notification',
          config: { template: 'final_quote_ready' }
        }
      ]
    }
  }.freeze
  
  def self.create_from_template(business, template_key)
    template = TEMPLATES[template_key]
    return nil unless template
    
    workflow = business.workflows.create!(
      name: template[:name],
      description: template[:description],
      trigger_event: template[:steps].first[:trigger] || 'quote_sent'
    )
    
    template[:steps].each_with_index do |step_config, index|
      workflow.workflow_steps.create!(
        step_type: :action,
        action_type: step_config[:action],
        configuration: step_config[:config],
        display_order: index
      )
    end
    
    workflow
  end
end
```

## Integration Points
- Quote Management (workflow trigger sources)
- Appointment Scheduling (automated scheduling actions)
- Notification System (automated communication)
- Staff Management (staff assignment actions)
- Invoice Generation (automated billing actions)

## Security Considerations
- Validate workflow configurations to prevent malicious actions
- Ensure business scoping for all workflow operations
- Audit workflow executions and modifications
- Limit workflow complexity to prevent infinite loops
- Secure workflow step configurations

## Growth Phase Scope (P2 Priority)
**Included in Growth Phase:**
- Visual workflow designer with drag-and-drop interface
- 6 core action types (notification, appointment, invoice, assignment, status, task)
- Pre-built workflow templates for common business types
- Basic workflow execution monitoring and error handling

**Future Enhancements:**
- Advanced conditional logic and branching
- External system integrations (webhooks, APIs)
- Workflow analytics and optimization suggestions
- Custom action types and extensibility

## Technical Implementation Notes
```ruby
# Background job for workflow execution
class WorkflowExecutionJob < ApplicationJob
  queue_as :workflows
  
  def perform(execution_id)
    execution = WorkflowExecution.find(execution_id)
    WorkflowEngine.new(execution).execute
  end
end

# Usage in controllers/services
class QuotesController < ApplicationController
  def update
    if @quote.update(quote_params)
      # Trigger workflows for quote status change
      WorkflowEngine.trigger('quote_accepted', @quote) if @quote.status_changed? && @quote.accepted?
    end
  end
end
```

## Workflow Designer Interface
```erb
<!-- Simple workflow step configuration -->
<div class="workflow-step" data-step-type="action">
  <div class="step-header">
    <h4>Send Notification</h4>
    <select name="workflow_step[action_type]">
      <option value="send_notification">Send Notification</option>
      <option value="create_appointment">Create Appointment</option>
      <option value="generate_invoice">Generate Invoice</option>
    </select>
  </div>
  
  <div class="step-config">
    <!-- Dynamic configuration based on action type -->
    <div class="notification-config" data-show-when="send_notification">
      <label>Notification Template:</label>
      <select name="workflow_step[configuration][template_id]">
        <% @business.notification_templates.each do |template| %>
          <option value="<%= template.id %>"><%= template.name %></option>
        <% end %>
      </select>
    </div>
  </div>
</div>
```

## Dependencies
- Notification System (for automated communications)
- Background Job Processing (Sidekiq)
- Quote Management System (trigger sources)
- Appointment Scheduling System (workflow actions)

## Estimate
- All Features: 21 story points (2.5 weeks)
- Note: This is a Growth Phase epic, not included in MVP
