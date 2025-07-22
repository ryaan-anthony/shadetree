# Feature: Business Branding

## Overview
Business Branding enables business owners to customize their visual identity across all customer-facing interfaces for each location. This includes location-specific logo management, color scheme customization, and branding elements that create a consistent professional appearance in quotes, booking pages, and communications while allowing for location-specific variations.

## User Stories
- As a business owner, I want to upload logos for each location so customers recognize the appropriate brand for their local service
- As a business owner, I want to customize colors and styling per location so my booking pages match location-specific brand identity
- As a business owner, I want to inherit branding from my primary location but customize it for specific locations as needed
- As a business owner, I want to preview how location-specific branding appears so I can ensure consistency

## Tasks

### 1. Location-Specific Logo and Image Management
Create interface for uploading and managing logos and branding images per location with inheritance options.

**Implementation Notes:**
- Add LocationBranding model with location_id, logo_url, favicon_url, inherit_from_primary fields
- Create location_branding controller with location-scoped image upload and management actions
- Build file upload interface with location selector, image preview and cropping tools
- Implement image optimization and multiple size generation per location
- Add logo inheritance toggle with fallback to primary location branding
- Include location context in customer-facing pages and documents

### 2. Location-Specific Color Scheme Customization
Implement brand color configuration that applies per location across customer interfaces.

**Implementation Notes:**
- Add primary_color, secondary_color, accent_color fields to LocationBranding model
- Create location-scoped color picker interface with preset color palettes
- Build CSS variable generation system for location-specific dynamic theming
- Implement color contrast validation for accessibility compliance per location
- Add color inheritance from primary location with override capabilities
- Include location-based color preview across different interface elements

### 3. Location-Specific Brand Preview and Application
Provide preview functionality to see how location branding appears across different customer touchpoints.

**Implementation Notes:**
- Create location_branding preview controller with location-scoped sample page generation
- Build preview interface showing location-specific quotes, booking pages, and emails
- Implement real-time brand updates with Hotwire integration per location
- Add brand reset functionality to restore primary location styling
- Include location-based brand export functionality for external marketing materials
- Add brand consistency validation across locations with conflict detection
