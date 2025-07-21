# Feature: Notification Rules Engine

## Overview
Provide a comprehensive system for configuring and managing notification rules that define when, how, and to whom notifications are sent. This allows business owners to customize their communication automation.

## User Stories
- As a business owner, I want to configure when notifications are sent so I can control customer communication
- As a business owner, I want to customize notification recipients based on the event type
- As a business owner, I want to enable/disable specific notifications without losing configuration

## Tasks

### 1. Create NotificationRulesController
**File**: `app/controllers/admin/notification_rules_controller.rb`

**Implementation Notes**:
```ruby
class Admin::NotificationRulesController < Admin::BaseController
  before_action :set_notification_rule, only: [:show, :edit, :update, :destroy, :toggle]
  before_action :ensure_can_manage_notifications
  
  def index
    @notification_rules = current_business.notification_rules
      .includes(:created_by)
      .order(:trigger_event, :name)
    @stats = notification_stats
  end
  
  def show
    @recent_deliveries = @notification_rule.notification_deliveries
      .includes(:recipient, :source)
      .recent
      .order(created_at: :desc)
      .limit(20)
  end
  
  def new
    @notification_rule = current_business.notification_rules.build
    set_form_data
  end
  
  def create
    @notification_rule = current_business.notification_rules.build(notification_rule_params)
    @notification_rule.created_by = current_user
    
    if @notification_rule.save
      redirect_to admin_notification_rules_path, notice: 'Notification rule created successfully'
    else
      set_form_data
      render :new, status: :unprocessable_entity
    end
  end
  
  def edit
    set_form_data
  end
  
  def update
    if @notification_rule.update(notification_rule_params)
      redirect_to admin_notification_rules_path, notice: 'Notification rule updated successfully'
    else
      set_form_data
      render :edit, status: :unprocessable_entity
    end
  end
  
  def destroy
    @notification_rule.destroy
    redirect_to admin_notification_rules_path, notice: 'Notification rule deleted successfully'
  end
  
  def toggle
    @notification_rule.update!(active: !@notification_rule.active?)
    status = @notification_rule.active? ? 'enabled' : 'disabled'
    redirect_to admin_notification_rules_path, notice: "Notification rule #{status}"
  end
  
  def test
    rule = current_business.notification_rules.find(params[:id])
    test_recipient = params[:test_email].presence || current_user.email
    
    # Create a test delivery
    test_delivery = NotificationDelivery.create!(
      notification_rule: rule,
      recipient: current_user,
      source: create_test_source(rule),
      delivery_method: 'email',
      recipient_email: test_recipient,
      status: :pending
    )
    
    NotificationEmailJob.perform_later(test_delivery.id)
    
    redirect_to admin_notification_rules_path, 
                notice: "Test notification sent to #{test_recipient}"
  end
  
  private
  
  def set_notification_rule
    @notification_rule = current_business.notification_rules.find(params[:id])
  end
  
  def notification_rule_params
    params.require(:notification_rule).permit(
      :name, :trigger_event, :delivery_method, :recipient_type,
      :email_template, :sms_template, :active
    )
  end
  
  def set_form_data
    @trigger_events = NotificationRule.trigger_events.keys.map do |event|
      [event.humanize, event]
    end
    
    @delivery_methods = NotificationRule.delivery_methods.keys.map do |method|
      [method.humanize, method]
    end
    
    @recipient_types = NotificationRule.recipient_types.keys.map do |type|
      [type.humanize.titlecase, type]
    end
  end
  
  def notification_stats
    {
      total_rules: current_business.notification_rules.count,
      active_rules: current_business.notification_rules.active.count,
      deliveries_this_week: current_business.notification_rules
        .joins(:notification_deliveries)
        .where(notification_deliveries: { created_at: 1.week.ago.. })
        .count,
      success_rate: calculate_success_rate
    }
  end
  
  def calculate_success_rate
    total = current_business.notification_rules
      .joins(:notification_deliveries)
      .where(notification_deliveries: { created_at: 1.month.ago.. })
      .count
      
    return 0 if total.zero?
    
    successful = current_business.notification_rules
      .joins(:notification_deliveries)
      .where(notification_deliveries: { 
        created_at: 1.month.ago..,
        status: [:sent, :delivered]
      })
      .count
      
    (successful.to_f / total * 100).round(1)
  end
  
  def create_test_source(rule)
    # Create a mock object for testing
    case rule.trigger_event
    when 'quote_sent', 'quote_accepted'
      OpenStruct.new(
        id: 'TEST',
        client_name: 'Test Client',
        total_amount: 500.00,
        service_description: 'Test Service'
      )
    when 'appointment_scheduled'
      OpenStruct.new(
        id: 'TEST',
        client: OpenStruct.new(name: 'Test Client'),
        scheduled_at: 1.day.from_now
      )
    else
      OpenStruct.new(id: 'TEST')
    end
  end
  
  def ensure_can_manage_notifications
    unless current_business_user.can_manage_services?
      redirect_to admin_dashboard_path, alert: 'Access denied'
    end
  end
end
```

