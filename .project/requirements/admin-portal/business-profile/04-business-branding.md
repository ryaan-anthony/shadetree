# Feature: Business Branding & Customization

## Overview
Enable business owners to customize their brand appearance across all customer-facing materials including logos, color schemes, and branded templates for quotes and communications.

## User Stories
- As a business owner, I want to upload my logo so it appears on all quotes and customer communications
- As a business owner, I want to set my brand colors so quotes match my company branding
- As a business owner, I want to customize quote templates with my branding for professional appearance
- As a business owner, I want to preview how my branding looks before applying it

## Tasks

### 1. Business Branding Model
**File**: `app/models/business_branding.rb`

**Implementation Notes**:
```ruby
class BusinessBranding < ApplicationRecord
  belongs_to :business
  
  has_one_attached :logo
  has_one_attached :logo_dark # For dark backgrounds
  has_one_attached :favicon
  
  validates :primary_color, format: { with: /\A#[0-9a-fA-F]{6}\z/ }, allow_blank: true
  validates :secondary_color, format: { with: /\A#[0-9a-fA-F]{6}\z/ }, allow_blank: true
  validates :accent_color, format: { with: /\A#[0-9a-fA-F]{6}\z/ }, allow_blank: true
  validates :text_color, format: { with: /\A#[0-9a-fA-F]{6}\z/ }, allow_blank: true
  
  validate :logo_file_type, if: -> { logo.attached? }
  validate :logo_file_size, if: -> { logo.attached? }
  
  before_save :set_default_colors
  
  def logo_url(variant = :original)
    return nil unless logo.attached?
    
    case variant
    when :thumb
      logo.variant(resize_to_limit: [100, 100])
    when :medium
      logo.variant(resize_to_limit: [300, 300])
    when :large
      logo.variant(resize_to_limit: [600, 600])
    else
      logo
    end
  end
  
  def has_complete_branding?
    logo.attached? && 
    primary_color.present? && 
    secondary_color.present? && 
    business_tagline.present?
  end
  
  def color_palette
    {
      primary: primary_color || '#10B981',
      secondary: secondary_color || '#059669',
      accent: accent_color || '#F59E0B',
      text: text_color || '#1F2937'
    }
  end
  
  def css_variables
    palette = color_palette
    "--brand-primary: #{palette[:primary]}; " \
    "--brand-secondary: #{palette[:secondary]}; " \
    "--brand-accent: #{palette[:accent]}; " \
    "--brand-text: #{palette[:text]};"
  end
  
  private
  
  def logo_file_type
    unless logo.content_type.in?(['image/png', 'image/jpg', 'image/jpeg', 'image/svg+xml'])
      errors.add(:logo, 'must be a PNG, JPG, or SVG file')
    end
  end
  
  def logo_file_size
    if logo.byte_size > 5.megabytes
      errors.add(:logo, 'must be less than 5MB')
    end
  end
  
  def set_default_colors
    self.primary_color ||= '#10B981'
    self.secondary_color ||= '#059669'
    self.accent_color ||= '#F59E0B'
    self.text_color ||= '#1F2937'
  end
end
```

### 2. Branding Controller
**File**: `app/controllers/admin/business_branding_controller.rb`

**Implementation Notes**:
```ruby
class Admin::BusinessBrandingController < ApplicationController
  include BusinessContext
  
  before_action :require_business
  before_action :set_branding
  
  def show
    @preview_quote = build_preview_quote
  end
  
  def edit
  end
  
  def update
    if @branding.update(branding_params)
      redirect_to admin_business_branding_path, notice: "Branding updated successfully"
    else
      render :edit, status: :unprocessable_entity
    end
  end
  
  def preview
    @branding.assign_attributes(branding_params)
    @preview_quote = build_preview_quote
    
    render json: {
      html: render_to_string(partial: 'quote_preview', locals: { quote: @preview_quote, branding: @branding }),
      css: @branding.css_variables
    }
  end
  
  def remove_logo
    @branding.logo.purge
    redirect_to edit_admin_business_branding_path, notice: "Logo removed successfully"
  end
  
  private
  
  def set_branding
    @branding = current_business.business_branding || current_business.build_business_branding
  end
  
  def branding_params
    params.require(:business_branding).permit(
      :logo, :logo_dark, :favicon,
      :primary_color, :secondary_color, :accent_color, :text_color,
      :business_tagline, :quote_footer_text,
      :font_family, :show_logo_on_quotes,
      :quote_header_style, :quote_layout_style
    )
  end
  
  def build_preview_quote
    OpenStruct.new(
      quote_number: "PREVIEW-001",
      customer_name: "John Smith",
      customer_address: "123 Main St, Anytown, ST 12345",
      total_amount: 1250.00,
      created_at: Time.current,
      valid_until: 30.days.from_now,
      line_items: [
        OpenStruct.new(description: "Lawn Mowing Service", quantity: 1, price: 85.00),
        OpenStruct.new(description: "Tree Trimming", quantity: 2, price: 180.00),
        OpenStruct.new(description: "Landscape Design", quantity: 1, price: 985.00)
      ]
    )
  end
end
```

