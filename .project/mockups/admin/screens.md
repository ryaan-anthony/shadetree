# Admin Portal Screen Inventory

This document lists all screens needed to complete the Admin Portal initiative. Each screen will have a corresponding HTML mockup linked in this document.

## Overview
The Admin Portal provides business owners with comprehensive tools to manage their service operations, from business setup and staff management to service configuration and performance monitoring. The interface emphasizes ease of use for non-technical users while maintaining enterprise-grade functionality.

## Screen Categories

### 1. Dashboard & Navigation
Central hub for accessing all admin functions with key business insights.

### 2. Business Profile Management
Essential business setup and configuration screens.

### 3. Staff Management
Team member invitation, role assignment, and activity management.

### 4. Service & Pricing Setup
Service catalog, pricing configuration, and quote template management.

### 5. Shared Components
Reusable UI components used across multiple screens.

---

## 1. Dashboard & Navigation Screens

### Main Admin Dashboard
- **Description**: Primary landing page showing business overview, key metrics, quick actions, and recent activity
- **Key Elements**:
  - Welcome header with business name and user info
  - Business metrics cards (quotes, revenue, jobs, conversion rate)
  - Quick action buttons for common tasks
  - Recent activity timeline
  - System alerts and notifications
  - Navigation sidebar for all admin sections
- **User Journey**: Entry point after login, central navigation hub
- **Mockup**: [Admin Dashboard](admin-dashboard.html)

### Dashboard Metrics Detail
- **Description**: Expanded view of business performance metrics with charts and trends
- **Key Elements**:
  - Tabbed metric categories (Financial, Operational, Growth)
  - Interactive charts and graphs
  - Period selector (7 days, 30 days, 90 days)
  - Metric comparison tables
  - Export functionality
- **User Journey**: Accessed from dashboard metrics cards for deeper analysis
- **Mockup**: [Metrics Detail](dashboard-metrics.html)

---

## 2. Business Profile Management Screens

### Company Information Setup
- **Description**: Business details configuration including logo, contact info, and basic settings
- **Key Elements**:
  - Logo upload with preview
  - Business name, description, and contact details
  - Address information with validation
  - Timezone selection
  - Website and social media links
  - Save/cancel actions
- **User Journey**: First-time setup or ongoing profile management
- **Mockup**: [Company Setup](business-company-info.html)

### Operating Hours & Service Areas
- **Description**: Configure business hours and define service coverage areas
- **Key Elements**:
  - Weekly schedule grid with day-by-day configuration
  - Open/closed toggles for each day
  - Time picker inputs for start/end times
  - Service area definition (ZIP codes or radius)
  - Holiday schedule management
  - Preview of customer-facing hours display
- **User Journey**: Essential setup for scheduling and customer expectations
- **Mockup**: [Hours & Areas](business-hours-areas.html)

### Notification Preferences
- **Description**: Configure automated notifications and email templates
- **Key Elements**:
  - Notification type toggles (quotes, jobs, payments, etc.)
  - Delivery method selection (email, SMS, in-app)
  - Email template editor with variables
  - Template preview functionality
  - Default template restoration
  - Test email sending
- **User Journey**: Customize business communication preferences
- **Mockup**: [Notifications](business-notifications.html)

### Payment Settings
- **Description**: Configure payment methods, invoicing, and financial preferences
- **Key Elements**:
  - Payment method checkboxes (cash, check, credit card)
  - Tax rate configuration
  - Invoice numbering setup
  - Payment terms selection
  - Deposit requirements
  - Invoice footer customization
- **User Journey**: Essential for quote generation and payment processing
- **Mockup**: [Payment Settings](business-payment.html)

---

## 3. Staff Management Screens

### Staff Overview & Invitations
- **Description**: Team member management with invitation system
- **Key Elements**:
  - Active staff member list with roles
  - Pending invitation status
  - Invite new staff form with role selection
  - Staff member action menu (edit, remove, resend)
  - Role badge indicators
  - Team statistics summary
- **User Journey**: Manage team access and permissions
- **Mockup**: [Staff Management](staff-overview.html)

### Role & Permission Matrix
- **Description**: Detailed role configuration and permission management
- **Key Elements**:
  - Role comparison table
  - Permission categories (quotes, jobs, customers, etc.)
  - Visual permission matrix
  - Role editing interface
  - Permission descriptions and help text
  - Role assignment confirmation
- **User Journey**: Configure team member access levels
- **Mockup**: [Roles & Permissions](staff-roles.html)

### Staff Availability Management
- **Description**: Individual staff member availability and scheduling
- **Key Elements**:
  - Staff member selection dropdown
  - Weekly availability grid
  - Available/unavailable toggle per day
  - Time range selectors
  - Time-off request management
  - Team calendar view
  - Availability conflict warnings