### 2. Create NotificationRuleBuilder Service
**File**: `app/services/notification_rule_builder.rb`

**Implementation Notes**:
```ruby
class NotificationRuleBuilder
  def self.create_default_rules(business, created_by)
    default_rules = NotificationRule.default_rules_for_business(business)
    
    default_rules.each do |rule_data|
      business.notification_rules.create!(
        rule_data.merge(created_by: created_by)
      )
    end
  end
  
  def self.available_variables_for_event(trigger_event)
    base_variables = {
      'business_name' => 'Your business name',
      'business_phone' => 'Your business phone number',
      'business_email' => 'Your business email',
      'recipient_name' => 'Name of the person receiving the notification'
    }
    
    event_specific = case trigger_event.to_s
    when 'quote_sent', 'quote_viewed', 'quote_accepted', 'quote_expired'
      {
        'client_name' => 'Customer name',
        'quote_id' => 'Quote reference number',
        'quote_amount' => 'Total quote amount',
        'quote_url' => 'Link to view the quote',
        'service_description' => 'Description of services'
      }
    when 'appointment_scheduled', 'appointment_reminder'
      {
        'client_name' => 'Customer name',
        'appointment_date' => 'Scheduled appointment date and time',
        'staff_name' => 'Assigned staff member name',
        'service_description' => 'Service being provided'
      }
    when 'payment_received'
      {
        'client_name' => 'Customer name',
        'payment_amount' => 'Amount received',
        'quote_id' => 'Related quote number'
      }
    when 'staff_assigned'
      {
        'staff_name' => 'Staff member being assigned',
        'job_title' => 'Job or appointment title',
        'client_name' => 'Customer name',
        'scheduled_date' => 'When the work is scheduled'
      }
    else
      {}
    end
    
    base_variables.merge(event_specific)
  end
  
  def self.template_suggestions_for_event(trigger_event, recipient_type)
    case [trigger_event.to_s, recipient_type.to_s]
    when ['quote_sent', 'client']
      {
        subject: 'Your Service Quote from {{business_name}}',
        body: quote_sent_client_template
      }
    when ['quote_accepted', 'owner']
      {
        subject: 'Quote Accepted - {{client_name}}',
        body: quote_accepted_owner_template
      }
    when ['appointment_scheduled', 'client']
      {
        subject: 'Appointment Confirmed - {{business_name}}',
        body: appointment_client_template
      }
    when ['staff_assigned', 'staff']
      {
        subject: 'New Assignment - {{job_title}}',
        body: staff_assigned_template
      }
    else
      {
        subject: 'Update from {{business_name}}',
        body: generic_template
      }
    end
  end
  
  private
  
  def self.quote_sent_client_template
    <<~HTML
      <p>Hello {{client_name}},</p>
      
      <p>Thank you for your interest in our services! We've prepared a quote for your project.</p>
      
      <div style="background: #f8f9fa; padding: 15px; border-radius: 5px; margin: 20px 0;">
        <strong>Quote #{{quote_id}}</strong><br>
        Service: {{service_description}}<br>
        Total: {{quote_amount}}
      </div>
      
      <p><a href="{{quote_url}}" style="background: #2563eb; color: white; padding: 12px 24px; text-decoration: none; border-radius: 5px;">View Quote</a></p>
      
      <p>If you have any questions, please contact us at {{business_phone}}.</p>
      
      <p>Best regards,<br>{{business_name}}</p>
    HTML
  end
  
  def self.appointment_client_template
    <<~HTML
      <p>Hello {{client_name}},</p>
      
      <p>Your appointment has been confirmed!</p>
      
      <div style="background: #f0f9ff; padding: 15px; border-radius: 5px; margin: 20px 0;">
        <strong>Appointment Details</strong><br>
        Date & Time: {{appointment_date}}<br>
        Service: {{service_description}}<br>
        Staff: {{staff_name}}
      </div>
      
      <p>We look forward to serving you. If you need to reschedule, please contact us at {{business_phone}}.</p>
      
      <p>Best regards,<br>{{business_name}}</p>
    HTML
  end
  
  def self.staff_assigned_template
    <<~HTML
      <p>Hello {{staff_name}},</p>
      
      <p>You have been assigned to a new job:</p>
      
      <div style="background: #fef3c7; padding: 15px; border-radius: 5px; margin: 20px 0;">
        <strong>{{job_title}}</strong><br>
        Client: {{client_name}}<br>
        Scheduled: {{scheduled_date}}
      </div>
      
      <p>Please review the job details in your dashboard and contact the client if needed.</p>
      
      <p>Thanks,<br>{{business_name}} Management</p>
    HTML
  end
end
```

