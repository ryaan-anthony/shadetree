# Feature: Quote Templates

## Overview
Enable business owners to create standardized quote templates with consistent formatting, terms, and branding to streamline the quote generation process.

## User Stories
- As a business owner, I want to create quote templates so all quotes have consistent professional formatting
- As a business owner, I want to customize quote layouts to match my brand
- As a staff member, I want to quickly generate quotes using pre-built templates

## Tasks

### 1. Create QuoteTemplate Model
**File**: `app/models/quote_template.rb`

**Implementation Notes**:
```ruby
class QuoteTemplate < ApplicationRecord
  belongs_to :business
  has_many :quotes, dependent: :nullify
  
  validates :name, presence: true, length: { maximum: 255 }
  validates :name, uniqueness: { scope: :business_id }
  validates :template_type, presence: true
  validates :header_content, presence: true
  validates :footer_content, presence: true
  
  enum template_type: { standard: 0, detailed: 1, simple: 2, custom: 3 }
  
  scope :active, -> { where(is_active: true) }
  scope :default_templates, -> { where(is_default: true) }
  
  def render_for_quote(quote)
    context = build_template_context(quote)
    
    {
      header: interpolate_template(header_content, context),
      body: interpolate_template(body_content || default_body_content, context),
      footer: interpolate_template(footer_content, context),
      terms: interpolate_template(terms_and_conditions || default_terms, context)
    }
  end
  
  def preview_with_sample_data
    sample_quote = build_sample_quote
    render_for_quote(sample_quote)
  end
  
  def self.create_default_templates(business)
    create_standard_template(business)
    create_detailed_template(business)
    create_simple_template(business)
  end
  
  private
  
  def interpolate_template(template, context)
    return template unless template && context
    
    result = template.dup
    context.each do |key, value|
      result.gsub!("{{#{key}}}", value.to_s)
    end
    result
  end
  
  def build_template_context(quote)
    {
      business_name: quote.business.name,
      business_address: format_business_address(quote.business),
      business_phone: quote.business.phone,
      business_email: quote.business.email,
      customer_name: quote.customer_name,
      customer_address: quote.customer_address,
      customer_phone: quote.customer_phone,
      customer_email: quote.customer_email,
      quote_number: quote.quote_number,
      quote_date: quote.created_at.strftime('%B %d, %Y'),
      valid_until: quote.valid_until&.strftime('%B %d, %Y'),
      subtotal: ActionController::Base.helpers.number_to_currency(quote.subtotal),
      tax_amount: ActionController::Base.helpers.number_to_currency(quote.tax_amount),
      total_amount: ActionController::Base.helpers.number_to_currency(quote.total_amount),
      project_description: quote.project_description,
      notes: quote.notes
    }
  end
  
  def format_business_address(business)
    address_parts = [
      business.address_line_1,
      business.address_line_2,
      "#{business.city}, #{business.state} #{business.zip_code}"
    ].compact.reject(&:blank?)
    
    address_parts.join('\n')
  end
  
  def build_sample_quote
    OpenStruct.new(
      business: business,
      customer_name: "John Smith",
      customer_address: "123 Main St, Anytown, ST 12345",
      customer_phone: "(555) 123-4567",
      customer_email: "john@example.com",
      quote_number: "Q-2025-001",
      created_at: Time.current,
      valid_until: 30.days.from_now,
      subtotal: 1250.00,
      tax_amount: 100.00,
      total_amount: 1350.00,
      project_description: "Sample landscaping project",
      notes: "This is a sample quote for preview purposes"
    )
  end
  
  def default_body_content
    <<~BODY
      Dear {{customer_name}},
      
      Thank you for your interest in our services. Please find below the details for your project:
      
      **Project:** {{project_description}}
      
      We look forward to working with you on this project.
      
      Best regards,
      {{business_name}}
    BODY
  end
  
  def default_terms
    <<~TERMS
      TERMS AND CONDITIONS:
      
      1. This quote is valid for 30 days from the date above.
      2. A 50% deposit is required to begin work.
      3. Final payment is due upon completion.
      4. Any changes to the scope of work may result in additional charges.
      5. We are fully licensed and insured.
    TERMS
  end
  
  def self.create_standard_template(business)
    create!(
      business: business,
      name: "Standard Quote",
      template_type: "standard",
      is_default: true,
      header_content: standard_header_content(business),
      footer_content: standard_footer_content(business),
      terms_and_conditions: standard_terms,
      show_line_items: true,
      show_totals: true,
      show_terms: true
    )
  end
  
  def self.create_detailed_template(business)
    create!(
      business: business,
      name: "Detailed Quote",
      template_type: "detailed",
      header_content: detailed_header_content(business),
      footer_content: detailed_footer_content(business),
      terms_and_conditions: detailed_terms,
      show_line_items: true,
      show_item_descriptions: true,
      show_totals: true,
      show_terms: true,
      show_payment_schedule: true
    )
  end
  
  def self.create_simple_template(business)
    create!(
      business: business,
      name: "Simple Quote",
      template_type: "simple",
      header_content: simple_header_content(business),
      footer_content: simple_footer_content(business),
      show_line_items: false,
      show_totals: true,
      show_terms: false
    )
  end
  
  def self.standard_header_content(business)
    <<~HEADER
      **{{business_name}}**
      {{business_address}}
      Phone: {{business_phone}}
      Email: {{business_email}}
      
      ---
      
      **QUOTE #{{quote_number}}**
      Date: {{quote_date}}
      Valid Until: {{valid_until}}
      
      **Bill To:**
      {{customer_name}}
      {{customer_address}}
      {{customer_phone}}
      {{customer_email}}
    HEADER
  end
  
  def self.standard_footer_content(business)
    <<~FOOTER
      Thank you for considering {{business_name}} for your project needs.
      
      To accept this quote, please sign and return a copy or contact us at {{business_phone}}.
      
      We look forward to working with you!
    FOOTER
  end
  
  def self.standard_terms
    <<~TERMS
      **TERMS AND CONDITIONS:**
      
      • This quote is valid for 30 days from the date above
      • A deposit may be required to begin work
      • Payment is due upon completion unless other arrangements are made
      • Any changes to the scope of work may result in additional charges
      • We are fully licensed and insured
    TERMS
  end
end
```

