# Feature: Location & Service Areas

## Overview
Location & Service Areas management enables businesses to define their physical locations and service delivery territories. This includes headquarters configuration, multiple location support for businesses with branches, and location-specific service area mapping that affects booking availability and pricing calculations.

## User Stories
- As a business owner, I want to set my primary business location so customers can find me and GPS systems work correctly
- As a business owner, I want to define service areas for each location so customers know where I can provide services from that specific location
- As a business owner, I want to exclude specific cities or states from my service area so I can avoid areas I don't serve
- As a business owner, I want to manage multiple locations so I can coordinate services across different sites

## Tasks

### 1. Primary Location Setup
Create interface for configuring the main business address and location details.

**Implementation Notes:**
- Add Location model with address, city, state, zip, latitude, longitude, is_primary fields
- Create locations controller with geocoding integration
- Build location form with address validation and map preview
- Implement Google Maps API integration for location verification
- Add location display on customer-facing pages

### 2. Location-Specific Service Area Configuration
Implement service territory mapping per location to define where business can deliver services from each location.

**Implementation Notes:**
- Add ServiceArea model with location_id, area_type, radius, polygon_data fields
- Create service_areas controller with location-scoped routes and actions
- Build radius-based service area configuration (distance from specific location)
- Implement custom polygon drawing for irregular service areas per location
- Add service area validation for booking requests against location-specific areas
- Include location context in service area management interface

### 3. Service Area Restrictions and Disallow Lists
Provide capability to exclude specific geographic areas from service coverage despite being within the defined radius or polygon.

**Implementation Notes:**
- Add ServiceAreaRestriction model with service_area_id, restriction_type, city, state, zip_code fields
- Create restrictions interface within service area configuration
- Build city/state/zip exclusion form with autocomplete functionality
- Implement restriction validation during booking address verification
- Add bulk restriction import for common exclusion patterns
- Include visual indicators on map showing excluded areas within service boundaries

### 4. Multiple Location Management
Provide capability for businesses to manage multiple physical locations or service points with independent service areas.

**Implementation Notes:**
- Create locations index view with location listing and service area summaries
- Build location assignment system for staff and services
- Implement location-specific service area inheritance and overrides
- Add location selection in booking workflows with service area validation
- Include service area overlap detection and conflict resolution between locations
