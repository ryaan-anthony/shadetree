# Feature: Location & Service Areas

## Description
Comprehensive location management system that allows businesses to define their physical locations, service delivery areas, and geographic coverage with integrated mapping and distance calculations.

## User Stories
- As a business owner, I want to set my business location so customers can find me
- As a service provider, I want to define my service areas so customers know if I serve their location
- As a business owner, I want to calculate travel fees based on distance so I can price appropriately
- As a customer, I want to see if a business serves my area before booking

## Tasks

### Task 1: Create Location Models
**Implementation Notes:**
- Create models for business locations and service areas
- Include geocoding integration for address validation
- Support multiple locations for franchise businesses

```ruby
# app/models/business_location.rb
class BusinessLocation < ApplicationRecord
  belongs_to :business
  has_many :service_areas, dependent: :destroy
  
  validates :name, presence: true
  validates :address, presence: true
  validates :city, :state, :zip_code, presence: true
  validates :latitude, :longitude, presence: true, numericality: true
  
  geocoded_by :full_address
  after_validation :geocode, if: :address_changed?
  
  scope :primary, -> { where(is_primary: true) }
  scope :active, -> { where(active: true) }
  
  def full_address
    [address, city, state, zip_code].compact.join(', ')
  end
  
  def distance_to(other_location)
    return nil unless other_location.respond_to?(:latitude) && other_location.respond_to?(:longitude)
    
    Geocoder::Calculations.distance_between(
      [latitude, longitude],
      [other_location.latitude, other_location.longitude]
    )
  end
  
  def serves_location?(check_latitude, check_longitude)
    service_areas.active.any? do |area|
      area.covers_location?(check_latitude, check_longitude)
    end
  end
  
  private
  
  def address_changed?
    address_changed? || city_changed? || state_changed? || zip_code_changed?
  end
end

# app/models/service_area.rb
class ServiceArea < ApplicationRecord
  belongs_to :business_location
  
  validates :name, presence: true
  validates :area_type, presence: true
  validates :max_distance_miles, presence: true, numericality: { greater_than: 0 }
  
  enum area_type: {
    radius: 0,
    zip_codes: 1,
    custom_polygon: 2
  }
  
  scope :active, -> { where(active: true) }
  
  def covers_location?(latitude, longitude)
    return false unless active?
    
    case area_type
    when 'radius'
      covers_radius?(latitude, longitude)
    when 'zip_codes'
      covers_zip_codes?(latitude, longitude)
    when 'custom_polygon'
      covers_polygon?(latitude, longitude)
    else
      false
    end
  end
  
  def travel_fee_for_distance(distance_miles)
    return 0 if distance_miles <= free_distance_miles
    
    case pricing_model
    when 'flat_rate'
      flat_rate_fee
    when 'per_mile'
      (distance_miles - free_distance_miles) * per_mile_rate
    when 'tiered'
      calculate_tiered_fee(distance_miles)
    else
      0
    end
  end
  
  private
  
  def covers_radius?(latitude, longitude)
    distance = Geocoder::Calculations.distance_between(
      [business_location.latitude, business_location.longitude],
      [latitude, longitude]
    )
    distance <= max_distance_miles
  end
  
  def covers_zip_codes?(latitude, longitude)
    # Reverse geocode to get zip code, then check if it's in our list
    results = Geocoder.search([latitude, longitude])
    return false unless results.first
    
    zip_code = results.first.postal_code
    covered_zip_codes.include?(zip_code)
  end
  
  def covers_polygon?(latitude, longitude)
    # Implementation would depend on polygon geometry library
    # For now, return false - this would need PostGIS or similar
    false
  end
  
  def calculate_tiered_fee(distance_miles)
    # Implementation for tiered pricing based on distance ranges
    excess_distance = distance_miles - free_distance_miles
    # This would implement tiered rates stored in a JSON field
    0
  end
end

# Migrations
# rails g model BusinessLocation business:references name:string address:string city:string state:string zip_code:string latitude:decimal longitude:decimal is_primary:boolean active:boolean
class CreateBusinessLocations < ActiveRecord::Migration[8.0]
  def change
    create_table :business_locations do |t|
      t.references :business, null: false, foreign_key: true
      t.string :name, null: false
      t.string :address, null: false
      t.string :city, null: false
      t.string :state, null: false
      t.string :zip_code, null: false
      t.decimal :latitude, precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6
      t.boolean :is_primary, default: false
      t.boolean :active, default: true
      t.text :description
      t.string :phone_number
      t.timestamps
    end
    
    add_index :business_locations, [:business_id, :is_primary]
    add_index :business_locations, [:latitude, :longitude]
  end
end

# rails g model ServiceArea business_location:references name:string area_type:integer max_distance_miles:decimal pricing_model:string flat_rate_fee:decimal per_mile_rate:decimal free_distance_miles:decimal covered_zip_codes:text active:boolean
class CreateServiceAreas < ActiveRecord::Migration[8.0]
  def change
    create_table :service_areas do |t|
      t.references :business_location, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :area_type, default: 0
      t.decimal :max_distance_miles, precision: 8, scale: 2, null: false
      t.string :pricing_model, default: 'flat_rate'
      t.decimal :flat_rate_fee, precision: 8, scale: 2, default: 0
      t.decimal :per_mile_rate, precision: 8, scale: 2, default: 0
      t.decimal :free_distance_miles, precision: 8, scale: 2, default: 0
      t.text :covered_zip_codes
      t.text :polygon_coordinates
      t.boolean :active, default: true
      t.timestamps
    end
    
    add_index :service_areas, :business_location_id
  end
end
```

