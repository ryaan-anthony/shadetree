# SaaS Owner Models & Database Schema

This document outlines the models, fields, and relationships required for the Shadetree SaaS owner platform management functionality based on the feature requirements.

## Platform Management Models

### PlatformAdmin
Administrative users who manage the SaaS platform.

**Fields:**
- `id` (primary key)
- `user_id` (foreign key, required) - Associated user account
- `admin_level` (string, required) - super_admin, admin, support, billing
- `permissions` (json) - Specific platform permissions
- `is_active` (boolean, default: true) - Admin status
- `last_login_at` (timestamp) - Last platform login
- `ip_restrictions` (json) - IP whitelist for access
- `mfa_enabled` (boolean, default: false) - Multi-factor authentication
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :user`
- `has_many :impersonation_sessions, dependent: :destroy`
- `has_many :platform_activities, dependent: :destroy`
- `has_many :admin_notes, dependent: :destroy`

## Subscription Management Models

### SubscriptionPlan
Available subscription plans for businesses.

**Fields:**
- `id` (primary key)
- `name` (string, required) - Plan name (Free, Pro, Enterprise)
- `description` (text) - Plan description
- `price_monthly` (decimal, required) - Monthly price
- `price_yearly` (decimal) - Yearly price (if applicable)
- `billing_interval` (string, required) - monthly, yearly
- `trial_days` (integer, default: 0) - Trial period length
- `max_staff` (integer) - Maximum staff members
- `max_locations` (integer) - Maximum locations
- `max_customers` (integer) - Maximum customers
- `features` (json) - Available features list
- `storage_limit_gb` (integer) - Storage limit in GB
- `api_calls_limit` (integer) - API calls per month
- `support_level` (string) - basic, priority, dedicated
- `is_active` (boolean, default: true) - Plan availability
- `sort_order` (integer, default: 0) - Display order
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `has_many :subscriptions, dependent: :restrict_with_error`
- `has_many :plan_changes, foreign_key: 'new_plan_id', dependent: :destroy`
- `has_many :plan_changes_from, class_name: 'PlanChange', foreign_key: 'old_plan_id', dependent: :destroy`

### Subscription
Customer subscription records and billing information.

**Fields:**
- `id` (primary key)
- `business_id` (foreign key, required) - Subscribed business
- `subscription_plan_id` (foreign key, required) - Current plan
- `status` (string, required) - active, trialing, past_due, canceled, unpaid
- `billing_interval` (string, required) - monthly, yearly
- `current_period_start` (date, required) - Current billing period start
- `current_period_end` (date, required) - Current billing period end
- `trial_start` (date) - Trial start date
- `trial_end` (date) - Trial end date
- `canceled_at` (timestamp) - Cancellation timestamp
- `cancel_at_period_end` (boolean, default: false) - Cancel at period end
- `cancellation_reason` (text) - Reason for cancellation
- `stripe_subscription_id` (string) - External subscription ID
- `stripe_customer_id` (string) - External customer ID
- `next_billing_amount` (decimal) - Next billing amount
- `discount_percent` (decimal, default: 0) - Applied discount percentage
- `discount_amount` (decimal, default: 0) - Applied discount amount
- `notes` (text) - Internal subscription notes
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :business`
- `belongs_to :subscription_plan`
- `has_many :billing_invoices, dependent: :destroy`
- `has_many :plan_changes, dependent: :destroy`
- `has_many :usage_records, dependent: :destroy`

### PlanChange
History of subscription plan changes and upgrades/downgrades.

