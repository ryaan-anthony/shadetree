# Feature: Workflow Templates

## Overview
Provide pre-built workflow templates for common business scenarios, allowing users to quickly implement standard automation patterns without building workflows from scratch.

## User Stories
- As a business owner, I want pre-built workflow templates so I can quickly set up common automations
- As a business owner, I want to customize templates to match my specific business needs
- As a business owner, I want templates for my industry type so they're relevant to my services

## Tasks

### 1. Create WorkflowTemplate Model
**File**: `app/models/workflow_template.rb`

**Implementation Notes**:
```ruby
class WorkflowTemplate < ApplicationRecord
  validates :name, :category, :template_data, presence: true
  validates :name, uniqueness: { scope: :category }
  
  enum category: {
    standard_service: 0,
    consultation_based: 1,
    project_workflow: 2,
    emergency_service: 3,
    subscription_service: 4
  }
  
  scope :for_business_type, ->(business_type) { 
    where('applicable_business_types @> ?', [business_type].to_json) 
  }
  scope :popular, -> { order(usage_count: :desc) }
  
  def instantiate_for_business(business, created_by)
    template = JSON.parse(template_data)
    
    workflow = business.workflows.create!(
      name: template['name'],
      description: template['description'],
      trigger_event: template['trigger_event'],
      created_by: created_by,
      status: 'draft'
    )
    
    create_workflow_steps(workflow, template['steps'])
    increment_usage_count
    
    workflow
  end
  
  private
  
  def create_workflow_steps(workflow, steps_data)
    steps_map = {}
    
    # Create all steps first
    steps_data.each do |step_data|
      step = workflow.workflow_steps.create!(
        name: step_data['name'],
        step_type: step_data['step_type'],
        action_type: step_data['action_type'],
        configuration: step_data['configuration'],
        display_order: step_data['display_order'],
        position_x: step_data['position_x'] || 100,
        position_y: step_data['position_y'] || 100
      )
      steps_map[step_data['id']] = step
    end
    
    # Create connections
    steps_data.each do |step_data|
      if step_data['next_step_id'].present?
        current_step = steps_map[step_data['id']]
        next_step = steps_map[step_data['next_step_id']]
        next_step.update!(previous_step: current_step) if next_step
      end
    end
  end
  
  def increment_usage_count
    increment!(:usage_count)
  end
end
```

### 2. Create WorkflowTemplateService
**File**: `app/services/workflow_template_service.rb`

