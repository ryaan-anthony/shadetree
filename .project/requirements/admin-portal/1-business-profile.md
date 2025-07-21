# Epic: Business Profile Management

## Overview
Enable users to create, configure, and manage multiple business entities within the Shadetree platform. This epic covers everything from initial business setup to ongoing profile management and multi-business operations for users who operate multiple service companies.

## Goals
- Enable quick business creation and onboarding
- Support multi-business management for entrepreneurs and franchises
- Provide comprehensive business configuration options
- Ensure proper data isolation between businesses
- Create scalable business context switching

## Success Metrics
- Business setup completion time < 10 minutes
- Multi-business adoption rate > 25% of active users
- Business profile completeness rate > 90%
- Cross-business data leakage incidents = 0
- Business switching time < 2 seconds

## User Stories
- As an entrepreneur, I want to create multiple business profiles so I can manage different service companies
- As a business owner, I want to configure my business details so customers see professional information
- As a franchise owner, I want to manage multiple locations with separate configurations
- As a user, I want to easily switch between my businesses without losing context
- As a business owner, I want to maintain separate staff, services, and customers for each business

## Features

### 1. [Business Creation & Setup](business-profile/01-business-creation.md)
Initial business creation workflow with guided setup process.

### 2. [Business Configuration](business-profile/02-business-configuration.md)
Comprehensive business profile management including contact details, branding, and operational settings.

### 3. [Business Hours & Service Areas](business-profile/03-business-hours-areas.md)
Configure operating hours, service territories, and availability calendars.

### 4. [Business Branding & Customization](business-profile/04-business-branding.md)
Logo upload, color schemes, and custom branding elements for quotes and customer-facing materials.

### 5. [Multi-Business Management](business-profile/05-multi-business-management.md)
Core functionality for users to create, manage, and switch between multiple business entities.

## Technical Architecture

### Core Models
- `Business` - Main business entity with profile information
- `BusinessOwnership` - Join model connecting users to businesses with roles
- `User` - Extended to support multiple business relationships

### Business Context
All admin functionality must be scoped to the current business context to ensure proper data isolation and security.

### Data Isolation Strategy
- Business-scoped queries for all domain objects
- Session-based business context switching
- Role-based access control within each business
- Audit logging for cross-business operations

## Integration Points
- Staff Management (business-scoped teams)
- Service & Pricing (business-specific catalogs)
- Customer Management (separate customer bases)
- Quote Generation (business-branded templates)
- Dashboard Analytics (business-specific metrics)

## Security Considerations
- Prevent cross-business data access
- Validate business ownership on all operations
- Audit business creation and deletion events
- Secure business switching with proper authorization

## Phase 1 (MVP)
- Single business creation and configuration
- Basic profile management
- Essential business settings

## Phase 2 (Multi-Business)
- Multiple business support
- Business context switching
- Advanced role management
- Business-specific customization

## Out of Scope
- Business-to-business relationships
- Complex organizational hierarchies
- Advanced workflow automation
- Third-party business verification
