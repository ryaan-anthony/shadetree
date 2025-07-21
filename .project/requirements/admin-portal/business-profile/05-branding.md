# Feature: Business Branding

## Description
Visual identity management system that allows businesses to upload logos, set brand colors, and customize the appearance of customer-facing interfaces to maintain consistent branding across all touchpoints.

## User Stories
- As a business owner, I want to upload my logo so it appears on all customer communications
- As a business owner, I want to set my brand colors so the booking interface matches my brand
- As a business owner, I want to customize my booking page so it reflects my business personality
- As a customer, I want to see consistent branding so I feel confident about the business

## Tasks

### Task 1: Create Business Branding Model
**Implementation Notes:**
- Create model to store branding assets and configuration
- Include image upload functionality with processing
- Support color schemes and customization options

```ruby
# app/models/business_branding.rb
class BusinessBranding < ApplicationRecord
  belongs_to :business
  
  has_one_attached :logo
  has_one_attached :favicon
  has_one_attached :background_image
  
  validates :primary_color, format: { with: /\A#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})\z/, message: 'must be a valid hex color' }, allow_blank: true
  validates :secondary_color, format: { with: /\A#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})\z/, message: 'must be a valid hex color' }, allow_blank: true
  validates :accent_color, format: { with: /\A#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})\z/, message: 'must be a valid hex color' }, allow_blank: true
  
  validate :logo_format, if: -> { logo.attached? }
  validate :logo_size, if: -> { logo.attached? }
  
  before_save :generate_color_variations
  
  def logo_url(size: :medium)
    return nil unless logo.attached?
    
    case size
    when :small
      logo.variant(resize_to_limit: [100, 100])
    when :medium
      logo.variant(resize_to_limit: [300, 300])
    when :large
      logo.variant(resize_to_limit: [600, 600])
    else
      logo
    end
  end
  
  def has_custom_branding?
    logo.attached? || primary_color.present? || custom_css.present?
  end
  
  def color_palette
    {
      primary: primary_color || '#3B82F6',
      secondary: secondary_color || '#6B7280',
      accent: accent_color || '#10B981',
      primary_light: primary_light_color,
      primary_dark: primary_dark_color
    }
  end
  
  def css_variables
    palette = color_palette
    {
      '--brand-primary': palette[:primary],
      '--brand-secondary': palette[:secondary],
      '--brand-accent': palette[:accent],
      '--brand-primary-light': palette[:primary_light],
      '--brand-primary-dark': palette[:primary_dark]
    }
  end
  
  private
  
  def logo_format
    acceptable_types = ['image/jpeg', 'image/png', 'image/svg+xml']
    unless acceptable_types.include?(logo.content_type)
      errors.add(:logo, 'must be a JPEG, PNG, or SVG image')
    end
  end
  
  def logo_size
    if logo.byte_size > 2.megabytes
      errors.add(:logo, 'must be less than 2MB')
    end
  end
  
  def generate_color_variations
    if primary_color.present?
      # Generate lighter and darker variations of primary color
      self.primary_light_color = lighten_color(primary_color, 0.2)
      self.primary_dark_color = darken_color(primary_color, 0.2)
    end
  end
  
  def lighten_color(hex_color, amount)
    # Simple color manipulation - in production, use a color library
    hex_color # Placeholder implementation
  end
  
  def darken_color(hex_color, amount)
    # Simple color manipulation - in production, use a color library
    hex_color # Placeholder implementation
  end
end

# Migration
# rails g model BusinessBranding business:references primary_color:string secondary_color:string accent_color:string custom_css:text booking_page_title:string booking_page_description:text
class CreateBusinessBrandings < ActiveRecord::Migration[8.0]
  def change
    create_table :business_brandings do |t|
      t.references :business, null: false, foreign_key: true
      
      # Color scheme
      t.string :primary_color
      t.string :secondary_color
      t.string :accent_color
      t.string :primary_light_color
      t.string :primary_dark_color
      
      # Typography
      t.string :font_family, default: 'Inter'
      t.string :heading_font_family
      
      # Custom styling
      t.text :custom_css
      t.text :custom_javascript
      
      # Booking page customization
      t.string :booking_page_title
      t.text :booking_page_description
      t.string :booking_page_subtitle
      t.text :welcome_message
      t.text :footer_text
      
      # Social media
      t.string :facebook_url
      t.string :instagram_url
      t.string :twitter_url
      t.string :linkedin_url
      t.string :website_url
      
      t.timestamps
    end
    
    add_index :business_brandings, :business_id, unique: true
  end
end
```

### Task 2: Create Branding Service
**Implementation Notes:**
- Service for image processing and optimization
- Color scheme generation and validation
- CSS generation for customer-facing interfaces