**Implementation Notes**:
```ruby
class WorkflowTemplateService
  TEMPLATES = {
    'standard_service' => {
      name: 'Standard Service Workflow',
      description: 'Quote → Accept → Schedule → Complete → Invoice',
      category: 'standard_service',
      applicable_business_types: ['landscaping', 'cleaning', 'handyman', 'plumbing'],
      template_data: {
        name: 'Standard Service Workflow',
        description: 'Automates the complete service delivery process',
        trigger_event: 'quote_accepted',
        steps: [
          {
            id: 'step1',
            name: 'Send Confirmation',
            step_type: 'action',
            action_type: 'send_notification',
            configuration: {
              event_type: 'quote_accepted_confirmation',
              recipient_type: 'client'
            },
            display_order: 1,
            position_x: 100,
            position_y: 100,
            next_step_id: 'step2'
          },
          {
            id: 'step2',
            name: 'Schedule Appointment',
            step_type: 'action',
            action_type: 'create_appointment',
            configuration: {
              auto_schedule: true,
              buffer_days: 2,
              duration: 120
            },
            display_order: 2,
            position_x: 300,
            position_y: 100,
            next_step_id: 'step3'
          },
          {
            id: 'step3',
            name: 'Assign Staff',
            step_type: 'action',
            action_type: 'assign_staff',
            configuration: {
              assignment_method: 'round_robin'
            },
            display_order: 3,
            position_x: 500,
            position_y: 100,
            next_step_id: 'step4'
          },
          {
            id: 'step4',
            name: 'Generate Invoice',
            step_type: 'action',
            action_type: 'generate_invoice',
            configuration: {
              payment_terms: 30,
              auto_send: true
            },
            display_order: 4,
            position_x: 700,
            position_y: 100
          }
        ]
      }
    },
    
    'consultation_first' => {
      name: 'Consultation-First Workflow',
      description: 'Quote → Accept → Consultation → Final Quote → Schedule',
      category: 'consultation_based',
      applicable_business_types: ['landscaping', 'roofing', 'electrical'],
      template_data: {
        name: 'Consultation-First Workflow',
        description: 'Includes consultation step before final service delivery',
        trigger_event: 'quote_accepted',
        steps: [
          {
            id: 'step1',
            name: 'Schedule Consultation',
            step_type: 'action',
            action_type: 'create_appointment',
            configuration: {
              auto_schedule: true,
              buffer_days: 1,
              duration: 60,
              appointment_type: 'consultation'
            },
            display_order: 1,
            position_x: 100,
            position_y: 100,
            next_step_id: 'step2'
          },
          {
            id: 'step2',
            name: 'Send Consultation Reminder',
            step_type: 'action',
            action_type: 'send_notification',
            configuration: {
              event_type: 'consultation_reminder',
              recipient_type: 'client'
            },
            display_order: 2,
            position_x: 300,
            position_y: 100,
            next_step_id: 'step3'
          },
          {
            id: 'step3',
            name: 'Create Follow-up Task',
            step_type: 'action',
            action_type: 'create_task',
            configuration: {
              title: 'Follow up on consultation',
              due_days: 1,
              task_type: 'follow_up'
            },
            display_order: 3,
            position_x: 500,
            position_y: 100
          }
        ]
      }
    },
    
    'emergency_service' => {
      name: 'Emergency Service Response',
      description: 'Immediate response workflow for urgent requests',
      category: 'emergency_service',
      applicable_business_types: ['plumbing', 'electrical', 'hvac'],
      template_data: {
        name: 'Emergency Service Response',
        description: 'Fast-track workflow for emergency service requests',
        trigger_event: 'quote_sent',
        steps: [
          {
            id: 'step1',
            name: 'Immediate Confirmation',
            step_type: 'action',
            action_type: 'send_notification',
            configuration: {
              event_type: 'emergency_quote_sent',
              recipient_type: 'client'
            },
            display_order: 1,
            position_x: 100,
            position_y: 100,
            next_step_id: 'step2'
          },
          {
            id: 'step2',
            name: 'Assign Available Technician',
            step_type: 'action',
            action_type: 'assign_staff',
            configuration: {
              assignment_method: 'least_busy'
            },
            display_order: 2,
            position_x: 300,
            position_y: 100,
            next_step_id: 'step3'
          },
          {
            id: 'step3',
            name: 'Schedule ASAP',
            step_type: 'action',
            action_type: 'create_appointment',
            configuration: {
              auto_schedule: true,
              buffer_days: 0,
              duration: 180
            },
            display_order: 3,
            position_x: 500,
            position_y: 100
          }
        ]
      }
    }
  }.freeze
  
  def self.seed_templates
    TEMPLATES.each do |key, template_config|
      WorkflowTemplate.find_or_create_by(
        name: template_config[:name],
        category: template_config[:category]
      ) do |template|
        template.description = template_config[:description]
        template.applicable_business_types = template_config[:applicable_business_types]
        template.template_data = template_config[:template_data].to_json
        template.usage_count = 0
      end
    end
  end
  
  def self.recommended_for_business(business)
    WorkflowTemplate.for_business_type(business.business_type)
      .popular
      .limit(6)
  end
  
  def self.customize_template(template, customizations)
    template_data = JSON.parse(template.template_data)
    
    # Apply customizations
    template_data['name'] = customizations[:name] if customizations[:name]
    template_data['description'] = customizations[:description] if customizations[:description]
    
    # Customize step configurations
    if customizations[:steps]
      customizations[:steps].each do |step_id, step_customizations|
        step = template_data['steps'].find { |s| s['id'] == step_id }
        if step
          step['configuration'].merge!(step_customizations)
        end
      end
    end
    
    template_data
  end
end
```

### 3. Create WorkflowTemplatesController
**File**: `app/controllers/admin/workflow_templates_controller.rb`