### 3. Branding Views
**File**: `app/views/admin/business_branding/show.html.erb`

**Implementation Notes**:
```erb
<div class="max-w-6xl mx-auto py-6">
  <div class="md:flex md:items-center md:justify-between mb-8">
    <div class="flex-1 min-w-0">
      <h1 class="text-2xl font-bold leading-7 text-gray-900 sm:text-3xl sm:truncate">
        Business Branding
      </h1>
      <p class="mt-1 text-sm text-gray-500">
        Customize your brand appearance across all customer materials
      </p>
    </div>
    <div class="mt-4 flex md:mt-0 md:ml-4">
      <%= link_to "Edit Branding", edit_admin_business_branding_path, 
          class: "bg-green-600 text-white px-4 py-2 rounded-md text-sm font-medium hover:bg-green-700" %>
    </div>
  </div>

  <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
    <!-- Current Branding -->
    <div class="space-y-6">
      <!-- Logo Section -->
      <div class="bg-white shadow overflow-hidden sm:rounded-lg">
        <div class="px-4 py-5 sm:px-6">
          <h3 class="text-lg leading-6 font-medium text-gray-900">Logo & Visual Identity</h3>
          <p class="mt-1 max-w-2xl text-sm text-gray-500">
            Your logo and visual branding elements
          </p>
        </div>
        <div class="border-t border-gray-200 px-4 py-5 sm:px-6">
          <% if @branding.logo.attached? %>
            <div class="flex items-center space-x-4">
              <div class="h-20 w-20 bg-gray-100 rounded-lg flex items-center justify-center">
                <%= image_tag @branding.logo_url(:thumb), class: "max-h-16 max-w-16 object-contain" %>
              </div>
              <div>
                <p class="text-sm font-medium text-gray-900">Current Logo</p>
                <p class="text-sm text-gray-500">
                  <%= @branding.logo.filename %> 
                  (<%= number_to_human_size(@branding.logo.byte_size) %>)
                </p>
              </div>
            </div>
          <% else %>
            <div class="text-center py-8">
              <div class="h-16 w-16 bg-gray-100 rounded-lg mx-auto flex items-center justify-center">
                <i data-feather="image" class="h-8 w-8 text-gray-400"></i>
              </div>
              <p class="mt-2 text-sm text-gray-500">No logo uploaded</p>
            </div>
          <% end %>
        </div>
      </div>

      <!-- Color Palette -->
      <div class="bg-white shadow overflow-hidden sm:rounded-lg">
        <div class="px-4 py-5 sm:px-6">
          <h3 class="text-lg leading-6 font-medium text-gray-900">Color Palette</h3>
          <p class="mt-1 max-w-2xl text-sm text-gray-500">
            Brand colors used across all materials
          </p>
        </div>
        <div class="border-t border-gray-200 px-4 py-5 sm:px-6">
          <div class="grid grid-cols-2 gap-4">
            <div class="text-center">
              <div class="h-16 w-16 rounded-lg mx-auto mb-2" 
                   style="background-color: <%= @branding.primary_color || '#10B981' %>"></div>
              <p class="text-xs font-medium text-gray-900">Primary</p>
              <p class="text-xs text-gray-500"><%= @branding.primary_color || '#10B981' %></p>
            </div>
            <div class="text-center">
              <div class="h-16 w-16 rounded-lg mx-auto mb-2" 
                   style="background-color: <%= @branding.secondary_color || '#059669' %>"></div>
              <p class="text-xs font-medium text-gray-900">Secondary</p>
              <p class="text-xs text-gray-500"><%= @branding.secondary_color || '#059669' %></p>
            </div>
            <div class="text-center">
              <div class="h-16 w-16 rounded-lg mx-auto mb-2" 
                   style="background-color: <%= @branding.accent_color || '#F59E0B' %>"></div>
              <p class="text-xs font-medium text-gray-900">Accent</p>
              <p class="text-xs text-gray-500"><%= @branding.accent_color || '#F59E0B' %></p>
            </div>
            <div class="text-center">
              <div class="h-16 w-16 rounded-lg mx-auto mb-2 border" 
                   style="background-color: <%= @branding.text_color || '#1F2937' %>"></div>
              <p class="text-xs font-medium text-gray-900">Text</p>
              <p class="text-xs text-gray-500"><%= @branding.text_color || '#1F2937' %></p>
            </div>
          </div>
        </div>
      </div>

      <!-- Brand Settings -->
      <div class="bg-white shadow overflow-hidden sm:rounded-lg">
        <div class="px-4 py-5 sm:px-6">
          <h3 class="text-lg leading-6 font-medium text-gray-900">Brand Settings</h3>
        </div>
        <div class="border-t border-gray-200">
          <dl class="divide-y divide-gray-200">
            <div class="px-4 py-4 sm:px-6 flex items-center justify-between">
              <dt class="text-sm font-medium text-gray-500">Business Tagline</dt>
              <dd class="text-sm text-gray-900">
                <%= @branding.business_tagline.presence || "Not set" %>
              </dd>
            </div>
            <div class="px-4 py-4 sm:px-6 flex items-center justify-between">
              <dt class="text-sm font-medium text-gray-500">Font Family</dt>
              <dd class="text-sm text-gray-900">
                <%= @branding.font_family.presence || "Default" %>
              </dd>
            </div>
            <div class="px-4 py-4 sm:px-6 flex items-center justify-between">
              <dt class="text-sm font-medium text-gray-500">Show Logo on Quotes</dt>
              <dd class="text-sm text-gray-900">
                <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium 
                             <%= @branding.show_logo_on_quotes? ? 'bg-green-100 text-green-800' : 'bg-gray-100 text-gray-800' %>">
                  <%= @branding.show_logo_on_quotes? ? 'Yes' : 'No' %>
                </span>
              </dd>
            </div>
          </dl>
        </div>
      </div>
    </div>

    <!-- Preview -->
    <div class="bg-white shadow overflow-hidden sm:rounded-lg">
      <div class="px-4 py-5 sm:px-6">
        <h3 class="text-lg leading-6 font-medium text-gray-900">Quote Preview</h3>
        <p class="mt-1 max-w-2xl text-sm text-gray-500">
          How your branding appears on customer quotes
        </p>
      </div>
      <div class="border-t border-gray-200 p-6">
        <%= render 'quote_preview', quote: @preview_quote, branding: @branding %>
      </div>
    </div>
  </div>
</div>

<script>
  feather.replace();
</script>
```

