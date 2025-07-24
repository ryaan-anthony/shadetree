# Feature: Customer Dashboard

## Overview
Provide a centralized dashboard view showing all business customers with key metrics, status indicators, and quick access to customer details for platform administrators.

## User Stories
- As a platform administrator, I want to see all customers at a glance so I can monitor overall platform health
- As a support specialist, I want to quickly identify customer status so I can prioritize support requests
- As a business analyst, I want to see customer metrics so I can understand platform usage patterns

## Tasks

### 1. Create Customer Dashboard Controller and Routes
Create the main dashboard controller to handle customer overview displays.
#### Implementation Notes:
- Add route `GET /admin/customers` to `config/routes.rb`
- Create `Admin::CustomersController` with `index` action
- Implement pagination for large customer lists
- Add filtering capabilities (active, inactive, trial, etc.)
- Implement search functionality by company name or email

### 2. Build Customer Model and Database Schema
Define the core Customer model with necessary attributes and relationships.
#### Implementation Notes:
- Create `Customer` model with fields: name, email, company, status, created_at, plan_type
- Add database migration for customers table
- Include status enum (active, inactive, trial, suspended)
- Add validation for required fields and email format
- Create indexes on frequently queried fields (status, created_at)

### 3. Design Dashboard View Template
Create the main dashboard interface showing customer overview and metrics.
#### Implementation Notes:
- Create `app/views/admin/customers/index.html.erb`
- Implement metric cards showing total customers, active customers, trials
- Build customer table with sortable columns
- Add status badges using design system colors
- Include search bar and status filters
- Implement responsive design for mobile/tablet viewing

### 4. Add Customer Metrics Calculation
Implement business logic to calculate and display key customer metrics.
#### Implementation Notes:
- Create service class `CustomerMetricsService` for metric calculations
- Calculate total customers, active customers, trial conversions
- Add monthly/weekly growth indicators
- Implement caching for expensive metric calculations
- Create background job to refresh metrics periodically

### 5. Implement Customer Status Management
Allow administrators to view and update customer status from the dashboard.
#### Implementation Notes:
- Add status update actions to `Admin::CustomersController`
- Create partial views for status change forms
- Implement AJAX updates for status changes
- Add confirmation dialogs for status changes
- Log all status changes for audit trail