- **User Journey**: Coordinate team schedules for optimal job assignment
- **Mockup**: [Staff Availability](staff-availability.html)

### Staff Activity Tracking
- **Description**: Monitor team performance and activity metrics
- **Key Elements**:
  - Staff member selection
  - Activity timeline for selected period
  - Performance metrics (quotes created, jobs completed)
  - Activity type filters
  - Export activity reports
  - Individual vs team comparison
- **User Journey**: Track productivity and manage team performance
- **Mockup**: [Activity Tracking](staff-activity.html)

---

## 4. Service & Pricing Setup Screens

### Service Catalog Management
- **Description**: Create and manage service offerings with categories
- **Key Elements**:
  - Service list with search and filters
  - Add/edit service form with pricing options
  - Service category organization
  - Bulk actions for multiple services
  - Active/inactive service toggle
  - Service usage statistics
  - Import/export functionality
- **User Journey**: Build and maintain comprehensive service catalog
- **Mockup**: [Service Catalog](services-catalog.html)

### Service Categories
- **Description**: Organize services into logical categories with visual management
- **Key Elements**:
  - Category grid with drag-and-drop reordering
  - Category creation/editing forms
  - Color coding for visual distinction
  - Service count per category
  - Uncategorized services management
  - Bulk service assignment
- **User Journey**: Organize services for better customer navigation
- **Mockup**: [Service Categories](services-categories.html)

### Pricing Configuration
- **Description**: Advanced pricing management with rules and price lists
- **Key Elements**:
  - Price list creation and management
  - Customer type-based pricing
  - Pricing rule builder
  - Price calculator tool
  - Discount configuration
  - Pricing preview and testing
- **User Journey**: Implement sophisticated pricing strategies
- **Mockup**: [Pricing Config](services-pricing.html)

### Quote Templates
- **Description**: Create and customize professional quote templates
- **Key Elements**:
  - Template selection grid
  - Template editor with variable insertion
  - Preview functionality with sample data
  - Template duplication and customization
  - Default template designation
  - Brand consistency controls
- **User Journey**: Ensure professional, consistent quote presentation
- **Mockup**: [Quote Templates](services-templates.html)

---

## 5. Shared Components

### Main Navigation Layout
- **Description**: Consistent navigation structure across all admin screens
- **Key Elements**:
  - Collapsible sidebar navigation
  - User profile dropdown
  - Business switcher (for multi-business users)
  - Notification bell with badge
  - Search functionality
  - Mobile-responsive hamburger menu
- **User Journey**: Seamless navigation between admin functions
- **Mockup**: [Navigation Layout](shared-navigation.html)

### Modal Components
- **Description**: Reusable modal dialogs for various interactions
- **Key Elements**:
  - Confirmation dialogs
  - Form modals for quick actions
  - Success/error notifications
  - Loading states
  - Multi-step wizards
- **User Journey**: Consistent interaction patterns across the admin portal
- **Mockup**: [Modal Components](shared-modals.html)

### Form Components
- **Description**: Standardized form elements and validation patterns
- **Key Elements**:
  - Input field styles and validation states
  - File upload components
  - Date/time pickers
  - Multi-select dropdowns
  - Rich text editors
  - Form wizard progression
- **User Journey**: Consistent data entry experience
- **Mockup**: [Form Components](shared-forms.html)

---

## Screen Flow & User Journeys

### First-Time Setup Flow
1. Admin Dashboard (welcome state)
2. Company Information Setup
3. Operating Hours & Service Areas
4. Service Catalog Management
5. Staff Invitations
6. Return to Dashboard (configured state)

### Daily Management Flow
1. Admin Dashboard (business metrics review)
2. Quick Actions (create quote, schedule job)
3. Staff Activity Tracking (team oversight)
4. Recent Activity Feed (business monitoring)

### Configuration Management Flow
1. Business Profile screens (ongoing updates)
2. Service & Pricing adjustments
3. Staff & Permission management
4. Notification & Template customization

## Design Principles

### Enterprise Trust
- Professional color scheme and typography
- Consistent spacing and visual hierarchy
- Clear data presentation with proper formatting
- Reliable interaction patterns

### User Experience Priority
- Minimal cognitive load with clear navigation
- Progressive disclosure of complex features
- Contextual help and validation messages
- Mobile-responsive design for field access

### Operational Efficiency
- Quick access to common tasks
- Bulk operations where appropriate
- Keyboard shortcuts for power users
- Fast loading with optimized performance

## Success Metrics for UI/UX
- Business setup completion rate > 95%
- Average task completion time < 3 minutes
- User satisfaction score > 4.5/5
- Support ticket reduction > 50%