### Task 2: Create Location Service
**Implementation Notes:**
- Service for location-based operations and calculations
- Integration with geocoding APIs
- Distance and travel fee calculations

```ruby
# app/services/admin/location_service.rb
class Admin::LocationService
  attr_reader :business

  def initialize(business)
    @business = business
  end

  def serves_address?(address)
    coordinates = geocode_address(address)
    return false unless coordinates
    
    serves_coordinates?(coordinates[:latitude], coordinates[:longitude])
  end

  def serves_coordinates?(latitude, longitude)
    business.business_locations.active.any? do |location|
      location.serves_location?(latitude, longitude)
    end
  end

  def calculate_travel_fee(customer_address)
    coordinates = geocode_address(customer_address)
    return 0 unless coordinates
    
    nearest_location = find_nearest_location(coordinates[:latitude], coordinates[:longitude])
    return 0 unless nearest_location
    
    distance = nearest_location.distance_to(coordinates)
    service_area = find_covering_service_area(nearest_location, coordinates[:latitude], coordinates[:longitude])
    
    service_area&.travel_fee_for_distance(distance) || 0
  end

  def find_nearest_location(latitude, longitude)
    business.business_locations.active.min_by do |location|
      location.distance_to(OpenStruct.new(latitude: latitude, longitude: longitude))
    end
  end

  def coverage_summary
    {
      total_locations: business.business_locations.active.count,
      service_areas: business.business_locations.active.joins(:service_areas)
                            .where(service_areas: { active: true }).count,
      max_coverage_miles: business.business_locations.active.joins(:service_areas)
                                 .where(service_areas: { active: true })
                                 .maximum('service_areas.max_distance_miles') || 0
    }
  end

  def validate_address(address)
    results = Geocoder.search(address)
    return { valid: false, error: 'Address not found' } unless results.first
    
    result = results.first
    {
      valid: true,
      formatted_address: result.formatted_address,
      latitude: result.latitude,
      longitude: result.longitude,
      city: result.city,
      state: result.state,
      zip_code: result.postal_code
    }
  end

  private

  def geocode_address(address)
    results = Geocoder.search(address)
    return nil unless results.first
    
    result = results.first
    {
      latitude: result.latitude,
      longitude: result.longitude
    }
  end

  def find_covering_service_area(location, latitude, longitude)
    location.service_areas.active.find do |area|
      area.covers_location?(latitude, longitude)
    end
  end
end
```