```ruby
# app/services/admin/branding_service.rb
class Admin::BrandingService
  attr_reader :business, :branding

  def initialize(business)
    @business = business
    @branding = business.business_branding || build_default_branding
  end

  def generate_customer_css
    return default_css unless branding.has_custom_branding?
    
    css_vars = branding.css_variables.map { |key, value| "#{key}: #{value};" }.join("\n  ")
    
    base_css = <<~CSS
      :root {
        #{css_vars}
      }
      
      .brand-primary { color: var(--brand-primary); }
      .brand-secondary { color: var(--brand-secondary); }
      .brand-accent { color: var(--brand-accent); }
      
      .bg-brand-primary { background-color: var(--brand-primary); }
      .bg-brand-secondary { background-color: var(--brand-secondary); }
      .bg-brand-accent { background-color: var(--brand-accent); }
      
      .border-brand-primary { border-color: var(--brand-primary); }
      
      .btn-brand-primary {
        background-color: var(--brand-primary);
        border-color: var(--brand-primary);
        color: white;
      }
      
      .btn-brand-primary:hover {
        background-color: var(--brand-primary-dark);
        border-color: var(--brand-primary-dark);
      }
      
      .booking-header {
        background: linear-gradient(135deg, var(--brand-primary), var(--brand-primary-light));
      }
    CSS
    
    custom_css = branding.custom_css.present? ? "\n\n#{branding.custom_css}" : ""
    base_css + custom_css
  end

  def process_logo_upload(logo_file)
    return { success: false, error: 'No file provided' } unless logo_file
    
    # Validate file type and size
    unless valid_image_type?(logo_file.content_type)
      return { success: false, error: 'Invalid file type. Please use JPEG, PNG, or SVG.' }
    end
    
    if logo_file.size > 2.megabytes
      return { success: false, error: 'File too large. Please use an image under 2MB.' }
    end
    
    # Attach and process the logo
    branding.logo.attach(logo_file)
    
    if branding.save
      { success: true, logo_url: branding.logo_url }
    else
      { success: false, error: branding.errors.full_messages.join(', ') }
    end
  end

  def generate_color_scheme(base_color)
    # Generate a complete color scheme from a base color
    # This would use a color theory library in production
    {
      primary: base_color,
      secondary: adjust_color_lightness(base_color, -20),
      accent: generate_complementary_color(base_color),
      light: adjust_color_lightness(base_color, 40),
      dark: adjust_color_lightness(base_color, -40)
    }
  end

  def preview_branding(params)
    # Generate a preview of how the branding will look
    temp_branding = branding.dup
    temp_branding.assign_attributes(params.slice(:primary_color, :secondary_color, :accent_color))
    
    {
      css: generate_preview_css(temp_branding),
      color_palette: temp_branding.color_palette,
      has_logo: params[:logo].present? || branding.logo.attached?
    }
  end

  def booking_page_configuration
    {
      title: branding.booking_page_title || "Book with #{business.name}",
      description: branding.booking_page_description || "Schedule your appointment with us",
      subtitle: branding.booking_page_subtitle,
      welcome_message: branding.welcome_message,
      footer_text: branding.footer_text,
      social_links: {
        facebook: branding.facebook_url,
        instagram: branding.instagram_url,
        twitter: branding.twitter_url,
        linkedin: branding.linkedin_url,
        website: branding.website_url
      }.compact,
      logo_url: branding.logo.attached? ? branding.logo_url : nil,
      css: generate_customer_css
    }
  end

  private

  def build_default_branding
    business.build_business_branding(
      primary_color: '#3B82F6',
      secondary_color: '#6B7280',
      accent_color: '#10B981'
    )
  end

  def default_css
    <<~CSS
      :root {
        --brand-primary: #3B82F6;
        --brand-secondary: #6B7280;
        --brand-accent: #10B981;
      }
    CSS
  end

  def valid_image_type?(content_type)
    ['image/jpeg', 'image/png', 'image/svg+xml'].include?(content_type)
  end

  def adjust_color_lightness(hex_color, percent)
    # Placeholder for color manipulation
    # In production, use a proper color library like 'color' gem
    hex_color
  end

  def generate_complementary_color(hex_color)
    # Placeholder for complementary color generation
    hex_color
  end

  def generate_preview_css(temp_branding)
    css_vars = temp_branding.css_variables.map { |key, value| "#{key}: #{value};" }.join("\n  ")
    
    <<~CSS
      :root {
        #{css_vars}
      }
    CSS
  end
end
```

### Task 3: Create Branding Controller
**Implementation Notes:**
- Handle image uploads and branding configuration
- Include preview functionality
- Support color scheme generation

