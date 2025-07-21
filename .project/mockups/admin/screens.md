# Admin Portal Screen Inventory - Phase-Aligned

This document lists all screens needed to complete the Admin Portal initiative, organized by development phases. Each screen will have a corresponding HTML mockup aligned with our MVP-first approach.

## Overview
The Admin Portal provides business owners with comprehensive tools to manage their service operations. The interface emphasizes ease of use for non-technical users while maintaining enterprise-grade functionality. Screens are prioritized for MVP delivery with growth features planned for later phases.

## Phase-Based Screen Categories

### MVP Phase (P0/P1) - Weeks 1-4
Essential screens for basic business operations and quote-to-payment workflow.

### Growth Phase (P2) - Weeks 5-8
Advanced features for business optimization and automation.

### Scale Phase (P3) - Weeks 9-12
Enterprise features for compliance, monitoring, and support.

---

## MVP Phase Screens (P0/P1)

### 1. Dashboard & Navigation (P0)
Central hub for accessing all admin functions with essential business insights.

#### Main Admin Dashboard
- **Description**: Primary landing page showing essential business metrics, quick actions, and recent activity
- **Key Elements**:
  - Business name and user info header
  - Core metrics cards (quotes sent this month, revenue this month, appointments this week)
  - Quick action buttons (New Quote, View Calendar)
  - Recent activity feed (last 5 quotes, upcoming appointments)
  - Simplified navigation sidebar for MVP features only
- **Phase**: MVP (P0)
- **User Journey**: Entry point after login, central navigation hub
- **Mockup**: [Admin Dashboard - MVP](admin-dashboard.html)

### 2. Business Profile Management (P0)

#### Business Creation & Setup
- **Description**: Guided business setup process for new users
- **Key Elements**:
  - Multi-step setup wizard (basic info → services → complete)
  - Progress indicator
  - Business name, email, phone (required fields only)
  - Business type selection
  - Basic address information
  - Skip option for non-essential fields
- **Phase**: MVP (P0)
- **User Journey**: First-time user onboarding
- **Mockup**: [Business Setup](business-creation-setup.html)

#### Company Information (P0)
- **Description**: Essential business details configuration
- **Key Elements**:
  - Business name and description
  - Contact details (email, phone, address)
  - Timezone selection
  - Basic business hours (simplified grid)
  - Save/cancel actions
- **Phase**: MVP (P0)
- **User Journey**: Essential setup for business operations
- **Mockup**: [Company Info - MVP](business-company-info.html)

#### Business Hours & Service Areas (P0)
- **Description**: Configure basic operating hours and service coverage
- **Key Elements**:
  - Simplified weekly schedule (open/closed per day)
  - Basic time picker for business hours
  - Simple service area definition (ZIP codes only)
  - Customer-facing hours preview
- **Phase**: MVP (P0)
- **User Journey**: Essential for appointment scheduling
- **Mockup**: [Hours & Areas - MVP](business-hours-areas.html)

### 3. Staff Management (P0)

#### Staff Invitations & Overview
- **Description**: Basic team member management with simple invitation system
- **Key Elements**:
  - Active staff list with roles (Owner, Admin, Staff only)
  - Simple invite form (email + role selection)
  - Pending invitation status
  - Basic staff actions (remove, resend invitation)
  - Team count summary
- **Phase**: MVP (P0)
- **User Journey**: Essential team setup
- **Mockup**: [Staff Overview - MVP](staff-overview.html)

#### Basic Roles & Permissions
- **Description**: Simplified role system with clear permissions
- **Key Elements**:
  - Three role types only (Owner, Admin, Staff)
  - Permission comparison table
  - Role assignment interface
  - Clear permission descriptions
- **Phase**: MVP (P0)
- **User Journey**: Secure team access control
- **Mockup**: [Staff Roles - MVP](staff-roles.html)

### 4. Service & Pricing Setup (P0)

#### Service Catalog Management
- **Description**: Core service creation and management
- **Key Elements**:
  - Service list with essential details
  - Add/edit service form (name, description, base price)
  - Three pricing types (Fixed, Hourly, Custom)
  - Active/inactive toggle
  - Search and basic filtering
- **Phase**: MVP (P0)
- **User Journey**: Essential for quote generation
- **Mockup**: [Service Catalog - MVP](services-catalog.html)

#### Basic Pricing Configuration
- **Description**: Simple pricing setup for services
- **Key Elements**:
  - Service selection
  - Pricing type selector (Fixed/Hourly/Custom)
  - Base price input
  - Price preview calculator
  - Save/cancel actions
- **Phase**: MVP (P0)
- **User Journey**: Essential for accurate quotes
- **Mockup**: [Pricing Config - MVP](pricing-rules.html)

### 5. Custom Fields (P1)

#### Quote Form Custom Fields
- **Description**: Basic custom field management for quote forms
- **Key Elements**:
  - Field list with drag-and-drop ordering
  - Add field form (6 basic types: text, textarea, select, checkbox, date, number)
  - Field configuration (label, placeholder, required)
  - Form preview
  - Field usage analytics
- **Phase**: MVP (P1)
- **User Journey**: Customize quote forms for business needs
- **Mockup**: [Custom Fields - MVP](custom-fields.html)

### 6. Email Notifications (P1)

#### Basic Notification Rules
- **Description**: Simple email notification configuration
- **Key Elements**:
  - Notification rule list (6 core events)
  - Toggle switches for email notifications
  - Basic email template editor
  - Template preview
  - Test email functionality
