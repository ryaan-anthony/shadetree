# Feature: Pricing Structure Configuration

## Overview
Pricing Structure Configuration enables business owners to set base prices, create pricing tiers, and implement flexible pricing rules. This includes location-based pricing, service-specific rates, tax calculations, and additional fees that can be configured per service.

## User Stories
- As a business owner, I want to set base prices for my services so customers know what to expect
- As a business owner, I want different pricing for different locations so I can account for varying costs
- As a business owner, I want to offer different price tiers so I can serve various customer segments
- As a business owner, I want to configure taxes per service so I can comply with local tax requirements
- As a business owner, I want to add fees to services so I can account for additional costs

## Tasks

### 1. Base Price Management
Create interface for setting and managing fundamental service pricing across the business.

**Implementation Notes:**
- Add ServicePrice model with service_id, location_id, base_price, currency fields
- Create service_prices controller with location-scoped pricing management
- Build pricing form with currency selection and price validation
- Implement price inheritance from primary location with override capabilities
- Add bulk pricing updates and import functionality

### 2. Tax Configuration and Calculation
Implement configurable tax rates and calculations for individual services.

**Implementation Notes:**
- Add ServiceTax model with service_id, tax_name, tax_rate, tax_type, is_inclusive fields
- Create service tax configuration interface within pricing management
- Build tax calculation engine for quotes and invoices with inclusive/exclusive options
- Implement location-based tax overrides for multi-location businesses
- Add tax exemption handling and special tax status configuration

### 3. Fee Management
Provide system for adding configurable fees to services beyond base pricing.

**Implementation Notes:**
- Add ServiceFee model with service_id, fee_name, fee_amount, fee_type, is_mandatory fields
- Create fee configuration interface with percentage and fixed amount options
- Build fee application logic for booking calculations and customer display
- Implement conditional fees based on service parameters or customer selections
- Add fee transparency display for customer-facing pricing

### 4. Pricing Tiers and Variations
Implement tiered pricing system for different service levels and customer segments.

**Implementation Notes:**
- Add PricingTier model with service_id, tier_name, price_multiplier, description fields
- Create pricing tiers interface within service configuration
- Build tier selection system for customer booking process
- Implement tier-based pricing calculations including taxes and fees
- Add tier management tools with complete pricing preview functionality

### 5. Location-Based Pricing
Provide capability for different pricing structures across multiple business locations.

**Implementation Notes:**
- Extend ServicePrice model with location-specific pricing rules, taxes, and fees
- Create location pricing comparison interface showing total cost including taxes/fees
- Build location-based pricing display for customer-facing pages with tax transparency
- Implement pricing synchronization tools across locations with tax/fee considerations
- Add comprehensive location pricing reports including tax and fee breakdowns