**Fields:**
- `id` (primary key)
- `subscription_id` (foreign key, required) - Associated subscription
- `old_plan_id` (foreign key, required) - Previous plan
- `new_plan_id` (foreign key, required) - New plan
- `change_type` (string, required) - upgrade, downgrade, change
- `effective_date` (date, required) - Change effective date
- `proration_amount` (decimal, default: 0) - Proration charge/credit
- `reason` (text) - Change reason
- `initiated_by_type` (string, required) - customer, admin, system
- `initiated_by_id` (integer) - User who initiated change
- `status` (string, default: 'pending') - pending, completed, failed, canceled
- `processed_at` (timestamp) - Processing completion time
- `billing_adjustment_created` (boolean, default: false) - Billing update status
- `notes` (text) - Change notes
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :subscription`
- `belongs_to :old_plan, class_name: 'SubscriptionPlan'`
- `belongs_to :new_plan, class_name: 'SubscriptionPlan'`
- `belongs_to :initiated_by, polymorphic: true`

### BillingInvoice
Billing invoices and payment records for subscriptions.

**Fields:**
- `id` (primary key)
- `subscription_id` (foreign key, required) - Associated subscription
- `business_id` (foreign key, required) - Billed business
- `invoice_number` (string, required, unique) - Invoice identifier
- `amount_due` (decimal, required) - Invoice amount
- `amount_paid` (decimal, default: 0) - Amount paid
- `currency` (string, default: 'USD') - Invoice currency
- `billing_period_start` (date, required) - Billing period start
- `billing_period_end` (date, required) - Billing period end
- `due_date` (date, required) - Payment due date
- `paid_at` (timestamp) - Payment timestamp
- `status` (string, default: 'draft') - draft, open, paid, void, uncollectible
- `stripe_invoice_id` (string) - External invoice ID
- `stripe_payment_intent_id` (string) - External payment ID
- `tax_amount` (decimal, default: 0) - Tax amount
- `discount_amount` (decimal, default: 0) - Discount applied
- `subtotal` (decimal, required) - Pre-tax amount
- `payment_method` (string) - Payment method used
- `failure_reason` (text) - Payment failure reason
- `invoice_pdf_url` (string) - Generated PDF URL
- `sent_at` (timestamp) - Invoice sent timestamp
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :subscription`
- `belongs_to :business`
- `has_many :invoice_line_items, dependent: :destroy`

### InvoiceLineItem
Individual line items within billing invoices.

**Fields:**
- `id` (primary key)
- `billing_invoice_id` (foreign key, required) - Associated invoice
- `description` (text, required) - Line item description
- `quantity` (decimal, default: 1) - Item quantity
- `unit_price` (decimal, required) - Price per unit
- `amount` (decimal, required) - Line total amount
- `proration` (boolean, default: false) - Proration item flag
- `period_start` (date) - Service period start
- `period_end` (date) - Service period end
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :billing_invoice`

## Usage Analytics Models

### UsageRecord
Daily/monthly usage tracking for businesses and platform metrics.

**Fields:**
- `id` (primary key)
- `business_id` (foreign key, required) - Associated business
- `subscription_id` (foreign key, required) - Associated subscription
- `record_date` (date, required) - Usage date
- `record_type` (string, required) - daily, monthly
- `metric_type` (string, required) - logins, api_calls, storage_used, customers_created
- `metric_value` (decimal, required) - Metric value
- `unit` (string) - Metric unit (count, bytes, minutes)
- `metadata` (json) - Additional usage data
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :business`
- `belongs_to :subscription`

### PlatformMetric
Platform-wide aggregated metrics for SaaS owner dashboard.

**Fields:**
- `id` (primary key)
- `metric_date` (date, required) - Metric date
- `metric_type` (string, required) - total_customers, active_customers, new_signups, churn_rate, mrr
- `metric_value` (decimal, required) - Metric value
- `previous_value` (deciml) - Previous period value
- `change_percentage` (decimal) - Period-over-period change
- `metadata` (json) - Additional metric data
- `calculated_at` (timestamp, required) - Calculation timestamp
- `created_at` (timestamp)
- `updated_at` (timestamp)

### FeatureUsage
Feature-specific usage tracking across businesses.

**Fields:**
- `id` (primary key)
- `business_id` (foreign key, required) - Associated business
- `feature_name` (string, required) - Feature identifier
- `usage_date` (date, required) - Usage date
- `usage_count` (integer, default: 0) - Usage count
- `unique_users` (integer, default: 0) - Unique users who used feature
- `session_duration` (integer, default: 0) - Total session duration in minutes
- `last_used_at` (timestamp) - Last usage timestamp
- `metadata` (json) - Additional usage data
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :business`

## Customer Management Models

### AdminNote
Internal notes about businesses/customers for platform management.

**Fields:**
- `id` (primary key)
- `business_id` (foreign key, required) - Associated business
- `platform_admin_id` (foreign key, required) - Note author
- `note_type` (string, required) - support, billing, account, technical
- `title` (string, required) - Note title
- `content` (text, required) - Note content
- `priority` (string, default: 'normal') - low, normal, high, urgent
- `is_internal` (boolean, default: true) - Internal visibility flag
- `follow_up_date` (date) - Follow-up reminder date
- `resolved_at` (timestamp) - Resolution timestamp
- `tags` (json) - Note tags for categorization
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :business`
- `belongs_to :platform_admin`

