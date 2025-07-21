# Feature: Workflow Designer

## Overview
Provide a visual, drag-and-drop interface for business owners to create and configure automated workflows that connect business events to actions, enabling process automation without technical expertise.

## User Stories
- As a business owner, I want to visually design workflows so I can automate my business processes
- As a business owner, I want to drag and drop workflow steps so the system is easy to use
- As a business owner, I want to see workflow execution status so I can monitor automation

## Tasks

### 1. Create Workflow Model
**File**: `app/models/workflow.rb`

**Implementation Notes**:
```ruby
class Workflow < ApplicationRecord
  belongs_to :business
  belongs_to :created_by, class_name: 'User'
  has_many :workflow_steps, dependent: :destroy
  has_many :workflow_executions, dependent: :destroy
  
  validates :name, :trigger_event, presence: true
  validates :name, uniqueness: { scope: :business_id }
  
  enum trigger_event: {
    quote_sent: 0,
    quote_accepted: 1,
    appointment_scheduled: 2,
    work_completed: 3,
    payment_received: 4,
    staff_assigned: 5
  }
  
  enum status: { draft: 0, active: 1, paused: 2, archived: 3 }
  
  scope :active, -> { where(status: 'active') }
  scope :for_event, ->(event) { where(trigger_event: event) }
  
  def first_step
    workflow_steps.where(previous_step: nil).first
  end
  
  def steps_count
    workflow_steps.count
  end
  
  def executions_count
    workflow_executions.count
  end
  
  def success_rate
    total = workflow_executions.count
    return 0 if total.zero?
    
    successful = workflow_executions.completed.count
    (successful.to_f / total * 100).round(1)
  end
end
```

### 2. Create WorkflowStep Model
**File**: `app/models/workflow_step.rb`

**Implementation Notes**:
```ruby
class WorkflowStep < ApplicationRecord
  belongs_to :workflow
  belongs_to :previous_step, class_name: 'WorkflowStep', optional: true
  has_many :next_steps, class_name: 'WorkflowStep', foreign_key: 'previous_step_id', dependent: :nullify
  has_many :workflow_step_executions, dependent: :destroy
  
  validates :step_type, :action_type, presence: true
  validates :name, presence: true
  validates :configuration, presence: true
  
  enum step_type: { action: 0, condition: 1, delay: 2 }
  enum action_type: {
    send_notification: 0,
    create_appointment: 1,
    generate_invoice: 2,
    assign_staff: 3,
    update_status: 4,
    create_task: 5,
    wait_for_approval: 6
  }
  
  scope :root_steps, -> { where(previous_step: nil) }
  scope :ordered, -> { order(:display_order) }
  
  def has_next_steps?
    next_steps.any?
  end
  
  def is_root_step?
    previous_step.nil?
  end
  
  def execution_count
    workflow_step_executions.count
  end
  
  def success_rate
    total = workflow_step_executions.count
    return 0 if total.zero?
    
    successful = workflow_step_executions.completed.count
    (successful.to_f / total * 100).round(1)
  end
end
```

### 3. Create WorkflowDesigner Controller
**File**: `app/controllers/admin/workflows_controller.rb`

