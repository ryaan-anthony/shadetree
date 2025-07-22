# Feature: Add-ons & Upsells

## Overview
Add-ons & Upsells enables business owners to configure optional service additions and manual upselling opportunities that increase transaction value while providing customers with enhanced service options.

## User Stories
- As a business owner, I want to create service add-ons so customers can enhance their base service
- As a business owner, I want to configure upsell suggestions so I can increase my average transaction value
- As a customer, I want to see optional add-ons so I can customize my service experience
- As a staff member, I want to see upsell prompts so I can offer relevant additional services

## Tasks

### 1. Service Add-on Configuration
Create system for defining optional additions to base services with independent pricing.

**Implementation Notes:**
- Add ServiceAddon model with service_id, name, description, price, duration_adjustment fields
- Create service_addons controller with add-on management for each service
- Build add-on creation interface with pricing and duration configuration
- Implement add-on display in customer booking flow with checkboxes
- Add add-on inventory tracking if applicable

### 2. Manual Upsell Configuration
Implement simple upselling system where business owners define which services to suggest together.

**Implementation Notes:**
- Add UpsellSuggestion model with primary_service_id, suggested_service_id, display_text fields
- Create upsell management interface for configuring service relationships
- Build upsell display in booking flow showing related service options
- Implement upsell tracking for business performance analysis
- Add manual upsell prompts for staff during customer interactions

### 3. Cross-sell Service Relationships
Provide system for business owners to manually define complementary service relationships.

**Implementation Notes:**
- Add ServiceRelationship model with service_id, related_service_id, relationship_type fields
- Create relationship management interface for defining complementary services
- Build cross-sell display showing "customers also booked" style suggestions
- Implement cross-sell configuration with custom messaging per relationship
- Add cross-sell performance tracking for business optimization