### 4. Quote Preview Partial
**File**: `app/views/admin/business_branding/_quote_preview.html.erb`

**Implementation Notes**:
```erb
<div class="bg-white border border-gray-200 rounded-lg p-6 max-w-md mx-auto" 
     style="<%= branding.css_variables %>">
  <!-- Header -->
  <div class="border-b border-gray-200 pb-4 mb-6">
    <div class="flex items-center justify-between">
      <% if branding.logo.attached? && branding.show_logo_on_quotes? %>
        <div class="h-12">
          <%= image_tag branding.logo_url(:medium), class: "h-12 object-contain" %>
        </div>
      <% else %>
        <div>
          <h2 class="text-xl font-bold" style="color: var(--brand-primary)">
            <%= current_business.name %>
          </h2>
          <% if branding.business_tagline.present? %>
            <p class="text-sm" style="color: var(--brand-secondary)">
              <%= branding.business_tagline %>
            </p>
          <% end %>
        </div>
      <% end %>
      
      <div class="text-right text-sm" style="color: var(--brand-text)">
        <p class="font-medium">Quote #<%= quote.quote_number %></p>
        <p><%= quote.created_at.strftime('%B %d, %Y') %></p>
      </div>
    </div>
  </div>

  <!-- Customer Info -->
  <div class="mb-6">
    <h3 class="text-sm font-medium mb-2" style="color: var(--brand-primary)">Quote For:</h3>
    <p class="text-sm" style="color: var(--brand-text)">
      <%= quote.customer_name %><br>
      <%= quote.customer_address %>
    </p>
  </div>

  <!-- Line Items -->
  <div class="mb-6">
    <table class="w-full text-sm">
      <thead>
        <tr class="border-b" style="border-color: var(--brand-secondary)">
          <th class="text-left py-2" style="color: var(--brand-primary)">Service</th>
          <th class="text-right py-2" style="color: var(--brand-primary)">Amount</th>
        </tr>
      </thead>
      <tbody>
        <% quote.line_items.each do |item| %>
          <tr>
            <td class="py-1" style="color: var(--brand-text)"><%= item.description %></td>
            <td class="py-1 text-right" style="color: var(--brand-text)">
              $<%= number_with_precision(item.price, precision: 2) %>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </div>

  <!-- Total -->
  <div class="border-t pt-4" style="border-color: var(--brand-secondary)">
    <div class="flex justify-between items-center">
      <span class="text-lg font-medium" style="color: var(--brand-primary)">Total:</span>
      <span class="text-xl font-bold" style="color: var(--brand-accent)">
        $<%= number_with_precision(quote.total_amount, precision: 2) %>
      </span>
    </div>
    <p class="text-xs mt-2" style="color: var(--brand-text)">
      Valid until <%= quote.valid_until.strftime('%B %d, %Y') %>
    </p>
  </div>

  <!-- Footer -->
  <% if branding.quote_footer_text.present? %>
    <div class="mt-6 pt-4 border-t text-center" style="border-color: var(--brand-secondary)">
      <p class="text-xs" style="color: var(--brand-text)">
        <%= branding.quote_footer_text %>
      </p>
    </div>
  <% end %>
</div>
```