### CustomerHealthScore
Automated health scoring for business accounts.

**Fields:**
- `id` (primary key)
- `business_id` (foreign key, required) - Associated business
- `score` (integer, required) - Health score (0-100)
- `score_date` (date, required) - Score calculation date
- `usage_score` (integer) - Usage-based score component
- `engagement_score` (integer) - Engagement-based score component
- `billing_score` (integer) - Billing health score component
- `support_score` (integer) - Support interaction score component
- `risk_level` (string, required) - low, medium, high, critical
- `risk_factors` (json) - Identified risk factors
- `improvement_suggestions` (json) - Suggested improvements
- `calculated_at` (timestamp, required) - Calculation timestamp
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :business`

## Support & Impersonation Models

### ImpersonationSession
Support staff impersonation sessions for customer assistance.

**Fields:**
- `id` (primary key)
- `platform_admin_id` (foreign key, required) - Impersonating admin
- `business_id` (foreign key, required) - Target business
- `impersonated_user_id` (foreign key, required) - Target user
- `session_token` (string, required, unique) - Secure session token
- `reason` (text, required) - Impersonation reason
- `started_at` (timestamp, required) - Session start time
- `ended_at` (timestamp) - Session end time
- `duration_minutes` (integer) - Session duration
- `ip_address` (string) - Impersonation IP address
- `user_agent` (text) - Browser information
- `status` (string, default: 'active') - active, ended, expired, terminated
- `activities_performed` (json) - Actions taken during session
- `restrictions` (json) - Applied restrictions during session
- `approval_required` (boolean, default: false) - Required approval flag
- `approved_by_id` (foreign key, optional) - Approving admin
- `approved_at` (timestamp) - Approval timestamp
- `termination_reason` (text) - Termination reason
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :platform_admin`
- `belongs_to :business`
- `belongs_to :impersonated_user, class_name: 'User'`
- `belongs_to :approved_by, class_name: 'PlatformAdmin', optional: true`
- `has_many :impersonation_activities, dependent: :destroy`

### ImpersonationActivity
Individual actions performed during impersonation sessions.

**Fields:**
- `id` (primary key)
- `impersonation_session_id` (foreign key, required) - Associated session
- `action_type` (string, required) - view, create, update, delete, login
- `resource_type` (string) - Model/resource accessed
- `resource_id` (integer) - Specific record ID
- `action_description` (text) - Description of action taken
- `before_state` (json) - Resource state before action
- `after_state` (json) - Resource state after action
- `ip_address` (string) - Action IP address
- `user_agent` (text) - Browser information
- `performed_at` (timestamp, required) - Action timestamp
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :impersonation_session`

## Feature Management Models

### FeatureFlag
Platform feature toggles and A/B testing configuration.

**Fields:**
- `id` (primary key)
- `name` (string, required, unique) - Feature flag identifier
- `description` (text) - Feature description
- `flag_type` (string, required) - boolean, percentage, variant
- `is_enabled` (boolean, default: false) - Global enable/disable
- `rollout_percentage` (integer, default: 0) - Rollout percentage (0-100)
- `target_audience` (json) - Targeting rules
- `variant_config` (json) - A/B test variants
- `environment` (string, default: 'production') - production, staging, development
- `created_by_id` (foreign key, required) - Creator admin
- `last_modified_by_id` (foreign key, required) - Last modifier admin
- `expires_at` (timestamp) - Feature flag expiration
- `metrics_tracked` (json) - Tracked metrics for evaluation
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :created_by, class_name: 'PlatformAdmin'`
- `belongs_to :last_modified_by, class_name: 'PlatformAdmin'`
- `has_many :feature_flag_evaluations, dependent: :destroy`

