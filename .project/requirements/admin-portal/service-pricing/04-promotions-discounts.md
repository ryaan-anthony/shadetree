# Feature: Promotions & Discounts

## Overview
Promotions & Discounts enables business owners to create marketing campaigns, discount codes, and special pricing events to attract customers and increase bookings during slow periods.

## User Stories
- As a business owner, I want to create discount codes so I can offer special pricing to targeted customers
- As a business owner, I want to run seasonal promotions so I can boost bookings during slow periods
- As a customer, I want to apply discount codes so I can save money on services

## Tasks

### 1. Discount Code Management
Create system for generating and managing promotional discount codes with usage tracking.

**Implementation Notes:**
- Add DiscountCode model with code, discount_type, discount_value, expiry_date, usage_limit fields
- Create discount_codes controller with code generation and validation
- Build discount creation form with code customization and restrictions
- Implement discount code validation during booking process
- Add usage tracking and reporting for promotional effectiveness

### 2. Promotional Campaign Management
Implement campaign system for organizing and managing marketing promotions across services.

**Implementation Notes:**
- Add PromotionalCampaign model with name, start_date, end_date, target_services fields
- Create campaigns controller with campaign lifecycle management
- Build campaign creation interface with service selection and scheduling
- Implement campaign activation and deactivation workflows
- Add campaign performance tracking and analytics

### 3. Automatic Promotion Application
Provide system for automatically applying eligible promotions based on customer behavior and booking patterns.

**Implementation Notes:**
- Add promotion eligibility logic for automatic discount application
- Create promotion suggestion system for customer booking flow
- Build promotion display interface showing available discounts
- Implement promotion conflict resolution for multiple eligible discounts
- Add promotion notification system for customers and staff
