# Feature: Template Customization

## Overview
Provide a rich template editor that allows business owners to customize notification templates with their branding, personalized messaging, and dynamic content while maintaining professional appearance.

## User Stories
- As a business owner, I want to customize notification templates to match my brand
- As a business owner, I want to preview templates before activating them
- As a business owner, I want to use my business colors and logo in notifications

## Tasks

### 1. Create Template Editor Component
**File**: `app/components/template_editor_component.rb`

**Implementation Notes**:
```ruby
class TemplateEditorComponent < ViewComponent::Base
  def initialize(rule:, template_type: 'email')
    @rule = rule
    @template_type = template_type
    @available_variables = NotificationRuleBuilder.available_variables_for_event(rule.trigger_event)
  end
  
  private
  
  attr_reader :rule, :template_type, :available_variables
  
  def current_template
    case template_type
    when 'email'
      rule.email_template.present? ? JSON.parse(rule.email_template) : {}
    when 'sms'
      rule.sms_template.present? ? JSON.parse(rule.sms_template) : {}
    end
  rescue JSON::ParserError
    {}
  end
  
  def template_suggestions
    NotificationRuleBuilder.template_suggestions_for_event(rule.trigger_event, rule.recipient_type)
  end
end
```

### 2. Create Template Editor View
**File**: `app/components/template_editor_component.html.erb`