### 5. Database Migration
**File**: `db/migrate/[timestamp]_create_business_brandings.rb`

**Implementation Notes**:
```ruby
class CreateBusinessBrandings < ActiveRecord::Migration[8.0]
  def change
    create_table :business_brandings do |t|
      t.references :business, null: false, foreign_key: true
      t.string :primary_color, default: '#10B981'
      t.string :secondary_color, default: '#059669'
      t.string :accent_color, default: '#F59E0B'
      t.string :text_color, default: '#1F2937'
      t.string :business_tagline
      t.text :quote_footer_text
      t.string :font_family, default: 'Inter'
      t.boolean :show_logo_on_quotes, default: true
      t.string :quote_header_style, default: 'modern'
      t.string :quote_layout_style, default: 'standard'
      
      t.timestamps
    end
    
    add_index :business_brandings, :business_id, unique: true
  end
end
```

### 6. Business Model Extension
**File**: `app/models/business.rb` (enhancement)

**Implementation Notes**:
```ruby
class Business < ApplicationRecord
  # ...existing code...
  
  has_one :business_branding, dependent: :destroy
  
  def branding
    business_branding || build_business_branding
  end
  
  def branded_color(type = :primary)
    branding.color_palette[type]
  end
end
```

## Branding Features
- **Logo Management**: Upload, preview, and manage business logos
- **Color Palette**: Set primary, secondary, accent, and text colors
- **Typography**: Choose fonts and text styling options
- **Quote Customization**: Preview how branding appears on customer quotes
- **Template Integration**: Apply branding to all quote templates

## File Requirements
- Supported formats: PNG, JPG, JPEG, SVG
- Maximum file size: 5MB
- Automatic resizing for different use cases (thumbnail, medium, large)
- Fallback to business name when no logo is present

## Integration Points
- Quote generation applies business branding automatically
- Email templates use business colors and logo
- Customer-facing materials reflect brand settings
- Preview functionality for real-time branding changes
