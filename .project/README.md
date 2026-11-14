> **Superseded (Nov 2026).** The current plan lives in [`docs/`](../docs/README.md). This folder is kept for reference only. Technical decisions in [`docs/adr`](../docs/adr/README.md) override anything here.

# Core Requirements - Shadetree Platform

## Overview
Shadetree is a lightweight, service booking platform that helps small businesses manage quotes and appointments. Built with Ruby on Rails conventions and minimal JavaScript, focusing on server-rendered pages enhanced with Hotwire for real-time features.

## Business Model
- Subscription SaaS with tiered pricing based on usage metrics
- Plans ranging from Free to $99/month based on quotes/jobs processed
- Optional add-ons for additional features

## Core Initiatives

### 1. [Marketing Website](requirements/01-marketing-website.md)
Static pages with minimal dynamic features. Ability to register/login to the admin portal for business management.

#### Key Features
- Landing Page
- Pricing Information
- Feature Showcase
- Industry-Specific Solutions
- Contact Form
- Testimonials
- Free Trial Signup

### 2. [Admin Portal](requirements/02-admin-portal.md)
Centralized administration interface for business management. Users may have multiple businesses.

#### Key Features
- Staff Availability Settings (schedule & availability per employee)
- Company Profile (logo, timezone, contact info)
- User Management (invite/remove team members, set roles)
- Workflow Builder (define custom flows: quote → schedule → invoice)
- Service Templates (define standard services, durations, pricing)
- Notification Rules (email/SMS triggers for clients & staff)
- Support Access (open support tickets or chat)
- Export Data (CSV/PDF for quotes, jobs, contacts)
- Business Metrics (quotes sent, jobs scheduled, payments received)- Audit Logs (who changed what and when)
- Activity Monitoring (basic logging, email/SMS status, quote views)
- Activity Feed (recent quotes, appointments, invoices)

### 3. [Customer-Facing Interface](requirements/03-customer-facing.md)
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

### 4. [SaaS Owner Backend](requirements/04-saas-owner-backend.md)
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