### 2. Create TemplateSection Model
**File**: `app/models/template_section.rb`

**Implementation Notes**:
```ruby
class TemplateSection < ApplicationRecord
  belongs_to :quote_template
  
  validates :section_name, presence: true
  validates :content, presence: true
  validates :display_order, presence: true, numericality: { greater_than: 0 }
  validates :section_name, uniqueness: { scope: :quote_template_id }
  
  scope :ordered, -> { order(:display_order) }
  scope :active, -> { where(is_active: true) }
  
  enum section_type: { 
    header: 0, 
    introduction: 1, 
    line_items: 2, 
    totals: 3, 
    terms: 4, 
    footer: 5, 
    custom: 6 
  }
  
  def render_with_context(context)
    return content unless context
    
    result = content.dup
    context.each do |key, value|
      result.gsub!("{{#{key}}}", value.to_s)
    end
    result
  end
end
```

### 3. Quote Templates Controller
**File**: `app/controllers/admin/quote_templates_controller.rb`

**Implementation Notes**:
```ruby
class Admin::QuoteTemplatesController < Admin::BaseController
  before_action :set_business
  before_action :ensure_can_manage_services
  before_action :set_quote_template, only: [:show, :edit, :update, :destroy, :duplicate, :preview, :set_default]
  
  def index
    @quote_templates = @business.quote_templates.order(:name)
    @default_template = @business.quote_templates.default_templates.first
  end
  
  def show
    @template_sections = @quote_template.template_sections.active.ordered
  end
  
  def new
    @quote_template = @business.quote_templates.build
    build_default_sections
  end
  
  def create
    @quote_template = @business.quote_templates.build(quote_template_params)
    
    if @quote_template.save
      create_template_sections if params[:template_sections].present?
      redirect_to admin_quote_template_path(@quote_template), notice: 'Template created successfully.'
    else
      build_default_sections
      render :new, status: :unprocessable_entity
    end
  end
  
  def edit
    @template_sections = @quote_template.template_sections.ordered
  end
  
  def update
    if @quote_template.update(quote_template_params)
      update_template_sections if params[:template_sections].present?
      redirect_to admin_quote_template_path(@quote_template), notice: 'Template updated successfully.'
    else
      @template_sections = @quote_template.template_sections.ordered
      render :edit, status: :unprocessable_entity
    end
  end
  
  def destroy
    if @quote_template.quotes.any?
      redirect_to admin_quote_templates_path, alert: 'Cannot delete template that has been used for quotes.'
    else
      @quote_template.destroy
      redirect_to admin_quote_templates_path, notice: 'Template deleted successfully.'
    end
  end
  
  def duplicate
    new_template = @quote_template.dup
    new_template.name = "#{@quote_template.name} (Copy)"
    new_template.is_default = false
    
    if new_template.save
      # Duplicate template sections
      @quote_template.template_sections.each do |section|
        new_template.template_sections.create!(
          section_name: section.section_name,
          section_type: section.section_type,
          content: section.content,
          display_order: section.display_order,
          is_active: section.is_active
        )
      end
      
      redirect_to edit_admin_quote_template_path(new_template), 
                  notice: 'Template duplicated successfully.'
    else
      redirect_to admin_quote_templates_path, alert: 'Failed to duplicate template.'
    end
  end
  
  def preview
    @preview_data = @quote_template.preview_with_sample_data
    render layout: false
  end
  
  def set_default
    # Remove default from all other templates
    @business.quote_templates.update_all(is_default: false)
    
    # Set this template as default
    @quote_template.update!(is_default: true)
    
    redirect_to admin_quote_templates_path, notice: 'Default template updated.'
  end
  
  private
  
  def set_business
    @business = current_user.owned_business || current_user.business
  end
  
  def ensure_can_manage_services
    business_user = current_user.business_users.find_by(business: @business)
    unless business_user&.can_manage_services?
      redirect_to admin_dashboard_path, alert: 'Not authorized to manage templates'
    end
  end
  
  def set_quote_template
    @quote_template = @business.quote_templates.find(params[:id])
  end
  
  def quote_template_params
    params.require(:quote_template).permit(
      :name, :template_type, :header_content, :body_content, :footer_content,
      :terms_and_conditions, :show_line_items, :show_item_descriptions,
      :show_totals, :show_terms, :show_payment_schedule, :is_active
    )
  end
  
  def build_default_sections
    @template_sections = [
      { section_name: 'Header', section_type: 'header', display_order: 1 },
      { section_name: 'Introduction', section_type: 'introduction', display_order: 2 },
      { section_name: 'Line Items', section_type: 'line_items', display_order: 3 },
      { section_name: 'Totals', section_type: 'totals', display_order: 4 },
      { section_name: 'Terms', section_type: 'terms', display_order: 5 },
      { section_name: 'Footer', section_type: 'footer', display_order: 6 }
    ]
  end
  
  def create_template_sections
    params[:template_sections].each do |section_params|
      @quote_template.template_sections.create!(
        section_name: section_params[:section_name],
        section_type: section_params[:section_type],
        content: section_params[:content],
        display_order: section_params[:display_order],
        is_active: section_params[:is_active] || true
      )
    end
  end
  
  def update_template_sections
    params[:template_sections].each do |section_id, section_params|
      if section_id == 'new'
        # Create new section
        @quote_template.template_sections.create!(
          section_name: section_params[:section_name],
          section_type: section_params[:section_type],
          content: section_params[:content],
          display_order: section_params[:display_order],
          is_active: section_params[:is_active] || true
        )
      else
        # Update existing section
        section = @quote_template.template_sections.find(section_id)
        if section_params[:_destroy] == '1'
          section.destroy
        else
          section.update!(
            section_name: section_params[:section_name],
            content: section_params[:content],
            display_order: section_params[:display_order],
            is_active: section_params[:is_active] || false
          )
        end
      end
    end
  end
end
```