**Implementation Notes**:
```ruby
class Admin::WorkflowTemplatesController < Admin::BaseController
  before_action :ensure_can_manage_workflows
  
  def index
    @templates = WorkflowTemplate.includes(:usage_count)
      .order(:category, :name)
    @recommended_templates = WorkflowTemplateService.recommended_for_business(current_business)
    @categories = WorkflowTemplate.categories.keys.map { |cat| [cat.humanize, cat] }
  end
  
  def show
    @template = WorkflowTemplate.find(params[:id])
    @template_data = JSON.parse(@template.template_data)
  end
  
  def create_from_template
    @template = WorkflowTemplate.find(params[:id])
    
    begin
      workflow = @template.instantiate_for_business(current_business, current_user)
      redirect_to edit_admin_workflow_path(workflow), 
                  notice: 'Workflow created from template. You can customize it before activating.'
    rescue => error
      redirect_to admin_workflow_templates_path, 
                  alert: "Failed to create workflow: #{error.message}"
    end
  end
  
  def customize
    @template = WorkflowTemplate.find(params[:id])
    @template_data = JSON.parse(@template.template_data)
    @customizations = session[:template_customizations] || {}
  end
  
  def preview_customization
    @template = WorkflowTemplate.find(params[:id])
    customizations = customization_params.to_h
    
    @customized_data = WorkflowTemplateService.customize_template(@template, customizations)
    session[:template_customizations] = customizations
    
    render :customize
  end
  
  def create_customized
    @template = WorkflowTemplate.find(params[:id])
    customizations = session[:template_customizations] || {}
    
    customized_data = WorkflowTemplateService.customize_template(@template, customizations)
    
    workflow = current_business.workflows.create!(
      name: customized_data['name'],
      description: customized_data['description'],
      trigger_event: customized_data['trigger_event'],
      created_by: current_user,
      status: 'draft'
    )
    
    create_workflow_steps_from_data(workflow, customized_data['steps'])
    
    session.delete(:template_customizations)
    redirect_to edit_admin_workflow_path(workflow), 
                notice: 'Customized workflow created successfully'
  end
  
  private
  
  def customization_params
    params.permit(
      :name, :description,
      steps: {}
    )
  end
  
  def create_workflow_steps_from_data(workflow, steps_data)
    steps_map = {}
    
    steps_data.each do |step_data|
      step = workflow.workflow_steps.create!(
        name: step_data['name'],
        step_type: step_data['step_type'],
        action_type: step_data['action_type'],
        configuration: step_data['configuration'],
        display_order: step_data['display_order'],
        position_x: step_data['position_x'],
        position_y: step_data['position_y']
      )
      steps_map[step_data['id']] = step
    end
    
    # Create connections
    steps_data.each do |step_data|
      if step_data['next_step_id'].present?
        current_step = steps_map[step_data['id']]
        next_step = steps_map[step_data['next_step_id']]
        next_step.update!(previous_step: current_step) if next_step
      end
    end
  end
  
  def ensure_can_manage_workflows
    unless current_business_user.can_manage_services?
      redirect_to admin_dashboard_path, alert: 'Access denied'
    end
  end
end
```

### 4. Create Template Seeder
**File**: `db/seeds/workflow_templates.rb`

**Implementation Notes**:
```ruby
# Workflow Templates Seeder
puts "Seeding workflow templates..."

WorkflowTemplateService.seed_templates

puts "Created #{WorkflowTemplate.count} workflow templates"

# Create some example usage data
if Rails.env.development?
  WorkflowTemplate.find_each do |template|
    template.update!(usage_count: rand(5..50))
  end
  puts "Added usage statistics for development"
end
```

### 5. Create Template Views
**File**: `app/views/admin/workflow_templates/index.html.erb`