- **Phase**: MVP (P1)
- **User Journey**: Automate client communication
- **Mockup**: [Notifications - MVP](notifications.html)

---

## Growth Phase Screens (P2)

### 7. Business Branding (P2)

#### Enhanced Business Customization
- **Description**: Logo upload and brand customization
- **Key Elements**:
  - Logo upload with preview
  - Brand color picker
  - Quote template preview with branding
  - Social media links
  - Website integration
- **Phase**: Growth (P2)
- **Mockup**: [Business Branding](business-branding.html)

### 8. Advanced Staff Features (P2)

#### Staff Availability Management
- **Description**: Detailed staff scheduling and availability
- **Key Elements**:
  - Weekly availability grid per staff member
  - Time-off request management
  - Team calendar view
  - Availability conflict warnings
- **Phase**: Growth (P2)
- **Mockup**: [Staff Availability](staff-availability.html)

### 9. Quote Templates (P2)

#### Professional Quote Templates
- **Description**: Customizable quote generation templates
- **Key Elements**:
  - Template gallery
  - Drag-and-drop template builder
  - Brand integration
  - Template preview and testing
- **Phase**: Growth (P2)
- **Mockup**: [Quote Templates](quote-templates.html)

### 10. Service Categories (P2)

#### Service Organization
- **Description**: Advanced service catalog organization
- **Key Elements**:
  - Category creation and management
  - Drag-and-drop service organization
  - Color coding
  - Category-based filtering
- **Phase**: Growth (P2)
- **Mockup**: [Service Categories](service-categories.html)

### 11. Workflow Builder (P2)

#### Process Automation
- **Description**: Visual workflow configuration for business processes
- **Key Elements**:
  - Drag-and-drop workflow designer
  - Trigger and action selection
  - Workflow templates
  - Execution monitoring
- **Phase**: Growth (P2)
- **Mockup**: [Workflow Builder](workflow-builder.html)

### 12. Reports & Analytics (P2)

#### Business Intelligence Dashboard
- **Description**: Comprehensive reporting and analytics
- **Key Elements**:
  - Revenue trends and charts
  - Quote conversion analytics
  - Job performance metrics
  - Export functionality
- **Phase**: Growth (P2)
- **Mockup**: [Reports Dashboard](reports-analytics.html)

### 13. Data Export (P2)

#### Export Management
- **Description**: Configurable data export capabilities
- **Key Elements**:
  - Export type selection
  - Date range and filtering
  - Format selection (CSV/PDF)
  - Export history and downloads
- **Phase**: Growth (P2)
- **Mockup**: [Data Export](data-export.html)

### 14. Integration Management (P2)

#### Third-Party Connections
- **Description**: Manage external service integrations
- **Key Elements**:
  - Integration status dashboard
  - Connection setup flows
  - Integration health monitoring
  - Configuration management
- **Phase**: Growth (P2)
- **Mockup**: [Integrations](integrations.html)

---

## Scale Phase Screens (P3)

### 15. Multi-Business Management (P3)

#### Business Switching & Management
- **Description**: Advanced multi-business operations
- **Key Elements**:
  - Business selector dropdown
  - Business creation wizard
  - Cross-business analytics
  - Business comparison views
- **Phase**: Scale (P3)
- **Mockup**: [Multi-Business](multi-business-management.html)

### 16. Staff Activity Tracking (P3)

#### Advanced Team Monitoring
- **Description**: Comprehensive staff activity and performance tracking
- **Key Elements**:
  - Activity timeline
  - Performance metrics
  - Team comparison analytics
  - Activity export and reporting
- **Phase**: Scale (P3)
- **Mockup**: [Staff Activity](staff-activity.html)

### 17. Audit & Activity Logs (P3)

#### Compliance & Monitoring
- **Description**: Comprehensive audit trail and activity monitoring
- **Key Elements**:
  - Change history tracking
  - User activity logs
  - Security event monitoring
  - Compliance reporting
- **Phase**: Scale (P3)
- **Mockup**: [Audit Logs](audit-logs.html)

### 18. Support Access (P3)

#### Integrated Support System
- **Description**: Help desk and support capabilities
- **Key Elements**:
  - Support ticket creation
  - Live chat interface
  - Knowledge base search
  - Support analytics
- **Phase**: Scale (P3)
- **Mockup**: [Support Portal](support-portal.html)

---

## Shared Components

### Navigation & Layout
- **Description**: Consistent navigation and layout elements
- **Key Elements**:
  - Responsive sidebar navigation
  - User menu and business selector
  - Breadcrumb navigation
  - Page header components
- **Mockup**: [Shared Navigation](shared-navigation.html)

### Modals & Forms
- **Description**: Reusable modal dialogs and form components
- **Key Elements**:
  - Confirmation dialogs
  - Form validation patterns
  - Loading states
  - Error handling
- **Mockup**: [Shared Modals](shared-modals.html)

---

## Implementation Notes

### MVP Phase Priority
Focus on essential business operations with simplified UX. Remove complex features that can be added in later phases.

### Growth Phase Enhancement
Add professional features that improve business efficiency and automation.

### Scale Phase Enterprise
Include compliance, monitoring, and advanced management features for larger operations.

### Design Consistency
All screens should maintain consistent design patterns, component usage, and user experience flows across phases.