### Task 3: Create Location Controllers
**Implementation Notes:**
- Controllers for managing locations and service areas
- Address validation and geocoding endpoints
- Service area coverage testing

```ruby
# app/controllers/admin/business_locations_controller.rb
class Admin::BusinessLocationsController < Admin::BaseController
  before_action :authenticate_admin!
  before_action :authorize_business_management!
  before_action :set_business_location, only: [:show, :edit, :update, :destroy, :set_primary]

  def index
    @business_locations = current_admin.business.business_locations.includes(:service_areas)
    @location_service = Admin::LocationService.new(current_admin.business)
    @coverage_summary = @location_service.coverage_summary
  end

  def show
    @service_areas = @business_location.service_areas.active
  end

  def new
    @business_location = current_admin.business.business_locations.build
  end

  def create
    @business_location = current_admin.business.business_locations.build(business_location_params)
    
    if @business_location.save
      track_location_creation
      redirect_to admin_business_locations_path, notice: 'Location created successfully'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @business_location.update(business_location_params)
      track_location_update
      redirect_to admin_business_location_path(@business_location), notice: 'Location updated successfully'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @business_location.destroy
    track_location_deletion
    redirect_to admin_business_locations_path, notice: 'Location deleted successfully'
  end

  def set_primary
    current_admin.business.business_locations.update_all(is_primary: false)
    @business_location.update!(is_primary: true)
    
    track_primary_location_change
    redirect_to admin_business_locations_path, notice: 'Primary location updated'
  end

  def validate_address
    address = params[:address]
    location_service = Admin::LocationService.new(current_admin.business)
    result = location_service.validate_address(address)
    
    render json: result
  end

  private

  def set_business_location
    @business_location = current_admin.business.business_locations.find(params[:id])
  end

  def business_location_params
    params.require(:business_location).permit(
      :name, :address, :city, :state, :zip_code, :description, :phone_number, :active
    )
  end

  def track_location_creation
    Admin::ActivityTrackingService.new(current_admin.business)
                                  .track_system_event(
                                    'business_location_created',
                                    "New location added: #{@business_location.name}",
                                    priority: 'normal'
                                  )
  end

  def track_location_update
    Admin::ActivityTrackingService.new(current_admin.business)
                                  .track_business_setting_changed(
                                    'business_location',
                                    current_admin,
                                    @business_location.changes
                                  )
  end

  def track_location_deletion
    Admin::ActivityTrackingService.new(current_admin.business)
                                  .track_system_event(
                                    'business_location_deleted',
                                    "Location deleted: #{@business_location.name}",
                                    priority: 'high'
                                  )
  end

  def track_primary_location_change
    Admin::ActivityTrackingService.new(current_admin.business)
                                  .track_business_setting_changed(
                                    'primary_location',
                                    current_admin,
                                    { primary_location: @business_location.name }
                                  )
  end
end

# app/controllers/admin/service_areas_controller.rb
class Admin::ServiceAreasController < Admin::BaseController
  before_action :authenticate_admin!
  before_action :authorize_business_management!
  before_action :set_business_location
  before_action :set_service_area, only: [:show, :edit, :update, :destroy, :test_coverage]

  def index
    @service_areas = @business_location.service_areas.includes(:business_location)
  end

  def new
    @service_area = @business_location.service_areas.build
  end

  def create
    @service_area = @business_location.service_areas.build(service_area_params)
    
    if @service_area.save
      track_service_area_creation
      redirect_to admin_business_location_service_areas_path(@business_location), 
                  notice: 'Service area created successfully'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @service_area.update(service_area_params)
      track_service_area_update
      redirect_to admin_business_location_service_area_path(@business_location, @service_area),
                  notice: 'Service area updated successfully'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @service_area.destroy
    track_service_area_deletion
    redirect_to admin_business_location_service_areas_path(@business_location),
                notice: 'Service area deleted successfully'
  end

  def test_coverage
    test_address = params[:test_address]
    location_service = Admin::LocationService.new(current_admin.business)
    
    address_validation = location_service.validate_address(test_address)
    unless address_validation[:valid]
      render json: { covered: false, error: address_validation[:error] }
      return
    end
    
    covered = @service_area.covers_location?(
      address_validation[:latitude], 
      address_validation[:longitude]
    )
    
    if covered
      distance = @business_location.distance_to(
        OpenStruct.new(
          latitude: address_validation[:latitude],
          longitude: address_validation[:longitude]
        )
      )
      travel_fee = @service_area.travel_fee_for_distance(distance)
      
      render json: { 
        covered: true, 
        distance: distance.round(2),
        travel_fee: travel_fee.round(2)
      }
    else
      render json: { covered: false }
    end
  end

  private

  def set_business_location
    @business_location = current_admin.business.business_locations.find(params[:business_location_id])
  end

  def set_service_area
    @service_area = @business_location.service_areas.find(params[:id])
  end

  def service_area_params
    params.require(:service_area).permit(
      :name, :area_type, :max_distance_miles, :pricing_model,
      :flat_rate_fee, :per_mile_rate, :free_distance_miles,
      :covered_zip_codes, :active
    )
  end

  def track_service_area_creation
    Admin::ActivityTrackingService.new(current_admin.business)
                                  .track_system_event(
                                    'service_area_created',
                                    "Service area created: #{@service_area.name}",
                                    priority: 'normal'
                                  )
  end

  def track_service_area_update
    Admin::ActivityTrackingService.new(current_admin.business)
                                  .track_business_setting_changed(
                                    'service_area',
                                    current_admin,
                                    @service_area.changes
                                  )
  end

  def track_service_area_deletion
    Admin::ActivityTrackingService.new(current_admin.business)
                                  .track_system_event(
                                    'service_area_deleted',
                                    "Service area deleted: #{@service_area.name}",
                                    priority: 'normal'
                                  )
  end
end
```

