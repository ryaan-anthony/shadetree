# Epic: Business Profile Management

## Overview
Enable business owners to set up and manage their core business information, contact details, and basic operational settings.

## Objectives
- Configure business information and contact details
- Set up service areas and operating hours
- Manage basic notification preferences
- Configure payment and invoicing settings

## Features
1. [Company Information Setup](business-profile/01-company-info.md)
2. [Operating Hours & Service Areas](business-profile/02-hours-areas.md)
3. [Notification Preferences](business-profile/03-notifications.md)
4. [Payment Settings](business-profile/04-payment-settings.md)

## Technical Requirements
- Simple form-based configuration
- Basic validation and data persistence
- File upload for logo/documents
- Timezone support
- Email template customization

## Acceptance Criteria
- Business owners can complete setup in under 10 minutes
- All information persists correctly
- Logo upload works properly
- Timezone settings affect all date/time displays
- Email templates use business branding

## Dependencies
- User Authentication System
- File Storage System

## Estimate
- Story Points: 13
- Timeline: 1 week

## Technical Notes
- Use Rails form objects for complex forms
- Implement image processing for logo uploads
- Cache business settings for performance
- Use Rails I18n for timezone handling