**Implementation Notes**:
```ruby
class Admin::WorkflowsController < Admin::BaseController
  before_action :set_workflow, only: [:show, :edit, :update, :destroy, :activate, :pause]
  before_action :ensure_can_manage_workflows
  
  def index
    @workflows = current_business.workflows
      .includes(:created_by, :workflow_steps)
      .order(created_at: :desc)
    @stats = workflow_stats
  end
  
  def show
    @executions = @workflow.workflow_executions
      .includes(:source)
      .order(created_at: :desc)
      .limit(20)
  end
  
  def new
    @workflow = current_business.workflows.build
    @trigger_events = workflow_trigger_events
  end
  
  def create
    @workflow = current_business.workflows.build(workflow_params)
    @workflow.created_by = current_user
    
    if @workflow.save
      redirect_to edit_admin_workflow_path(@workflow), notice: 'Workflow created. Now add workflow steps.'
    else
      @trigger_events = workflow_trigger_events
      render :new, status: :unprocessable_entity
    end
  end
  
  def edit
    @workflow_data = {
      id: @workflow.id,
      name: @workflow.name,
      trigger_event: @workflow.trigger_event,
      steps: serialize_workflow_steps,
      connections: serialize_workflow_connections
    }
  end
  
  def update
    if @workflow.update(workflow_params)
      # Handle workflow steps update from JSON data
      if params[:workflow_data].present?
        update_workflow_steps(JSON.parse(params[:workflow_data]))
      end
      
      redirect_to admin_workflow_path(@workflow), notice: 'Workflow updated successfully'
    else
      render :edit, status: :unprocessable_entity
    end
  end
  
  def activate
    @workflow.update!(status: :active)
    redirect_to admin_workflows_path, notice: 'Workflow activated'
  end
  
  def pause
    @workflow.update!(status: :paused)
    redirect_to admin_workflows_path, notice: 'Workflow paused'
  end
  
  def destroy
    @workflow.destroy
    redirect_to admin_workflows_path, notice: 'Workflow deleted'
  end
  
  private
  
  def set_workflow
    @workflow = current_business.workflows.find(params[:id])
  end
  
  def workflow_params
    params.require(:workflow).permit(:name, :description, :trigger_event)
  end
  
  def serialize_workflow_steps
    @workflow.workflow_steps.map do |step|
      {
        id: step.id,
        name: step.name,
        step_type: step.step_type,
        action_type: step.action_type,
        configuration: step.configuration,
        position_x: step.position_x || 0,
        position_y: step.position_y || 0,
        display_order: step.display_order
      }
    end
  end
  
  def serialize_workflow_connections
    connections = []
    @workflow.workflow_steps.each do |step|
      step.next_steps.each do |next_step|
        connections << {
          from: step.id,
          to: next_step.id
        }
      end
    end
    connections
  end
  
  def update_workflow_steps(workflow_data)
    # Clear existing steps
    @workflow.workflow_steps.destroy_all
    
    # Create new steps
    steps_map = {}
    workflow_data['steps'].each do |step_data|
      step = @workflow.workflow_steps.create!(
        name: step_data['name'],
        step_type: step_data['step_type'],
        action_type: step_data['action_type'],
        configuration: step_data['configuration'],
        position_x: step_data['position_x'],
        position_y: step_data['position_y'],
        display_order: step_data['display_order']
      )
      steps_map[step_data['id']] = step
    end
    
    # Create connections
    workflow_data['connections'].each do |connection|
      from_step = steps_map[connection['from']]
      to_step = steps_map[connection['to']]
      to_step.update!(previous_step: from_step) if from_step && to_step
    end
  end
  
  def workflow_trigger_events
    Workflow.trigger_events.keys.map { |event| [event.humanize, event] }
  end
  
  def workflow_stats
    {
      total_workflows: current_business.workflows.count,
      active_workflows: current_business.workflows.active.count,
      total_executions: current_business.workflows.joins(:workflow_executions).count,
      avg_success_rate: calculate_average_success_rate
    }
  end
  
  def calculate_average_success_rate
    workflows = current_business.workflows.includes(:workflow_executions)
    return 0 if workflows.empty?
    
    total_rate = workflows.sum(&:success_rate)
    (total_rate / workflows.count).round(1)
  end
  
  def ensure_can_manage_workflows
    unless current_business_user.can_manage_services?
      redirect_to admin_dashboard_path, alert: 'Access denied'
    end
  end
end
```

### 4. Create Workflow Designer Stimulus Controller
**File**: `app/javascript/controllers/workflow_designer_controller.js`