### 3. Create Notification Rules Views
**File**: `app/views/admin/notification_rules/index.html.erb`

**Implementation Notes**:
```erb
<div class="max-w-6xl mx-auto">
  <div class="flex justify-between items-center mb-6">
    <h1 class="text-2xl font-bold text-gray-900">Notification Rules</h1>
    <%= link_to "New Rule", new_admin_notification_rule_path,
        class: "bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-md font-medium" %>
  </div>

  <!-- Stats Cards -->
  <div class="grid grid-cols-1 md:grid-cols-4 gap-6 mb-8">
    <div class="bg-white overflow-hidden shadow rounded-lg">
      <div class="p-5">
        <div class="flex items-center">
          <div class="flex-shrink-0">
            <i data-feather="settings" class="h-8 w-8 text-blue-600"></i>
          </div>
          <div class="ml-5 w-0 flex-1">
            <dl>
              <dt class="text-sm font-medium text-gray-500 truncate">Total Rules</dt>
              <dd class="text-3xl font-bold text-gray-900"><%= @stats[:total_rules] %></dd>
            </dl>
          </div>
        </div>
      </div>
    </div>

    <div class="bg-white overflow-hidden shadow rounded-lg">
      <div class="p-5">
        <div class="flex items-center">
          <div class="flex-shrink-0">
            <i data-feather="check-circle" class="h-8 w-8 text-green-600"></i>
          </div>
          <div class="ml-5 w-0 flex-1">
            <dl>
              <dt class="text-sm font-medium text-gray-500 truncate">Active Rules</dt>
              <dd class="text-3xl font-bold text-gray-900"><%= @stats[:active_rules] %></dd>
            </dl>
          </div>
        </div>
      </div>
    </div>

    <div class="bg-white overflow-hidden shadow rounded-lg">
      <div class="p-5">
        <div class="flex items-center">
          <div class="flex-shrink-0">
            <i data-feather="send" class="h-8 w-8 text-purple-600"></i>
          </div>
          <div class="ml-5 w-0 flex-1">
            <dl>
              <dt class="text-sm font-medium text-gray-500 truncate">This Week</dt>
              <dd class="text-3xl font-bold text-gray-900"><%= @stats[:deliveries_this_week] %></dd>
            </dl>
          </div>
        </div>
      </div>
    </div>

    <div class="bg-white overflow-hidden shadow rounded-lg">
      <div class="p-5">
        <div class="flex items-center">
          <div class="flex-shrink-0">
            <i data-feather="trending-up" class="h-8 w-8 text-orange-600"></i>
          </div>
          <div class="ml-5 w-0 flex-1">
            <dl>
              <dt class="text-sm font-medium text-gray-500 truncate">Success Rate</dt>
              <dd class="text-3xl font-bold text-gray-900"><%= @stats[:success_rate] %>%</dd>
            </dl>
          </div>
        </div>
      </div>
    </div>
  </div>

  <!-- Notification Rules Table -->
  <div class="bg-white shadow rounded-lg">
    <div class="px-6 py-4 border-b border-gray-200">
      <h3 class="text-lg font-medium text-gray-900">Your Notification Rules</h3>
    </div>
    
    <div class="overflow-x-auto">
      <table class="min-w-full divide-y divide-gray-200">
        <thead class="bg-gray-50">
          <tr>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              Rule Name
            </th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              Trigger Event
            </th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              Recipients
            </th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              Method
            </th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              Status
            </th>
            <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
              Actions
            </th>
          </tr>
        </thead>
        <tbody class="bg-white divide-y divide-gray-200">
          <% @notification_rules.each do |rule| %>
            <tr>
              <td class="px-6 py-4 whitespace-nowrap">
                <div class="text-sm font-medium text-gray-900"><%= rule.name %></div>
              </td>
              <td class="px-6 py-4 whitespace-nowrap">
                <div class="text-sm text-gray-900"><%= rule.trigger_event.humanize %></div>
              </td>
              <td class="px-6 py-4 whitespace-nowrap">
                <div class="text-sm text-gray-900"><%= rule.recipient_type.humanize.titlecase %></div>
              </td>
              <td class="px-6 py-4 whitespace-nowrap">
                <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                  <%= rule.delivery_method.humanize %>
                </span>
              </td>
              <td class="px-6 py-4 whitespace-nowrap">
                <% if rule.active? %>
                  <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
                    Active
                  </span>
                <% else %>
                  <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800">
                    Disabled
                  </span>
                <% end %>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                <div class="flex justify-end space-x-2">
                  <%= link_to "Test", test_admin_notification_rule_path(rule),
                      class: "text-blue-600 hover:text-blue-900",
                      method: :post,
                      data: { confirm: "Send test notification to #{current_user.email}?" } %>
                  <%= link_to "Edit", edit_admin_notification_rule_path(rule),
                      class: "text-indigo-600 hover:text-indigo-900" %>
                  <%= link_to rule.active? ? "Disable" : "Enable", 
                      toggle_admin_notification_rule_path(rule),
                      class: rule.active? ? "text-yellow-600 hover:text-yellow-900" : "text-green-600 hover:text-green-900",
                      method: :patch %>
                </div>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
  </div>
</div>

<script>
  feather.replace();
</script>
```