**Implementation Notes**:
```erb
<div class="template-editor" data-controller="template-editor">
  <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
    <!-- Template Editor -->
    <div class="space-y-6">
      <div class="bg-white shadow rounded-lg p-6">
        <h3 class="text-lg font-medium text-gray-900 mb-4">
          <%= template_type.humanize %> Template Editor
        </h3>
        
        <% if template_type == 'email' %>
          <!-- Email Subject -->
          <div class="mb-4">
            <label class="block text-sm font-medium text-gray-700 mb-2">
              Subject Line
            </label>
            <input type="text" 
                   name="template[subject]" 
                   value="<%= current_template['subject'] %>"
                   class="block w-full border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500"
                   data-template-editor-target="subject"
                   placeholder="<%= template_suggestions[:subject] %>">
          </div>
          
          <!-- Email Body -->
          <div class="mb-4">
            <label class="block text-sm font-medium text-gray-700 mb-2">
              Email Content
            </label>
            <textarea name="template[body]" 
                      rows="12"
                      class="block w-full border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500"
                      data-template-editor-target="body"
                      placeholder="<%= template_suggestions[:body] %>"><%= current_template['body'] %></textarea>
          </div>
        <% else %>
          <!-- SMS Body -->
          <div class="mb-4">
            <label class="block text-sm font-medium text-gray-700 mb-2">
              SMS Message
              <span class="text-xs text-gray-500">(160 character limit)</span>
            </label>
            <textarea name="template[body]" 
                      rows="4"
                      maxlength="160"
                      class="block w-full border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500"
                      data-template-editor-target="smsBody"
                      data-action="input->template-editor#updateCharCount"
                      placeholder="<%= template_suggestions[:body] %>"><%= current_template['body'] %></textarea>
            <div class="mt-1 text-xs text-gray-500">
              <span data-template-editor-target="charCount">0</span> / 160 characters
            </div>
          </div>
        <% end %>
        
        <!-- Quick Actions -->
        <div class="flex space-x-2 mb-4">
          <button type="button" 
                  class="px-3 py-1 text-xs bg-gray-100 text-gray-700 rounded hover:bg-gray-200"
                  data-action="click->template-editor#useTemplate">
            Use Suggested Template
          </button>
          <button type="button" 
                  class="px-3 py-1 text-xs bg-blue-100 text-blue-700 rounded hover:bg-blue-200"
                  data-action="click->template-editor#addBranding">
            Add Business Branding
          </button>
        </div>
      </div>
      
      <!-- Available Variables -->
      <div class="bg-white shadow rounded-lg p-6">
        <h4 class="text-md font-medium text-gray-900 mb-4">Available Variables</h4>
        <div class="grid grid-cols-1 gap-2">
          <% available_variables.each do |variable, description| %>
            <div class="flex justify-between items-center p-2 bg-gray-50 rounded cursor-pointer hover:bg-blue-50"
                 data-action="click->template-editor#insertVariable"
                 data-variable="<%= variable %>">
              <span class="text-sm font-mono text-blue-600">{{<%= variable %>}}</span>
              <span class="text-xs text-gray-500"><%= description %></span>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    
    <!-- Live Preview -->
    <div class="space-y-6">
      <div class="bg-white shadow rounded-lg p-6 sticky top-6">
        <h4 class="text-md font-medium text-gray-900 mb-4">Live Preview</h4>
        
        <% if template_type == 'email' %>
          <div class="border border-gray-200 rounded-md">
            <!-- Email Header -->
            <div class="bg-blue-600 text-white p-4 rounded-t-md">
              <h3 class="font-bold"><%= rule.business.name %></h3>
            </div>
            
            <!-- Preview Subject -->
            <div class="p-3 border-b bg-gray-50">
              <span class="text-xs text-gray-500">Subject:</span>
              <div class="font-medium" data-template-editor-target="previewSubject">
                <%= current_template['subject'] || template_suggestions[:subject] %>
              </div>
            </div>
            
            <!-- Preview Body -->
            <div class="p-4 min-h-48">
              <div data-template-editor-target="previewBody" class="prose prose-sm max-w-none">
                <%= simple_format(current_template['body'] || template_suggestions[:body]) %>
              </div>
            </div>
          </div>
        <% else %>
          <div class="border border-gray-200 rounded-md p-4 bg-gray-50">
            <div class="flex items-start space-x-2">
              <div class="flex-shrink-0 w-8 h-8 bg-green-500 rounded-full flex items-center justify-center">
                <i data-feather="message-square" class="w-4 h-4 text-white"></i>
              </div>
              <div class="flex-1">
                <div class="bg-white rounded-lg p-3 shadow-sm">
                  <div data-template-editor-target="previewSms" class="text-sm">
                    <%= current_template['body'] || template_suggestions[:body] %>
                  </div>
                </div>
                <div class="text-xs text-gray-500 mt-1">
                  From: <%= rule.business.name %>
                </div>
              </div>
            </div>
          </div>
        <% end %>
        
        <!-- Preview Actions -->
        <div class="mt-4 flex space-x-2">
          <button type="button" 
                  class="px-3 py-2 text-sm bg-gray-100 text-gray-700 rounded hover:bg-gray-200"
                  data-action="click->template-editor#sendTestPreview">
            Send Test
          </button>
          <button type="button" 
                  class="px-3 py-2 text-sm bg-blue-100 text-blue-700 rounded hover:bg-blue-200"
                  data-action="click->template-editor#refreshPreview">
            Refresh Preview
          </button>
        </div>
      </div>
    </div>
  </div>
</div>

<script>
  feather.replace();
</script>
```

### 3. Create Template Editor Stimulus Controller
**File**: `app/javascript/controllers/template_editor_controller.js`