**Implementation Notes**:
```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["canvas", "sidebar", "saveButton", "workflowData"]
  static values = { 
    workflow: Object,
    availableActions: Array 
  }
  
  connect() {
    this.initializeCanvas()
    this.loadWorkflowData()
    this.setupEventListeners()
  }
  
  initializeCanvas() {
    // Initialize drag-and-drop canvas
    this.canvas = this.canvasTarget
    this.steps = new Map()
    this.connections = []
    this.draggedElement = null
    this.isConnecting = false
    this.connectionStart = null
    
    // Make canvas droppable
    this.canvas.addEventListener('dragover', this.handleDragOver.bind(this))
    this.canvas.addEventListener('drop', this.handleDrop.bind(this))
  }
  
  loadWorkflowData() {
    if (this.workflowValue && this.workflowValue.steps) {
      this.workflowValue.steps.forEach(step => {
        this.createStepElement(step)
      })
      
      this.workflowValue.connections.forEach(connection => {
        this.createConnection(connection.from, connection.to)
      })
    }
  }
  
  setupEventListeners() {
    // Add event listeners for sidebar actions
    this.sidebarTarget.querySelectorAll('[data-action-type]').forEach(element => {
      element.addEventListener('dragstart', this.handleActionDragStart.bind(this))
    })
  }
  
  handleActionDragStart(event) {
    const actionType = event.target.dataset.actionType
    const actionData = {
      step_type: 'action',
      action_type: actionType,
      name: event.target.textContent.trim()
    }
    
    event.dataTransfer.setData('application/json', JSON.stringify(actionData))
    event.dataTransfer.effectAllowed = 'copy'
  }
  
  handleDragOver(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = 'copy'
  }
  
  handleDrop(event) {
    event.preventDefault()
    
    try {
      const actionData = JSON.parse(event.dataTransfer.getData('application/json'))
      const rect = this.canvas.getBoundingClientRect()
      const x = event.clientX - rect.left
      const y = event.clientY - rect.top
      
      const stepData = {
        ...actionData,
        id: this.generateStepId(),
        position_x: x,
        position_y: y,
        configuration: this.getDefaultConfiguration(actionData.action_type)
      }
      
      this.createStepElement(stepData)
      this.markAsModified()
      
    } catch (error) {
      console.error('Error dropping action:', error)
    }
  }
  
  createStepElement(stepData) {
    const stepElement = document.createElement('div')
    stepElement.className = 'workflow-step'
    stepElement.dataset.stepId = stepData.id
    stepElement.style.left = stepData.position_x + 'px'
    stepElement.style.top = stepData.position_y + 'px'
    
    stepElement.innerHTML = `
      <div class="step-header">
        <span class="step-icon">${this.getActionIcon(stepData.action_type)}</span>
        <span class="step-name">${stepData.name}</span>
        <button class="step-delete" data-action="click->workflow-designer#deleteStep">×</button>
      </div>
      <div class="step-body">
        <p class="step-description">${this.getActionDescription(stepData.action_type)}</p>
      </div>
      <div class="step-connectors">
        <div class="connector-input" data-action="click->workflow-designer#startConnection"></div>
        <div class="connector-output" data-action="click->workflow-designer#startConnection"></div>
      </div>
    `
    
    // Make step draggable
    stepElement.draggable = true
    stepElement.addEventListener('dragstart', this.handleStepDragStart.bind(this))
    stepElement.addEventListener('click', this.handleStepClick.bind(this))
    
    this.canvas.appendChild(stepElement)
    this.steps.set(stepData.id, stepData)
  }
  
  handleStepDragStart(event) {
    this.draggedElement = event.target.closest('.workflow-step')
    event.dataTransfer.effectAllowed = 'move'
  }
  
  handleStepClick(event) {
    const stepElement = event.target.closest('.workflow-step')
    const stepId = stepElement.dataset.stepId
    const stepData = this.steps.get(stepId)
    
    this.showStepConfiguration(stepData)
  }
  
  startConnection(event) {
    const stepElement = event.target.closest('.workflow-step')
    const stepId = stepElement.dataset.stepId
    
    if (this.isConnecting) {
      // Complete connection
      this.createConnection(this.connectionStart, stepId)
      this.isConnecting = false
      this.connectionStart = null
    } else {
      // Start connection
      this.isConnecting = true
      this.connectionStart = stepId
      stepElement.classList.add('connecting')
    }
  }
  
  createConnection(fromStepId, toStepId) {
    if (fromStepId === toStepId) return // Can't connect to self
    
    const connection = { from: fromStepId, to: toStepId }
    this.connections.push(connection)
    
    this.drawConnection(fromStepId, toStepId)
    this.markAsModified()
  }
  
  drawConnection(fromStepId, toStepId) {
    const fromElement = this.canvas.querySelector(`[data-step-id="${fromStepId}"]`)
    const toElement = this.canvas.querySelector(`[data-step-id="${toStepId}"]`)
    
    if (!fromElement || !toElement) return
    
    // Create SVG line between steps
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
    svg.className = 'workflow-connection'
    svg.style.position = 'absolute'
    svg.style.pointerEvents = 'none'
    svg.style.zIndex = '1'
    
    const line = document.createElementNS('http://www.w3.org/2000/svg', 'line')
    line.setAttribute('stroke', '#3B82F6')
    line.setAttribute('stroke-width', '2')
    line.setAttribute('marker-end', 'url(#arrowhead)')
    
    // Calculate positions
    const fromRect = fromElement.getBoundingClientRect()
    const toRect = toElement.getBoundingClientRect()
    const canvasRect = this.canvas.getBoundingClientRect()
    
    const x1 = fromRect.right - canvasRect.left
    const y1 = fromRect.top + fromRect.height / 2 - canvasRect.top
    const x2 = toRect.left - canvasRect.left
    const y2 = toRect.top + toRect.height / 2 - canvasRect.top
    
    line.setAttribute('x1', x1)
    line.setAttribute('y1', y1)
    line.setAttribute('x2', x2)
    line.setAttribute('y2', y2)
    
    svg.appendChild(line)
    this.canvas.appendChild(svg)
  }
  
  deleteStep(event) {
    const stepElement = event.target.closest('.workflow-step')
    const stepId = stepElement.dataset.stepId
    
    // Remove step
    this.steps.delete(stepId)
    stepElement.remove()
    
    // Remove connections
    this.connections = this.connections.filter(conn => 
      conn.from !== stepId && conn.to !== stepId
    )
    
    // Redraw connections
    this.redrawConnections()
    this.markAsModified()
  }
  
  save() {
    const workflowData = {
      steps: Array.from(this.steps.values()),
      connections: this.connections
    }
    
    this.workflowDataTarget.value = JSON.stringify(workflowData)
    
    // Submit form
    this.element.closest('form').submit()
  }
  
  markAsModified() {
    this.saveButtonTarget.disabled = false
    this.saveButtonTarget.textContent = 'Save Changes'
    this.saveButtonTarget.classList.add('bg-yellow-600', 'hover:bg-yellow-700')
  }
  
  getActionIcon(actionType) {
    const icons = {
      send_notification: '📧',
      create_appointment: '📅',
      generate_invoice: '💰',
      assign_staff: '👤',
      update_status: '🔄',
      create_task: '📝'
    }
    return icons[actionType] || '⚙️'
  }
  
  getActionDescription(actionType) {
    const descriptions = {
      send_notification: 'Send email or SMS notification',
      create_appointment: 'Schedule an appointment',
      generate_invoice: 'Create an invoice',
      assign_staff: 'Assign staff member to job',
      update_status: 'Change record status',
      create_task: 'Create a task or reminder'
    }
    return descriptions[actionType] || 'Perform action'
  }
  
  getDefaultConfiguration(actionType) {
    const defaults = {
      send_notification: { template_id: null, recipient_type: 'client' },
      create_appointment: { auto_schedule: false, buffer_days: 1 },
      generate_invoice: { payment_terms: 30, auto_send: true },
      assign_staff: { assignment_method: 'round_robin' },
      update_status: { new_status: 'in_progress' },
      create_task: { task_type: 'follow_up', due_days: 1 }
    }
    return defaults[actionType] || {}
  }
  
  generateStepId() {
    return 'step_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9)
  }
}
```

## Acceptance Criteria
- Visual drag-and-drop workflow designer
- Workflow steps can be connected in sequence
- Step configuration panels for action details
- Workflow validation before activation
- Visual execution status and statistics
- Template workflows for common patterns

## Estimate
- Story Points: 13
- Timeline: 1.5 weeks
- Dependencies: Workflow models, Stimulus framework, SVG drawing capabilities