**Implementation Notes**:
```erb
<div class="max-w-6xl mx-auto">
  <div class="flex justify-between items-center mb-6">
    <h1 class="text-2xl font-bold text-gray-900">Workflow Templates</h1>
    <%= link_to "Create Custom Workflow", new_admin_workflow_path,
        class: "bg-gray-600 hover:bg-gray-700 text-white px-4 py-2 rounded-md font-medium" %>
  </div>

  <!-- Recommended Templates -->
  <% if @recommended_templates.any? %>
    <div class="mb-8">
      <h2 class="text-lg font-medium text-gray-900 mb-4">Recommended for Your Business</h2>
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        <% @recommended_templates.each do |template| %>
          <div class="bg-white shadow rounded-lg border-2 border-blue-200">
            <div class="p-6">
              <div class="flex items-center justify-between mb-3">
                <h3 class="text-lg font-medium text-gray-900"><%= template.name %></h3>
                <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                  Recommended
                </span>
              </div>
              <p class="text-sm text-gray-600 mb-4"><%= template.description %></p>
              <div class="text-xs text-gray-500 mb-4">
                Used <%= pluralize(template.usage_count, 'time') %>
              </div>
              <div class="flex space-x-2">
                <%= link_to "Use Template", 
                    create_from_template_admin_workflow_template_path(template),
                    method: :post,
                    class: "flex-1 bg-blue-600 hover:bg-blue-700 text-white px-3 py-2 rounded-md text-sm font-medium text-center" %>
                <%= link_to "Customize", 
                    customize_admin_workflow_template_path(template),
                    class: "flex-1 bg-gray-100 hover:bg-gray-200 text-gray-700 px-3 py-2 rounded-md text-sm font-medium text-center" %>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
  <% end %>

  <!-- All Templates by Category -->
  <div class="bg-white shadow rounded-lg">
    <div class="px-6 py-4 border-b border-gray-200">
      <h3 class="text-lg font-medium text-gray-900">All Templates</h3>
    </div>
    
    <% WorkflowTemplate.categories.keys.each do |category| %>
      <% templates_in_category = @templates.select { |t| t.category == category } %>
      <% if templates_in_category.any? %>
        <div class="px-6 py-4 border-b border-gray-200 last:border-b-0">
          <h4 class="text-md font-medium text-gray-900 mb-3"><%= category.humanize %></h4>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <% templates_in_category.each do |template| %>
              <div class="border border-gray-200 rounded-lg p-4">
                <div class="flex justify-between items-start mb-2">
                  <h5 class="font-medium text-gray-900"><%= template.name %></h5>
                  <span class="text-xs text-gray-500"><%= template.usage_count %> uses</span>
                </div>
                <p class="text-sm text-gray-600 mb-3"><%= template.description %></p>
                <div class="flex space-x-2">
                  <%= link_to "Preview", admin_workflow_template_path(template),
                      class: "text-sm text-blue-600 hover:text-blue-500" %>
                  <%= link_to "Use Template", 
                      create_from_template_admin_workflow_template_path(template),
                      method: :post,
                      class: "text-sm bg-blue-600 hover:bg-blue-700 text-white px-3 py-1 rounded" %>
                  <%= link_to "Customize", 
                      customize_admin_workflow_template_path(template),
                      class: "text-sm bg-gray-100 hover:bg-gray-200 text-gray-700 px-3 py-1 rounded" %>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
    <% end %>
  </div>
</div>
```

### 6. Create Database Migration
**File**: `db/migrate/xxx_create_workflow_templates.rb`

**Implementation Notes**:
```ruby
class CreateWorkflowTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :workflow_templates do |t|
      t.string :name, null: false
      t.text :description
      t.integer :category, null: false
      t.json :applicable_business_types
      t.json :template_data, null: false
      t.integer :usage_count, default: 0
      t.boolean :active, default: true
      
      t.timestamps
    end
    
    add_index :workflow_templates, :category
    add_index :workflow_templates, :usage_count
    add_index :workflow_templates, [:category, :name], unique: true
  end
end
```

## Acceptance Criteria
- Pre-built workflow templates are available for common business scenarios
- Templates can be instantiated as new workflows with one click
- Templates can be customized before creation
- Template usage is tracked for popularity ranking
- Templates are categorized by business type and use case
- Template data includes complete workflow configuration

## Estimate
- Story Points: 8
- Timeline: 1 week
- Dependencies: Workflow models, workflow designer
