# Feature: Price Change Audit Trail

## Overview
Price Change Audit Trail maintains a simple history of all pricing-related modifications including service prices, promotions, discounts, packages, and pricing rules. This provides transparency and accountability for all pricing decisions.

## User Stories
- As a business owner, I want to see all pricing changes so I can track what was modified and when
- As a business owner, I want to know who made pricing changes so I can maintain accountability
- As a business owner, I want simple pricing history so I can understand my pricing decisions

## Tasks

### 1. Universal Pricing Change Logging
Create simple logging system that captures all pricing modifications across the platform.

**Implementation Notes:**
- Add PricingAuditLog model with item_type, item_id, field_changed, old_value, new_value, changed_by, changed_at fields
- Create audit logging for service prices, discount codes, promotional campaigns, packages, and add-ons
- Build automatic logging using Rails callbacks on pricing model updates
- Implement simple audit trail display showing chronological changes
- Add basic filtering by date range and change type

### 2. Change Tracking Display
Provide easy-to-read interface showing pricing change history.

**Implementation Notes:**
- Create pricing_audit controller with simple list and detail views
- Build audit log display with clear before/after values
- Implement change grouping by date and user for readability
- Add search functionality for specific services or time periods
- Include change reason field for optional staff notes

### 3. Basic Notifications
Send simple notifications when significant pricing changes occur.

**Implementation Notes:**
- Add email notifications for pricing changes above configurable thresholds
- Create daily/weekly pricing change summary emails for business owners
- Build simple notification preferences for different types of pricing changes
- Implement basic change alerts for discount code creation and expiration
- Add audit log export for record keeping and compliance