### FeatureFlagEvaluation
Feature flag evaluation logs for analytics and debugging.

**Fields:**
- `id` (primary key)
- `feature_flag_id` (foreign key, required) - Associated feature flag
- `business_id` (foreign key, optional) - Target business
- `user_id` (foreign key, optional) - Target user
- `evaluation_result` (boolean, required) - Flag evaluation result
- `variant_assigned` (string) - A/B test variant assigned
- `evaluation_context` (json) - Context used for evaluation
- `evaluated_at` (timestamp, required) - Evaluation timestamp
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :feature_flag`
- `belongs_to :business, optional: true`
- `belongs_to :user, optional: true`

## Platform Activity Models

### PlatformActivity
Administrative activities and audit trail for platform changes.

**Fields:**
- `id` (primary key)
- `platform_admin_id` (foreign key, required) - Admin performing action
- `activity_type` (string, required) - login, customer_view, plan_change, impersonation, etc.
- `target_type` (string) - Target resource type (polymorphic)
- `target_id` (integer) - Target resource ID (polymorphic)
- `action_description` (text, required) - Description of action
- `before_state` (json) - State before action
- `after_state` (json) - State after action
- `ip_address` (string) - Action IP address
- `user_agent` (text) - Browser information
- `session_id` (string) - Admin session ID
- `success` (boolean, default: true) - Action success status
- `error_message` (text) - Error details if failed
- `performed_at` (timestamp, required) - Action timestamp
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :platform_admin`
- `belongs_to :target, polymorphic: true, optional: true`

## Key Indexes

```sql
-- Platform Admin indexes
CREATE INDEX index_platform_admins_on_user_id ON platform_admins(user_id);
CREATE INDEX index_platform_admins_on_admin_level ON platform_admins(admin_level);
CREATE INDEX index_platform_admins_on_is_active ON platform_admins(is_active);

-- Subscription indexes
CREATE INDEX index_subscriptions_on_business_id ON subscriptions(business_id);
CREATE INDEX index_subscriptions_on_plan_id ON subscriptions(subscription_plan_id);
CREATE INDEX index_subscriptions_on_status ON subscriptions(status);
CREATE INDEX index_subscriptions_on_current_period_end ON subscriptions(current_period_end);

-- Usage Analytics indexes
CREATE INDEX index_usage_records_on_business_id ON usage_records(business_id);
CREATE INDEX index_usage_records_on_record_date ON usage_records(record_date);
CREATE INDEX index_usage_records_on_metric_type ON usage_records(metric_type);
CREATE INDEX index_platform_metrics_on_metric_date ON platform_metrics(metric_date);
CREATE INDEX index_platform_metrics_on_metric_type ON platform_metrics(metric_type);

-- Billing indexes
CREATE INDEX index_billing_invoices_on_subscription_id ON billing_invoices(subscription_id);
CREATE INDEX index_billing_invoices_on_status ON billing_invoices(status);
CREATE INDEX index_billing_invoices_on_due_date ON billing_invoices(due_date);

-- Support Impersonation indexes
CREATE INDEX index_impersonation_sessions_on_admin_id ON impersonation_sessions(platform_admin_id);
CREATE INDEX index_impersonation_sessions_on_business_id ON impersonation_sessions(business_id);
CREATE INDEX index_impersonation_sessions_on_status ON impersonation_sessions(status);
CREATE INDEX index_impersonation_sessions_on_started_at ON impersonation_sessions(started_at);

-- Feature Flag indexes
CREATE INDEX index_feature_flags_on_name ON feature_flags(name);
CREATE INDEX index_feature_flags_on_is_enabled ON feature_flags(is_enabled);
CREATE INDEX index_feature_flag_evaluations_on_flag_id ON feature_flag_evaluations(feature_flag_id);

-- Activity indexes
CREATE INDEX index_platform_activities_on_admin_id ON platform_activities(platform_admin_id);
CREATE INDEX index_platform_activities_on_performed_at ON platform_activities(performed_at);
CREATE INDEX index_platform_activities_on_activity_type ON platform_activities(activity_type);
```

## Foreign Key Constraints