### Task 4: Add Location Routes
**Implementation Notes:**
- Nested routes for locations and service areas
- Special routes for validation and testing

```ruby
# Add to config/routes.rb
namespace :admin do
  # ...existing routes...
  resources :business_locations do
    member do
      patch :set_primary
    end
    collection do
      post :validate_address
    end
    resources :service_areas do
      member do
        post :test_coverage
      end
    end
  end
end
```

### Task 5: Add Geocoding Configuration
**Implementation Notes:**
- Configure geocoding gem for address validation
- Set up API keys and rate limiting

```ruby
# Add to Gemfile
gem 'geocoder'

# config/initializers/geocoder.rb
Geocoder.configure(
  # Geocoding service (see geocoder's documentation for supported APIs)
  lookup: :google,
  
  # API key for Google Geocoding API
  api_key: Rails.application.credentials.google_maps_api_key,
  
  # Request timeout (in seconds)
  timeout: 3,
  
  # Use HTTPS for requests
  use_https: true,
  
  # Rate limiting
  cache: Redis.new(url: ENV['REDIS_URL']) if Rails.env.production?,
  
  # Units for distance calculations
  units: :mi
)
```

## Acceptance Criteria
- [ ] Business owners can add and manage multiple locations
- [ ] Address validation ensures accurate geocoding
- [ ] Service areas properly calculate coverage and travel fees
- [ ] Distance calculations are accurate within acceptable margin
- [ ] Coverage testing tool works for any address
- [ ] Mobile interface supports location management

## Testing Requirements
- Unit tests for location and service area models
- Integration tests for geocoding functionality
- Distance calculation accuracy tests
- Service area coverage logic verification
- API integration tests for geocoding services
