# Feature: Custom Service Selection

## Overview
Implement a flexible service selection component within the quote request form that allows businesses to define their service offerings and enables customers to select specific services they're interested in when requesting a quote.

## Goals
- Allow businesses to create a catalog of services with descriptions and pricing options
- Enable hierarchical service categorization for businesses with diverse offerings
- Provide an intuitive service selection interface for customers
- Support conditional form fields based on service selection
- Enable service-specific questions and requirements

## User Stories
1. **As a business owner**, I want to define my service offerings so customers can select exactly what they need.
2. **As a business owner**, I want to organize my services into categories for easier navigation.
3. **As a business owner**, I want to show different form fields based on the selected service.
4. **As a customer**, I want to easily find and select the services I'm interested in.
5. **As a customer**, I want to see basic pricing information before submitting my quote request.

## Technical Requirements

### Service Catalog Management
- CRUD interface for service offerings
- Support for service categories and subcategories
- Service attributes:
  - Name
  - Description
  - Base pricing (optional)
  - Estimated duration (optional)
  - Required information fields
  - Image/icon (optional)

### Customer Service Selection Component
- Visual service category navigation
- Search functionality for services
- Service cards with key information
- Multiple selection for related services
- Quantity selectors where applicable

### Conditional Form Logic
- Dynamic form field display based on selected services
- Service-specific required fields
- Contextual help text for different service selections
- Custom validation rules per service

### Pricing Preview (Optional)
- Basic pricing estimates based on selections
- Range pricing for variable-scope work
- Disclaimers for estimate-only pricing
- Customizable pricing display options

## User Flows

### Business Owner Service Configuration Flow
1. Access service catalog in admin portal
2. Create/edit service categories
3. Add/edit services within categories
4. Define required information per service
5. Set pricing information (if applicable)
6. Configure any service-specific form fields
7. Preview service selection interface

### Customer Service Selection Flow
1. Access quote request form
2. Browse service categories or search for services
3. Select desired service(s)
4. Specify quantity/scope if applicable
5. View any service-specific form fields
6. Complete remaining quote request information
7. Submit request with selected services

## Success Criteria
- Service selection completion rate >70%
- Service categorization reducing selection time by >25%
- Business owners able to configure services without technical support
- Customers selecting correct services (reduced clarification requests)
- Improved quote accuracy based on service-specific information

## Dependencies
- Service catalog database schema
- Dynamic form field component
- Pricing calculation engine (if implemented)

## Implementation Notes
- Use nested attributes for service-specific form fields
- Implement lazy loading for service categories with many items
- Consider using Stimulus controllers for interactive service selection
- Cache service catalog for performance
- Implement versioning for services to handle updates without breaking existing quotes
