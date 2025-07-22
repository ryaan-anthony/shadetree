# Feature: Basic Business Information

## Overview
Basic Business Information allows business owners to configure core company details that customers see and that affect system operations. This includes business name, description, contact information, and essential settings that drive customer interactions and internal workflows.

## User Stories
- As a business owner, I want to update my business name and description so customers understand what services I provide
- As a business owner, I want to manage my contact information so customers can reach me through their preferred method
- As a business owner, I want to set my timezone so appointments and communications are scheduled correctly

## Tasks

### 1. Business Details Form
Create interface for managing core business information including name, description, and industry type.

**Implementation Notes:**
- Add Business model with name, description, industry, timezone fields
- Create admin/businesses controller with show/edit actions
- Build form partial with validation feedback
- Include industry selection dropdown with predefined options
- Add timezone selector with common business timezones

### 2. Contact Information Management
Implement contact details configuration including phone, email, and address fields.

**Implementation Notes:**
- Add contact fields to Business model (phone, email, address, city, state, zip)
- Create contact_info form section with proper input types
- Implement phone number formatting and validation
- Add email validation with domain verification

### 3. Business Settings Configuration
Provide essential operational settings that affect customer experience and system behavior.

**Implementation Notes:**
- Add settings fields to Business model (currency, tax_rate, booking_lead_time)
- Create settings form section with appropriate input controls
- Implement currency selection with common business currencies
- Add tax rate input with percentage validation
- Include booking lead time configuration (minimum hours/days)
