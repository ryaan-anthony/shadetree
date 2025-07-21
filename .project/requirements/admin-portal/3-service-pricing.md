# Epic: Service & Pricing Setup

## Overview
Enable business owners to configure their service offerings, pricing structures, and basic quote templates efficiently.

## Objectives
- Create and manage service catalog
- Set up pricing tiers and options
- Configure basic quote templates
- Manage service categories and descriptions

## Features
1. [Service Catalog Management](service-pricing/01-service-catalog.md)
2. [Pricing Configuration](service-pricing/02-pricing-config.md)
3. [Quote Templates](service-pricing/03-quote-templates.md)
4. [Service Categories](service-pricing/04-service-categories.md)

## Technical Requirements
- CRUD operations for services
- Flexible pricing models (fixed, hourly, custom)
- Template system for quotes
- Category organization

## Acceptance Criteria
- Business owners can add/edit services quickly
- Pricing calculations work correctly in quotes
- Templates generate consistent quote formats
- Categories help organize service offerings
- Changes apply immediately to new quotes

## Dependencies
- Business Profile Management Epic

## Estimate
- Story Points: 13
- Timeline: 1 week

## Technical Notes
- Use Rails nested attributes for pricing tiers
- Implement template rendering with ERB
- Store pricing as decimal for accuracy
- Use Rails validations for data integrity
