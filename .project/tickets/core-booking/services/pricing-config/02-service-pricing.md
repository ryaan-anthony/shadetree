# Implementation Task: Service Pricing

## Overview
Create a system for managing service-specific pricing configurations, including base prices, variations, and service-level rules.

## Technical Design

### Models
```ruby
class ServicePricing < ApplicationRecord
  belongs_to :service
  belongs_to :pricing_engine
  
  validates :pricing_model, inclusion: { in: %w[fixed tiered dynamic package custom] }
  
  # Store pricing configuration
  store :price_config, accessors: [
    :base_price,
    :price_ranges,
    :variation_prices,
    :volume_rules
  ], coder: JSON
end

class PriceVariation < ApplicationRecord
  belongs_to :service_pricing
  
  validates :variation_type, inclusion: { in: %w[option addon upgrade custom] }
  
  # Store variation configuration
  store :variation_config, accessors: [
    :price_adjustment,
    :calculation_method,
    :constraints,
    :dependencies
  ], coder: JSON
end

class ServicePackage < ApplicationRecord
  belongs_to :service_pricing
  has_many :package_items
  
  validates :package_type, inclusion: { in: %w[bundle series subscription] }
  
  # Store package configuration
  store :package_config, accessors: [
    :pricing_strategy,
    :discount_rules,
    :duration_rules,
    :renewal_settings
  ], coder: JSON
end
```

### Service Objects
```ruby
class ServicePricingService
  def self.configure_pricing(service, params)
    ServicePricing.transaction do
      # Set up base pricing
      # Configure variations
      # Set up packages
      # Initialize rules
    end
  end
  
  def self.calculate_service_price(service, options)
    # Get base price
    # Apply variations
    # Handle packages
    # Return total
  end
end

class PriceVariationService
  def self.apply_variations(base_price, selected_variations)
    # Calculate adjustments
    # Apply dependencies
    # Handle conflicts
    # Return final price
  end
  
  def self.validate_combinations(variations)
    # Check compatibility
    # Validate rules
    # Return validation
  end
end
```

### Background Jobs
```ruby
class ServicePriceUpdateJob < ApplicationJob
  def perform(service_id)
    # Update base prices
    # Recalculate variations
    # Update packages
    # Send notifications
  end
end

class PackagePriceCalculationJob < ApplicationJob
  def perform(package_id)
    # Calculate package prices
    # Apply discounts
    # Update cache
    # Log changes
  end
end
```

## Views
1. Service Price Configuration
   - Base price setup
   - Variation management
   - Package builder
   - Rule configuration

2. Price Management
   - Bulk updates
   - Package management
   - Variation editor
   - Preview calculator

## API Endpoints
```ruby
# GET /api/v1/services/:id/pricing
{
  "include_variations": boolean,
  "include_packages": boolean
}

# POST /api/v1/services/:id/calculate_price
{
  "variations": ["uuid"],
  "package_id": "uuid",
  "options": {}
}
```

## Testing Strategy
1. Model Tests
   - Price configuration
   - Variation handling
   - Package management
   - Rule validation

2. Service Tests
   - Price calculation
   - Variation application
   - Package pricing
   - Rule processing

3. Integration Tests
   - Complete pricing flow
   - Package management
   - API functionality
   - Cache behavior

## Security Considerations
- Price validation
- Rule authorization
- Package access control
- Rate limiting
- Audit logging
- Data integrity

## Estimated Hours: 24

## Dependencies
- Pricing Engine
- Service Catalog
