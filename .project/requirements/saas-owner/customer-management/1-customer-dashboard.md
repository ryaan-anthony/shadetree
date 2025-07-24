# Feature: Customer Dashboard

Centralized view of all customers with key metrics and status indicators for platform administrators to monitor platform usage and customer health.

## User Stories
- As a platform administrator, I want to see all customers at a glance so I can monitor platform adoption
- As a support manager, I want to view customer metrics so I can identify accounts needing attention  
- As an operations manager, I want customer status indicators so I can track account health

## Tasks

### 1. Create Customer Overview Page
Build main dashboard page displaying customer list with essential information

**Implementation Notes:**
- Create customers controller with index action
- Design responsive table layout with pagination
- Include customer name, signup date, subscription status, last activity
- Add search bar in header for quick customer lookup
- Implement sorting by name, signup date, and activity

### 2. Add Customer Metrics Cards
Display key platform metrics in card format above customer list

**Implementation Notes:**
- Create dashboard service to calculate metrics
- Add metric cards for total customers, active customers, trial customers, churned customers
- Use background jobs to calculate metrics if performance becomes an issue
- Cache metric calculations for better performance
- Style cards using design system metric card patterns

### 3. Implement Status Indicators
Visual indicators for customer account health and subscription status

**Implementation Notes:**
- Add status column to customers table
- Create status badge component with colors from design system
- Include statuses: active, trial, suspended, cancelled, overdue
- Add tooltip hover states explaining each status
- Ensure status updates reflect real-time subscription changes

### 4. Build Customer Quick Actions
Action buttons for common customer management tasks

**Implementation Notes:**
- Add action column with dropdown menu
- Include quick actions: view details, impersonate, add note, suspend account
- Implement permissions checking for each action
- Add confirmation dialogs for destructive actions
- Use Stimulus controllers for interactive behaviors
