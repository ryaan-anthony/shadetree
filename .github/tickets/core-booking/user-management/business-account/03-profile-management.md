# Implementation Task: Profile Management System

## Overview
Create the profile management system that handles business profile information, settings, and customization.

## Technical Design

### Models
```ruby
class BusinessProfile < ApplicationRecord
  belongs_to :business
  has_one_attached :logo
  has_many_attached :gallery_images
  
  validates :business_name, presence: true
  validates :contact_email, format: { with: URI::MailTo::EMAIL_REGEXP }
  
  # Store complex data structures
  store :address, accessors: [:street, :city, :state, :zip], coder: JSON
  store :social_links, accessors: [:website, :facebook, :instagram], coder: JSON
  store :business_details, accessors: [:description, :founded_year, :tax_id], coder: JSON
end
```

### Controllers
```ruby
class Business::ProfilesController < BusinessController
  before_action :set_business_profile
  
  def edit
  end
  
  def update
    if @profile.update(profile_params)
      # Handle success
    else
      # Handle failure
    end
  end
  
  private
  
  def profile_params
    params.require(:business_profile).permit(
      :business_name, :contact_email, :phone,
      :logo, gallery_images: [],
      address: [:street, :city, :state, :zip],
      social_links: [:website, :facebook, :instagram],
      business_details: [:description, :founded_year, :tax_id]
    )
  end
end
```

### Service Objects
```ruby
class ProfileUpdateService
  def self.update(profile, params)
    Business.transaction do
      # Update profile
      # Process logo if changed
      # Handle gallery images
      # Update search indices
    end
  end
end
```

### Background Jobs
```ruby
class ProcessBusinessImagesJob < ApplicationJob
  def perform(profile_id)
    # Process and optimize logo
    # Process gallery images
    # Generate thumbnails
    # Update CDN
  end
end
```

## Views
1. Profile Edit Form
   - Basic Information
   - Address Information
   - Social Links
   - Logo Upload
   - Gallery Management

2. Profile Preview
   - Public View
   - Customer Portal View

## API Endpoints
```ruby
# PATCH /api/v1/business/profile
{
  "business_profile": {
    "business_name": "string",
    "contact_email": "string",
    "address": {
      "street": "string",
      "city": "string",
      "state": "string",
      "zip": "string"
    }
  }
}
```

## Testing Strategy
1. Model Tests
   - Validation rules
   - Data persistence
   - Image attachment

2. Controller Tests
   - Update scenarios
   - Validation handling
   - Image processing

3. Integration Tests
   - Complete profile update flow
   - Image processing workflow
   - API endpoints

## Security Considerations
- Image upload validation
- File type restrictions
- Size limits
- CSRF protection
- Data sanitization

## Estimated Hours: 16

## Dependencies
- Core Models implementation
- AWS S3 or similar for image storage
- Image processing library