### 4. Create NotificationRuleValidator
**File**: `app/validators/notification_rule_validator.rb`

**Implementation Notes**:
```ruby
class NotificationRuleValidator < ActiveModel::Validator
  def validate(record)
    validate_template_structure(record)
    validate_recipient_compatibility(record)
    validate_trigger_event_compatibility(record)
  end
  
  private
  
  def validate_template_structure(record)
    return unless record.email_template.present?
    
    begin
      template = JSON.parse(record.email_template)
      
      unless template.is_a?(Hash) && template['subject'].present? && template['body'].present?
        record.errors.add(:email_template, 'must contain subject and body')
      end
      
      validate_template_variables(record, template)
      
    rescue JSON::ParserError
      record.errors.add(:email_template, 'must be valid JSON')
    end
  end
  
  def validate_template_variables(record, template)
    available_vars = NotificationRuleBuilder.available_variables_for_event(record.trigger_event)
    used_vars = extract_template_variables(template['subject'] + ' ' + template['body'])
    
    invalid_vars = used_vars - available_vars.keys
    
    if invalid_vars.any?
      record.errors.add(:email_template, "contains invalid variables: #{invalid_vars.join(', ')}")
    end
  end
  
  def extract_template_variables(text)
    text.scan(/\{\{([^}]+)\}\}/).flatten.uniq
  end
  
  def validate_recipient_compatibility(record)
    incompatible_combinations = [
      ['staff_assigned', 'client'],  # Staff assignment notifications should go to staff
      ['quote_viewed', 'staff']      # Quote view notifications are for business owners
    ]
    
    if incompatible_combinations.include?([record.trigger_event, record.recipient_type])
      record.errors.add(:recipient_type, "is not compatible with #{record.trigger_event} event")
    end
  end
  
  def validate_trigger_event_compatibility(record)
    # Some events only make sense with certain delivery methods
    sms_incompatible_events = ['quote_viewed'] # These need links which work better in email
    
    if record.delivery_method.in?(['sms', 'both']) && record.trigger_event.in?(sms_incompatible_events)
      record.errors.add(:delivery_method, "SMS not recommended for #{record.trigger_event} events")
    end
  end
end
```

## Acceptance Criteria
- Business owners can create, edit, and delete notification rules
- Rules can be enabled/disabled without losing configuration
- Template variables are validated against available data for each event
- Test notifications can be sent to verify rule configuration
- Rule compatibility is validated (recipient type vs trigger event)
- Statistics show notification performance and usage

## Estimate
- Story Points: 8
- Timeline: 1 week
- Dependencies: NotificationRule model, email notification system
