# Core Requirements - Shadetree Platform

## Overview
Shadetree is a lightweight, Rails-based service booking platform that helps small businesses manage quotes and appointments. Built with Ruby on Rails conventions and minimal JavaScript, focusing on server-rendered pages enhanced with Hotwire for real-time features.

## Core Initiatives

### 1. [Core Booking Platform](tickets/01-core-booking-platform.md)
Server-rendered Rails application handling core business logic.

#### Key Features
- User Management
- Appointment Management
- Quote Generation
- Notification System

#### Additional Features
- Audit Logs

### 2. [Marketing Website](tickets/02-marketing-website.md)
Rails-rendered marketing pages with minimal dynamic features.

#### Key Features
- Landing Page
- Pricing Information
- Feature Showcase
- Contact Form
- Testimonials

#### Additional Features
- SEO Optimization
- Analytics Integration

### 3. [Admin Portal](tickets/03-admin-portal.md)
Centralized administration interface for business management.

#### Key Features
- Dashboard Overview
- Business Metrics
- System Status
- Activity Monitoring
- User Management
- Integration Management
- Audit Logs
- Support Tools
- Reporting Tools
- Workflow Configuration
- Custom Field Management
- Notification Rules
- Service Templates
- Workflow Builder
- Approval Chains
- Service-Specific Workflows
- Workflow Validation

#### Additional Features
- Customizable Dashboards
- Real-time Updates

### 4. SaaS Owner Backend
Lightweight admin interface for managing business customers.

#### Key Features
- Customer Management
- Feature Toggles

#### Additional Features
- Basic Reporting

## Core Technologies

### Backend
- Ruby on Rails 8.0
- PostgreSQL
- Redis
- Sidekiq
- Action Cable

### Frontend
- Hotwire (Turbo + Stimulus)
- TailwindCSS
- ViewComponent
- Minimal vanilla JavaScript

## Security Approach
- Rails security best practices
- Devise + Pundit
- Strong Parameters
- Security audit gems
- Regular updates
- Basic audit logs

## Performance Strategy
- Server-side rendering
- Fragment caching
- Background jobs
- Query optimization
- Asset pipeline

## Testing Requirements
- RSpec for all layers
- System tests with Capybara
- Factory Bot fixtures
- Faker test data
- SimpleCov coverage

## Development Process
- Standard Rails patterns
- GitHub Flow
- Pull requests
- Continuous Integration
- Documented code

## Monitoring Plan
- Standard Rails logging
- Exception tracking
- Basic metrics
- Queue monitoring
- Server health

## Success Metrics
1. Core Platform
    - Fast response times
    - High test coverage
    - Clean code quality
    - Minimal dependencies

2. Marketing Site
    - Quick page loads
    - Good SEO scores
    - Easy maintenance
    - Clear analytics

3. Admin Portal
    - Simple operations
    - Clear audit trail
    - Fast reporting
    - Easy navigation

4. SaaS Backend
    - Key metrics tracked
    - Simple operations
    - Clear reporting
    - Low maintenance
