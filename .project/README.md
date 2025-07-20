# Core Requirements - Shadetree Platform

## Overview
Shadetree is a lightweight, Rails-based service booking platform that helps small businesses manage quotes and appointments. Built with Ruby on Rails conventions and minimal JavaScript, focusing on server-rendered pages enhanced with Hotwire for real-time features.

## Core Initiatives

### 1. [Core Booking Platform](tickets/01-core-booking-platform.md)
Server-rendered Rails application handling core business logic.

#### Key Components
- **User Management**
    - Devise-based authentication
    - Pundit for authorization
    - Multi-tenancy through account scope
    - Simple role system (owner, staff, customer)

- **Appointment Management**
    - Server-rendered calendar views
    - Turbo Frame-based updates
    - iCal feed integration
    - Email/SMS notifications via Action Mailer/Noticed

- **Quote Generation**
    - PDF generation with Prawn
    - Template system using ViewComponent
    - Turbo Stream updates for real-time status
    - Email delivery with attachments

- **Service Configuration**
    - Database-backed configuration
    - Simple admin interface
    - Cached settings with Redis
    - Audit logging with Paper Trail

### 2. [Marketing Website](tickets/02-marketing-website.md)
Rails-rendered marketing pages with minimal dynamic features.

#### Key Features
- Server-rendered pages with ERB/TailwindCSS
- Turbo Frame contact forms
- Simple pricing calculator
- Blog using basic Rails models
- SEO-optimized meta tags

### 3. [Admin Portal](tickets/03-admin-portal.md)
Centralized administration interface for business management.

#### Features
- Rails-native admin interface
- ViewComponent-based UI
- Turbo Frame inline editing
- CSV exports via Sidekiq
- Simple charts with Chartkick

### 4. SaaS Owner Backend
Lightweight admin namespace within main Rails app.

#### Features
- **Customer Management**
    - ActiveRecord analytics
    - Usage tracking via Redis
    - Simple CRM features
    - Account health monitoring

- **Support Tools**
    - Rails-based user impersonation
    - Paper Trail audit logs
    - Basic ticket management
    - Knowledge base with ViewComponent

- **Business Metrics**
    - Server-rendered dashboards
    - Chartkick visualizations
    - Sidekiq-processed exports
    - Redis-cached metrics

- **Platform Control**
    - Flipper feature flags
    - Simple A/B testing
    - Plan management via Postgres
    - Redis usage tracking

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

### Infrastructure
- Docker containers
- Kamal deployment
- Basic AWS (S3, SES)
- Simple monitoring

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

## Scalability Requirements
- Vertical scaling focus
- Basic horizontal when needed
- Database optimization
- Background job queues
- CDN for assets

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

## Timeline
- Phase 1: Core Platform (8 weeks)
- Phase 2: Marketing Site (2 weeks)
- Phase 3: Admin Portal (4 weeks)
- Phase 4: SaaS Backend (2 weeks)
- Total Duration: 16 weeks