### 4. Quote Template Form View
**File**: `app/views/admin/quote_templates/edit.html.erb`

**Implementation Notes**:
```erb
<div class="max-w-6xl mx-auto py-8">
  <div class="flex justify-between items-center mb-6">
    <h1 class="text-2xl font-bold text-gray-900">
      <%= @quote_template.persisted? ? "Edit" : "New" %> Quote Template
    </h1>
    <div class="flex space-x-3">
      <% if @quote_template.persisted? %>
        <%= link_to "Preview", preview_admin_quote_template_path(@quote_template),
                    target: "_blank", class: "bg-green-600 hover:bg-green-700 text-white font-medium py-2 px-4 rounded-md" %>
      <% end %>
      <%= link_to "Back to Templates", admin_quote_templates_path,
                  class: "bg-gray-600 hover:bg-gray-700 text-white font-medium py-2 px-4 rounded-md" %>
    </div>
  </div>
  
  <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
    <!-- Template Settings -->
    <div class="bg-white shadow rounded-lg">
      <div class="px-6 py-4 border-b border-gray-200">
        <h2 class="text-lg font-medium text-gray-900">Template Settings</h2>
      </div>
      
      <%= form_with model: [@business, @quote_template], url: @quote_template.persisted? ? admin_quote_template_path(@quote_template) : admin_quote_templates_path, 
                    local: true, class: "p-6 space-y-6" do |form| %>
        
        <div>
          <%= form.label :name, class: "block text-sm font-medium text-gray-700" %>
          <%= form.text_field :name, required: true,
                             class: "mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500" %>
        </div>
        
        <div>
          <%= form.label :template_type, class: "block text-sm font-medium text-gray-700" %>
          <%= form.select :template_type,
                         options_for_select(
                           QuoteTemplate.template_types.map { |k, v| [k.titleize, k] },
                           @quote_template.template_type
                         ),
                         {},
                         class: "mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500" %>
        </div>
        
        <!-- Display Options -->
        <div class="space-y-3">
          <h3 class="text-sm font-medium text-gray-900">Display Options</h3>
          
          <div class="flex items-center">
            <%= form.check_box :show_line_items, class: "rounded border-gray-300 text-blue-600 focus:ring-blue-500" %>
            <%= form.label :show_line_items, "Show individual line items", class: "ml-2 text-sm text-gray-700" %>
          </div>
          
          <div class="flex items-center">
            <%= form.check_box :show_item_descriptions, class: "rounded border-gray-300 text-blue-600 focus:ring-blue-500" %>
            <%= form.label :show_item_descriptions, "Show item descriptions", class: "ml-2 text-sm text-gray-700" %>
          </div>
          
          <div class="flex items-center">
            <%= form.check_box :show_totals, class: "rounded border-gray-300 text-blue-600 focus:ring-blue-500" %>
            <%= form.label :show_totals, "Show totals section", class: "ml-2 text-sm text-gray-700" %>
          </div>
          
          <div class="flex items-center">
            <%= form.check_box :show_terms, class: "rounded border-gray-300 text-blue-600 focus:ring-blue-500" %>
            <%= form.label :show_terms, "Show terms and conditions", class: "ml-2 text-sm text-gray-700" %>
          </div>
          
          <div class="flex items-center">
            <%= form.check_box :show_payment_schedule, class: "rounded border-gray-300 text-blue-600 focus:ring-blue-500" %>
            <%= form.label :show_payment_schedule, "Show payment schedule", class: "ml-2 text-sm text-gray-700" %>
          </div>
        </div>
        
        <!-- Template Content -->
        <div>
          <%= form.label :header_content, "Header Content", class: "block text-sm font-medium text-gray-700" %>
          <%= form.text_area :header_content, rows: 6,
                            class: "mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500" %>
          <p class="mt-1 text-sm text-gray-500">Use {{variable_name}} for dynamic content</p>
        </div>
        
        <div>
          <%= form.label :body_content, "Body Content (Optional)", class: "block text-sm font-medium text-gray-700" %>
          <%= form.text_area :body_content, rows: 4,
                            class: "mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500" %>
        </div>
        
        <div>
          <%= form.label :footer_content, "Footer Content", class: "block text-sm font-medium text-gray-700" %>
          <%= form.text_area :footer_content, rows: 4,
                            class: "mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500" %>
        </div>
        
        <div>
          <%= form.label :terms_and_conditions, "Terms and Conditions", class: "block text-sm font-medium text-gray-700" %>
          <%= form.text_area :terms_and_conditions, rows: 6,
                            class: "mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500" %>
        </div>
        
        <div class="flex items-center">
          <%= form.check_box :is_active, class: "rounded border-gray-300 text-blue-600 focus:ring-blue-500" %>
          <%= form.label :is_active, "Template is active", class: "ml-2 text-sm text-gray-700" %>
        </div>
        
        <div class="flex justify-end space-x-3">
          <%= link_to "Cancel", admin_quote_templates_path,
                      class: "bg-gray-300 hover:bg-gray-400 text-gray-700 font-medium py-2 px-4 rounded-md" %>
          <%= form.submit @quote_template.persisted? ? "Update Template" : "Create Template",
                          class: "bg-blue-600 hover:bg-blue-700 text-white font-medium py-2 px-4 rounded-md" %>
        </div>
      <% end %>
    </div>
    
    <!-- Available Variables -->
    <div class="bg-white shadow rounded-lg">
      <div class="px-6 py-4 border-b border-gray-200">
        <h2 class="text-lg font-medium text-gray-900">Available Variables</h2>
        <p class="text-sm text-gray-600">Use these variables in your template content</p>
      </div>
      
      <div class="p-6">
        <div class="space-y-4">
          <div>
            <h3 class="text-sm font-semibold text-gray-900 mb-2">Business Information</h3>
            <div class="grid grid-cols-1 gap-1 text-sm text-gray-600">
              <code>{{business_name}}</code>
              <code>{{business_address}}</code>
              <code>{{business_phone}}</code>
              <code>{{business_email}}</code>
            </div>
          </div>
          
          <div>
            <h3 class="text-sm font-semibold text-gray-900 mb-2">Customer Information</h3>
            <div class="grid grid-cols-1 gap-1 text-sm text-gray-600">
              <code>{{customer_name}}</code>
              <code>{{customer_address}}</code>
              <code>{{customer_phone}}</code>
              <code>{{customer_email}}</code>
            </div>
          </div>
          
          <div>
            <h3 class="text-sm font-semibold text-gray-900 mb-2">Quote Details</h3>
            <div class="grid grid-cols-1 gap-1 text-sm text-gray-600">
              <code>{{quote_number}}</code>
              <code>{{quote_date}}</code>
              <code>{{valid_until}}</code>
              <code>{{project_description}}</code>
              <code>{{notes}}</code>
            </div>
          </div>
          
          <div>
            <h3 class="text-sm font-semibold text-gray-900 mb-2">Financial</h3>
            <div class="grid grid-cols-1 gap-1 text-sm text-gray-600">
              <code>{{subtotal}}</code>
              <code>{{tax_amount}}</code>
              <code>{{total_amount}}</code>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</div>
```

## Acceptance Criteria
- [ ] Business owners can create custom quote templates with branding
- [ ] Templates support variable interpolation for dynamic content
- [ ] Multiple template types are available (standard, detailed, simple)
- [ ] Templates can be previewed with sample data
- [ ] Default templates are automatically created for new businesses
- [ ] Templates can be duplicated and customized
- [ ] One template can be set as the default for new quotes

## Testing Requirements
- Template rendering tests with various quote data
- Variable interpolation tests
- Template duplication functionality tests
- Default template creation tests
- Controller tests for template management
