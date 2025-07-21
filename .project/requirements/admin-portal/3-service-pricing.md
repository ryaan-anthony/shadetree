# Epic: Service & Pricing Setup

## Overview
Enable business owners to configure their service offerings, pricing structures, and quote templates efficiently. Focus on essential service catalog management that directly supports quote generation and business operations.

## Goals
- Enable quick service catalog setup (< 15 minutes)
- Support flexible pricing models for diverse service types
- Provide professional quote template generation
- Ensure consistent pricing and service presentation
- Support business growth with scalable service management

## Success Metrics
- Service catalog setup completion time < 15 minutes
- Quote generation time < 3 minutes per quote
- Pricing calculation accuracy = 100%
- Service catalog completeness rate > 85%
- Quote template consistency score > 90%

## User Stories
- As a business owner, I want to create my service catalog so customers can see what I offer
- As a business owner, I want to set pricing for my services so quotes calculate automatically
- As a business owner, I want professional quote templates so my business looks established
- As a staff member, I want to quickly find services when creating quotes
- As a business owner, I want to organize services by category so they're easy to manage

## Features

### MVP Phase (P0 - Critical Path)
1. [Service Catalog Management](service-pricing/01-service-catalog.md) - Core CRUD operations for services
2. [Pricing Configuration](service-pricing/02-pricing-config.md) - Flexible pricing models and calculations

### Growth Phase (P1 - Early Value)
3. [Quote Templates](service-pricing/03-quote-templates.md) - Professional quote generation and customization
4. [Service Categories](service-pricing/04-service-categories.md) - Organization and management of service offerings

## Technical Architecture

### Core Models
```ruby
# MVP Models
class Service < ApplicationRecord
  belongs_to :business
  belongs_to :category, class_name: 'ServiceCategory', optional: true
  has_many :quote_line_items, dependent: :destroy
  
  validates :name, :pricing_type, presence: true
  validates :base_price, presence: true, numericality: { greater_than: 0 }
  
  enum pricing_type: { fixed: 0, hourly: 1, custom: 2 }
  enum status: { active: 0, inactive: 1 }
  
  scope :active, -> { where(status: 'active') }
  scope :by_category, ->(category) { where(category: category) }
end

class ServiceCategory < ApplicationRecord
  belongs_to :business
  has_many :services, dependent: :nullify
  
  validates :name, presence: true
  validates :name, uniqueness: { scope: :business_id }
end

# Growth Phase
class QuoteTemplate < ApplicationRecord
  belongs_to :business
  
  validates :name, :template_type, presence: true
  enum template_type: { standard: 0, detailed: 1, minimal: 2 }
end
```

### Pricing Calculation Engine
```ruby
# Simple pricing calculator for MVP
class PricingCalculator
  def self.calculate(service, quantity: 1, hours: nil, custom_rate: nil)
    case service.pricing_type
    when 'fixed'
      service.base_price * quantity
    when 'hourly'
      hours ? service.base_price * hours : service.base_price
    when 'custom'
      custom_rate || service.base_price
    end
  end
end
```

## Integration Points
- Business Profile (business-scoped service catalogs)
- Staff Management (service access permissions)
- Quote Generation (service selection and pricing)
- Admin Dashboard (service performance metrics)

## Security Considerations
- Validate business ownership for all service operations
- Ensure pricing calculations are accurate and secure
- Prevent unauthorized service modifications
- Audit pricing changes for business compliance

## MVP Scope Reduction
**Removed from MVP:**
- Complex pricing rules (bulk discounts, time-based pricing)
- Advanced template customization with drag-and-drop
- Service bundles or packages
- Service scheduling integration
- Multi-currency support

**Simplified for MVP:**
- Three basic pricing types (fixed, hourly, custom)
- Simple service CRUD operations
- Basic quote template rendering
- Essential service categorization

## Phase Progression
- **MVP**: Core service catalog and basic pricing
- **Growth**: Professional templates and advanced categorization  
- **Scale**: Complex pricing rules and service automation

## Dependencies
- Business Profile Management Epic
- Quote Generation System (from Core Booking Platform)

## Estimate
- MVP Features: 10 story points (1 week)
- Growth Features: 8 story points (1 week)
- Total: 18 story points (2 weeks)

## Technical Implementation Notes
- Use Rails money gem for accurate pricing calculations
- Implement service search with simple text matching
- Store templates as ERB for flexibility
- Use Rails validations for pricing integrity
- Cache frequently accessed services for performance