```sql
-- Platform Admin relationships
ALTER TABLE platform_admins ADD CONSTRAINT fk_platform_admins_user FOREIGN KEY (user_id) REFERENCES users(id);

-- Subscription relationships
ALTER TABLE subscriptions ADD CONSTRAINT fk_subscriptions_business FOREIGN KEY (business_id) REFERENCES businesses(id);
ALTER TABLE subscriptions ADD CONSTRAINT fk_subscriptions_plan FOREIGN KEY (subscription_plan_id) REFERENCES subscription_plans(id);
ALTER TABLE plan_changes ADD CONSTRAINT fk_plan_changes_subscription FOREIGN KEY (subscription_id) REFERENCES subscriptions(id);
ALTER TABLE plan_changes ADD CONSTRAINT fk_plan_changes_old_plan FOREIGN KEY (old_plan_id) REFERENCES subscription_plans(id);
ALTER TABLE plan_changes ADD CONSTRAINT fk_plan_changes_new_plan FOREIGN KEY (new_plan_id) REFERENCES subscription_plans(id);

-- Billing relationships
ALTER TABLE billing_invoices ADD CONSTRAINT fk_billing_invoices_subscription FOREIGN KEY (subscription_id) REFERENCES subscriptions(id);
ALTER TABLE billing_invoices ADD CONSTRAINT fk_billing_invoices_business FOREIGN KEY (business_id) REFERENCES businesses(id);
ALTER TABLE invoice_line_items ADD CONSTRAINT fk_invoice_line_items_invoice FOREIGN KEY (billing_invoice_id) REFERENCES billing_invoices(id);

-- Usage Analytics relationships
ALTER TABLE usage_records ADD CONSTRAINT fk_usage_records_business FOREIGN KEY (business_id) REFERENCES businesses(id);
ALTER TABLE usage_records ADD CONSTRAINT fk_usage_records_subscription FOREIGN KEY (subscription_id) REFERENCES subscriptions(id);
ALTER TABLE feature_usage ADD CONSTRAINT fk_feature_usage_business FOREIGN KEY (business_id) REFERENCES businesses(id);

-- Customer Management relationships
ALTER TABLE admin_notes ADD CONSTRAINT fk_admin_notes_business FOREIGN KEY (business_id) REFERENCES businesses(id);
ALTER TABLE admin_notes ADD CONSTRAINT fk_admin_notes_admin FOREIGN KEY (platform_admin_id) REFERENCES platform_admins(id);
ALTER TABLE customer_health_scores ADD CONSTRAINT fk_customer_health_scores_business FOREIGN KEY (business_id) REFERENCES businesses(id);

-- Support Impersonation relationships
ALTER TABLE impersonation_sessions ADD CONSTRAINT fk_impersonation_sessions_admin FOREIGN KEY (platform_admin_id) REFERENCES platform_admins(id);
ALTER TABLE impersonation_sessions ADD CONSTRAINT fk_impersonation_sessions_business FOREIGN KEY (business_id) REFERENCES businesses(id);
ALTER TABLE impersonation_sessions ADD CONSTRAINT fk_impersonation_sessions_user FOREIGN KEY (impersonated_user_id) REFERENCES users(id);
ALTER TABLE impersonation_activities ADD CONSTRAINT fk_impersonation_activities_session FOREIGN KEY (impersonation_session_id) REFERENCES impersonation_sessions(id);

-- Feature Flag relationships
ALTER TABLE feature_flags ADD CONSTRAINT fk_feature_flags_created_by FOREIGN KEY (created_by_id) REFERENCES platform_admins(id);
ALTER TABLE feature_flags ADD CONSTRAINT fk_feature_flags_modified_by FOREIGN KEY (last_modified_by_id) REFERENCES platform_admins(id);
ALTER TABLE feature_flag_evaluations ADD CONSTRAINT fk_feature_flag_evaluations_flag FOREIGN KEY (feature_flag_id) REFERENCES feature_flags(id);

-- Platform Activity relationships
ALTER TABLE platform_activities ADD CONSTRAINT fk_platform_activities_admin FOREIGN KEY (platform_admin_id) REFERENCES platform_admins(id);
```

This schema provides a comprehensive foundation for the Shadetree SaaS owner platform management functionality, supporting all the features outlined in the requirements including customer management, subscription billing, usage analytics, support impersonation, feature flags, and platform administration.
