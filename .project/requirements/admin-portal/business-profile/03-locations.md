# Feature: Location & Service Areas

## Overview
Location & Service Areas management enables businesses to define their physical locations and service delivery territories. This includes headquarters configuration, multiple location support for businesses with branches, and service area mapping that affects booking availability and pricing calculations.

## User Stories
- As a business owner, I want to set my primary business location so customers can find me and GPS systems work correctly
- As a business owner, I want to define my service areas so customers know where I can provide services
- As a business owner, I want to manage multiple locations so I can coordinate services across different sites

## Tasks

### 1. Primary Location Setup
Create interface for configuring the main business address and location details.

**Implementation Notes:**
- Add Location model with address, city, state, zip, latitude, longitude fields
- Create locations controller with geocoding integration
- Build location form with address validation and map preview
- Implement Google Maps API integration for location verification
- Add location display on customer-facing pages

### 2. Service Area Configuration
Implement service territory mapping to define where business can deliver services.

**Implementation Notes:**
- Add ServiceArea model with business_id, area_type, radius
- Build radius-based service area configuration (distance from location)
- Add service area validation for booking requests

### 3. Multiple Location Management
Provide capability for businesses to manage multiple physical locations or service points.

**Implementation Notes:**
- Add is_primary flag to Location model for main location identification
- Create locations index view with location listing and management
- Build location assignment system for staff and services
- Implement location-specific operating hours and availability
- Add location selection in booking and scheduling workflows
