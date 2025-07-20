# Implementation Task: Service Selection

## Overview
Implement a service catalog system that allows businesses to manage their services and customers to browse and select services for booking.

## Technical Design

### Models
```ruby
class Service < ApplicationRecord
  belongs_to :business
  belongs_to :category, optional: true
  has_many :service_providers
  has_many :staff, through: :service_providers
  
  store :service_config, accessors: [
    :duration,
    :buffer_time,
    :max_participants,
    :preparation_time,
    :cleanup_time
  ]
  
  validates :name, :duration, :price, presence: true
  validates :active, inclusion: { in: [true, false] }
  
  scope :active, -> { where(active: true) }
  scope :bookable, -> { active.where('start_date <= ? AND end_date >= ?', Date.current, Date.current) }
end

class ServiceCategory < ApplicationRecord
  belongs_to :business
  has_many :services
  has_many :subcategories, class_name: 'ServiceCategory', foreign_key: 'parent_id'
  belongs_to :parent, class_name: 'ServiceCategory', optional: true
  
  validates :name, presence: true
  validate :prevent_deep_nesting
end

class ServiceProvider < ApplicationRecord
  belongs_to :service
  belongs_to :staff
  
  store :provider_config, accessors: [
    :proficiency_level,
    :custom_duration,
    :custom_price,
    :availability_override
  ]
end
```

### Service Layer
```ruby
module Services
  class CatalogService
    def initialize(business)
      @business = business
    end
    
    def available_services(filters = {})
      services = @business.services.bookable
      
      apply_category_filter(services, filters[:category])
      apply_provider_filter(services, filters[:provider])
      apply_duration_filter(services, filters[:duration])
      apply_price_filter(services, filters[:price_range])
      
      services
    end
  end
  
  class SelectionService
    def initialize(booking_flow)
      @flow = booking_flow
    end
    
    def select_service(service_id)
      service = Service.find(service_id)
      validate_service_availability(service)
      update_booking_flow(service)
    end
  end
end
```

## Implementation Steps

### Phase 1: Service Management
1. Catalog Structure
   - Category management
   - Service configuration
   - Provider assignment
   - Pricing setup

2. Service Rules
   - Availability rules
   - Booking constraints
   - Provider requirements
   - Time restrictions

3. Search & Filter
   - Category browsing
   - Provider filtering
   - Duration filtering
   - Price filtering

### Phase 2: Selection Flow
1. Service Selection
   - Availability check
   - Prerequisite validation
   - Conflict detection
   - Flow state update

2. Additional Options
   - Add-on services
   - Custom requirements
   - Special requests
   - Package deals

### Phase 3: Optimization
1. Performance
   - Catalog caching
   - Search optimization
   - Filter indexing
   - Bulk operations

## API Design

### RESTful Endpoints
```ruby
namespace :api do
  namespace :v1 do
    resources :services do
      collection do
        get :categories
        get :available
        get :featured
      end
      member do
        get :providers
        get :availability
        get :requirements
      end
    end
  end
end
```

## Cache Strategy

### Redis Implementation
```ruby
class ServiceCache
  def cache_key(business_id, filters = {})
    "services:#{business_id}:#{filters.to_param}"
  end
  
  def cache_catalog(business_id, services, filters = {})
    Redis.current.setex(
      cache_key(business_id, filters),
      1.hour.to_i,
      services.to_json
    )
  end
end
```

## Testing Strategy

### Unit Tests
- Model validations
- Service availability
- Price calculations
- Filter logic

### Integration Tests
- Catalog browsing
- Service selection
- Provider matching
- Flow updates

### Performance Tests
- Large catalogs
- Complex filters
- Concurrent access
- Cache efficiency

## Monitoring

### Key Metrics
- Selection completion rate
- Search response time
- Cache hit ratio
- Error frequency

### Health Checks
- Catalog availability
- Search functionality
- Cache status
- API response time

## Documentation

### Technical Guide
1. Model Structure
2. Service Configuration
3. Integration Points
4. Cache Strategy

### User Guide
1. Service Setup
2. Category Management
3. Provider Assignment
4. Pricing Configuration