```ruby
# app/controllers/admin/business_branding_controller.rb
class Admin::BusinessBrandingController < Admin::BaseController
  before_action :authenticate_admin!
  before_action :authorize_business_management!
  before_action :load_branding

  def show
    @branding_service = Admin::BrandingService.new(current_admin.business)
    @booking_config = @branding_service.booking_page_configuration
    @preview_url = customer_booking_url(subdomain: current_admin.business.subdomain)
  end

  def edit
    @color_presets = color_presets
  end

  def update
    if @branding.update(branding_params)
      track_branding_update
      redirect_to admin_business_branding_path, notice: 'Branding updated successfully'
    else
      @color_presets = color_presets
      render :edit, status: :unprocessable_entity
    end
  end

  def upload_logo
    logo_file = params[:logo]
    branding_service = Admin::BrandingService.new(current_admin.business)
    result = branding_service.process_logo_upload(logo_file)
    
    if result[:success]
      track_logo_upload
      render json: { success: true, logo_url: url_for(@branding.logo_url) }
    else
      render json: { success: false, error: result[:error] }
    end
  end

  def remove_logo
    @branding.logo.purge if @branding.logo.attached?
    track_logo_removal
    redirect_to edit_admin_business_branding_path, notice: 'Logo removed successfully'
  end

  def preview
    branding_service = Admin::BrandingService.new(current_admin.business)
    preview_data = branding_service.preview_branding(preview_params)
    
    render json: preview_data
  end

  def generate_color_scheme
    base_color = params[:base_color]
    branding_service = Admin::BrandingService.new(current_admin.business)
    color_scheme = branding_service.generate_color_scheme(base_color)
    
    render json: color_scheme
  end

  def reset_to_defaults
    @branding.update!(
      primary_color: '#3B82F6',
      secondary_color: '#6B7280',
      accent_color: '#10B981',
      custom_css: nil,
      booking_page_title: nil,
      booking_page_description: nil
    )
    
    track_branding_reset
    redirect_to admin_business_branding_path, notice: 'Branding reset to defaults'
  end

  private

  def load_branding
    @branding = current_admin.business.business_branding || 
                current_admin.business.build_business_branding
  end

  def branding_params
    params.require(:business_branding).permit(
      :primary_color, :secondary_color, :accent_color, :font_family, :heading_font_family,
      :custom_css, :booking_page_title, :booking_page_description, :booking_page_subtitle,
      :welcome_message, :footer_text, :facebook_url, :instagram_url, :twitter_url,
      :linkedin_url, :website_url
    )
  end

  def preview_params
    params.permit(:primary_color, :secondary_color, :accent_color, :logo)
  end

  def color_presets
    [
      { name: 'Ocean Blue', primary: '#0EA5E9', secondary: '#0369A1', accent: '#06B6D4' },
      { name: 'Forest Green', primary: '#059669', secondary: '#047857', accent: '#10B981' },
      { name: 'Sunset Orange', primary: '#EA580C', secondary: '#C2410C', accent: '#F97316' },
      { name: 'Royal Purple', primary: '#7C3AED', secondary: '#5B21B6', accent: '#8B5CF6' },
      { name: 'Rose Pink', primary: '#E11D48', secondary: '#BE123C', accent: '#F43F5E' },
      { name: 'Slate Gray', primary: '#475569', secondary: '#334155', accent: '#64748B' }
    ]
  end

  def track_branding_update
    Admin::ActivityTrackingService.new(current_admin.business)
                                  .track_business_setting_changed(
                                    'business_branding',
                                    current_admin,
                                    @branding.changes
                                  )
  end

  def track_logo_upload
    Admin::ActivityTrackingService.new(current_admin.business)
                                  .track_system_event(
                                    'logo_uploaded',
                                    'Business logo uploaded',
                                    priority: 'normal'
                                  )
  end

  def track_logo_removal
    Admin::ActivityTrackingService.new(current_admin.business)
                                  .track_system_event(
                                    'logo_removed',
                                    'Business logo removed',
                                    priority: 'normal'
                                  )
  end

  def track_branding_reset
    Admin::ActivityTrackingService.new(current_admin.business)
                                  .track_business_setting_changed(
                                    'branding_reset',
                                    current_admin
                                  )
  end
end
```

### Task 4: Add Branding Routes
**Implementation Notes:**
- Add routes for branding management and uploads
- Include special endpoints for preview and color generation

```ruby
# Add to config/routes.rb
namespace :admin do
  # ...existing routes...
  resource :business_branding, only: [:show, :edit, :update] do
    collection do
      post :upload_logo
      delete :remove_logo
      post :preview
      post :generate_color_scheme
      patch :reset_to_defaults
    end
  end
end
```

### Task 5: Integration with Business Model
**Implementation Notes:**
- Add association to Business model
- Create default branding on business creation

```ruby
# Add to app/models/business.rb
class Business < ApplicationRecord
  # ...existing associations...
  has_one :business_branding, dependent: :destroy
  
  after_create :create_default_branding
  
  private
  
  def create_default_branding
    create_business_branding!(
      primary_color: '#3B82F6',
      secondary_color: '#6B7280',
      accent_color: '#10B981'
    )
  end
end
```

### Task 6: Add Image Processing Dependencies
**Implementation Notes:**
- Configure Active Storage for image variants
- Add image processing gems

```ruby
# Add to Gemfile
gem 'image_processing', '~> 1.2'

# config/application.rb
config.active_storage.variant_processor = :mini_magick
```

## Acceptance Criteria
- [ ] Business owners can upload and manage logo images
- [ ] Color scheme configuration updates customer-facing interfaces
- [ ] Custom CSS allows advanced styling customization
- [ ] Preview functionality shows branding changes before saving
- [ ] Image uploads are processed and optimized correctly
- [ ] Social media links integrate properly with booking pages

## Testing Requirements
- Unit tests for BusinessBranding model validations
- Service tests for image processing and CSS generation
- Integration tests for logo upload functionality
- Color scheme generation verification
- Preview functionality testing