**Implementation Notes**:
```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["subject", "body", "smsBody", "previewSubject", "previewBody", "previewSms", "charCount"]
  
  connect() {
    this.updatePreview()
    this.updateCharCount()
  }
  
  updatePreview() {
    if (this.hasSubjectTarget && this.hasPreviewSubjectTarget) {
      this.previewSubjectTarget.textContent = this.processTemplate(this.subjectTarget.value)
    }
    
    if (this.hasBodyTarget && this.hasPreviewBodyTarget) {
      this.previewBodyTarget.innerHTML = this.processTemplate(this.bodyTarget.value)
    }
    
    if (this.hasSmsBodyTarget && this.hasPreviewSmsTarget) {
      this.previewSmsTarget.textContent = this.processTemplate(this.smsBodyTarget.value)
    }
  }
  
  updateCharCount() {
    if (this.hasSmsBodyTarget && this.hasCharCountTarget) {
      const count = this.smsBodyTarget.value.length
      this.charCountTarget.textContent = count
      
      // Update color based on length
      if (count > 160) {
        this.charCountTarget.classList.add("text-red-500")
        this.charCountTarget.classList.remove("text-gray-500")
      } else {
        this.charCountTarget.classList.add("text-gray-500")
        this.charCountTarget.classList.remove("text-red-500")
      }
    }
  }
  
  insertVariable(event) {
    const variable = event.currentTarget.dataset.variable
    const variableText = `{{${variable}}}`
    
    // Insert into appropriate field
    let targetField
    if (this.hasSubjectTarget && document.activeElement === this.subjectTarget) {
      targetField = this.subjectTarget
    } else if (this.hasBodyTarget) {
      targetField = this.bodyTarget
    } else if (this.hasSmsBodyTarget) {
      targetField = this.smsBodyTarget
    }
    
    if (targetField) {
      const cursorPos = targetField.selectionStart
      const textBefore = targetField.value.substring(0, cursorPos)
      const textAfter = targetField.value.substring(targetField.selectionEnd)
      
      targetField.value = textBefore + variableText + textAfter
      targetField.focus()
      targetField.setSelectionRange(cursorPos + variableText.length, cursorPos + variableText.length)
      
      this.updatePreview()
      this.updateCharCount()
    }
  }
  
  useTemplate() {
    // Get suggested template from data attributes or make an AJAX call
    const businessName = this.data.get("businessName") || "Your Business"
    
    if (this.hasSubjectTarget) {
      this.subjectTarget.value = `Update from ${businessName}`
    }
    
    if (this.hasBodyTarget) {
      this.bodyTarget.value = `Hello {{client_name}},\n\nWe have an update regarding your service request.\n\nBest regards,\n${businessName}`
    }
    
    if (this.hasSmsBodyTarget) {
      this.smsBodyTarget.value = `Update from ${businessName}: {{event_description}}. Call {{business_phone}} for details.`
    }
    
    this.updatePreview()
    this.updateCharCount()
  }
  
  addBranding() {
    const businessName = this.data.get("businessName") || "{{business_name}}"
    const businessPhone = this.data.get("businessPhone") || "{{business_phone}}"
    
    if (this.hasBodyTarget) {
      const currentValue = this.bodyTarget.value
      const brandedFooter = `\n\nBest regards,\n${businessName}\n${businessPhone}`
      
      if (!currentValue.includes(businessName)) {
        this.bodyTarget.value = currentValue + brandedFooter
        this.updatePreview()
      }
    }
  }
  
  sendTestPreview() {
    // This would make an AJAX call to send a test notification
    const templateData = {
      subject: this.hasSubjectTarget ? this.subjectTarget.value : null,
      body: this.hasBodyTarget ? this.bodyTarget.value : this.smsBodyTarget.value
    }
    
    fetch('/admin/notification_rules/test_template', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      },
      body: JSON.stringify({ template: templateData })
    })
    .then(response => response.json())
    .then(data => {
      if (data.success) {
        alert('Test notification sent!')
      } else {
        alert('Failed to send test: ' + data.error)
      }
    })
  }
  
  refreshPreview() {
    this.updatePreview()
  }
  
  processTemplate(template) {
    // Replace variables with sample data for preview
    const sampleData = {
      'business_name': this.data.get("businessName") || 'Your Business Name',
      'client_name': 'John Doe',
      'quote_id': '12345',
      'quote_amount': '$1,250.00',
      'appointment_date': 'Tomorrow at 2:00 PM',
      'staff_name': 'Mike Johnson',
      'business_phone': '(555) 123-4567'
    }
    
    let processed = template
    Object.entries(sampleData).forEach(([key, value]) => {
      processed = processed.replace(new RegExp(`{{${key}}}`, 'g'), value)
    })
    
    return processed
  }
}
```

## Acceptance Criteria
- Visual template editor with syntax highlighting
- Live preview shows how notifications will appear
- Variable insertion with click-to-add functionality
- Character count for SMS templates
- Test notification sending from preview
- Business branding integration
- Template validation and error handling

## Estimate
- Story Points: 8
- Timeline: 1 week
- Dependencies: Notification rules engine, Stimulus controllers
