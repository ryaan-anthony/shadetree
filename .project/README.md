# Core Requirements - Shadetree Platform

## Overview
Shadetree is a lightweight, service booking platform that helps small businesses manage quotes and appointments. Built with Ruby on Rails conventions and minimal JavaScript, focusing on server-rendered pages enhanced with Hotwire for real-time features.

## Business Model
- Subscription SaaS with tiered pricing based on usage metrics
- Plans ranging from Free to $99/month based on quotes/jobs processed
- Optional add-ons for additional features

## Core Initiatives

### 1. [Core Booking Platform](requirements/01-core-booking-platform.md)
Server-rendered Rails application handling core business logic.

#### Key Features
- User Management (Business Owner, Staff, Customers)
- Appointment Management
- Quote Generation and Approval
- Payment Processing (Stripe/PayPal integration)
- Job Scheduling and Tracking
- Invoice Management
- Notification System (Email/SMS)

#### Additional Features
- Audit Logs
- White Label Interfaces
- Mobile-Responsive Design
- Offline Capability

### 2. [Marketing Website](requirements/02-marketing-website.md)
Rails-rendered marketing pages with minimal dynamic features.

#### Key Features
- Landing Page
- Pricing Information
- Feature Showcase
- Industry-Specific Solutions
- Contact Form
- Testimonials
- Free Trial Signup

#### Additional Features
- SEO Optimization
- Analytics Integration
- Blog/Content Marketing

### 3. [Admin Portal](requirements/03-admin-portal.md)
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

### 4. [Customer-Facing Interface](requirements/04-customer-facing.md)
Public-facing pages for end customers to interact with businesses.

#### Key Features
- Quote Request Forms
- Quote Review and Approval
- Appointment Self-Scheduling
- Payment Processing
- Digital Signature Collection
- Service History

#### Additional Features
- Customer Portal
- File Upload
- Feedback Collection

### 5. [SaaS Owner Backend](./requirements/05-saas-owner-backend.md)
Lightweight admin interface for managing business customers.

#### Key Features
- Customer Management
- Feature Toggles
- Subscription Management
- Usage Analytics
- Multi-tenant Administration

#### Additional Features
- Basic Reporting
- Billing Management
- Feature Flag Control

## End-to-End User Flow
1. **Initial Contact**: Client submits request through branded form
2. **Quote Creation**: Business creates and sends professional quote
3. **Approval**: Client approves quote with one click
4. **Scheduling**: Appointment is scheduled (by staff or client self-service)
5. **Job Execution**: Work is completed and documented
6. **Payment**: Invoice sent and payment collected online
7. **Follow-up**: Reviews requested, future service scheduled

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

### Integrations
- Stripe/PayPal for payments
- Twilio for SMS
- Google/Outlook Calendar
- Email providers

## Security Approach
- Rails security best practices
- Devise + Pundit
- Strong Parameters
- Security audit gems
- Regular updates
- Basic audit logs
- GDPR/CCPA compliance features

## Performance Strategy
- Server-side rendering
- Fragment caching
- Background jobs
- Query optimization
- Asset pipeline
- Progressive Web App capabilities

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
- User behavior analytics

## Success Metrics
1. Core Platform
    - Fast response times
    - High test coverage
    - Clean code quality
    - Minimal dependencies
    - Customer satisfaction

2. Marketing Site
    - Quick page loads
    - Good SEO scores
    - Easy maintenance
    - Clear analytics
    - Conversion rates

3. Admin Portal
    - Simple operations
    - Clear audit trail
    - Fast reporting
    - Easy navigation
    - Reduced training time

4. Customer Interface
    - High approval rate
    - Fast quote-to-job conversion
    - Positive customer feedback
    - Mobile usability

5. SaaS Backend
    - Key metrics tracked
    - Simple operations
    - Clear reporting
    - Low maintenance
    - Churn reduction

## Timeline & Roadmap
- **MVP Launch**: 6 months from kickoff
- **First Paying Customers**: 8 months
- **Product-Market Fit**: 12-18 months
- **Scale Phase**: 18-24 months

## Pricing Strategy
| Tier | Monthly Price | Features |
|------|--------------|----------|
| Free | $0 | 3 quotes/month, basic features |
| Starter | $15 | 15 quotes/month, basic features |
| Pro | $39 | 50 quotes/month, all core features |
| Team | $89 | 150 quotes/month, all features + priority support |
| Unlimited | $199 | Unlimited usage, all features, dedicated support |
