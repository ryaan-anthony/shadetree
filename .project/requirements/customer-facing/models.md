# Customer-Facing Models & Database Schema

This document outlines the models, fields, and relationships required for the Shadetree customer-facing functionality based on the feature requirements.

## Quote & Request Models

### QuoteRequest
Customer-initiated service quote requests with dynamic form data.

**Fields:**
- `id` (primary key)
- `business_id` (foreign key, required) - Target business
- `customer_id` (foreign key, optional) - Associated customer (if registered)
- `form_configuration_id` (foreign key, required) - Form template used
- `status` (string, default: 'pending') - pending, quoted, approved, declined, expired
- `customer_name` (string, required) - Customer full name
- `customer_email` (string, required) - Customer email
- `customer_phone` (string) - Customer phone number
- `service_address` (text, required) - Service location address
- `service_city` (string, required) - Service city
- `service_state` (string, required) - Service state
- `service_zip_code` (string, required) - Service zip code
- `preferred_contact_method` (string) - email, phone, sms
- `urgency` (string) - low, medium, high, emergency
- `form_data` (json) - Dynamic form responses
- `notes` (text) - Additional customer notes
- `estimated_budget` (decimal) - Customer's budget range
- `preferred_start_date` (date) - Desired service start date
- `referral_source` (string) - How customer found business
- `ip_address` (string) - Request IP for spam prevention
- `user_agent` (text) - Browser info for analytics
- `submitted_at` (timestamp) - Request submission time
- `expires_at` (timestamp) - Request expiration time
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :business`
- `belongs_to :customer, optional: true`
- `belongs_to :form_configuration`
- `has_many :quote_request_services, dependent: :destroy`
- `has_many :services, through: :quote_request_services`
- `has_many :quote_request_attachments, dependent: :destroy`
- `has_one :quote, dependent: :destroy`

### FormConfiguration
Business-specific quote request form templates with branding.

**Fields:**
- `id` (primary key)
- `business_id` (foreign key, required) - Associated business
- `name` (string, required) - Form template name
- `title` (string, required) - Form display title
- `description` (text) - Form description/instructions
- `fields_configuration` (json) - Dynamic form fields schema
- `branding_configuration` (json) - Colors, logo, styling
- `notification_settings` (json) - Email/SMS notification preferences
- `is_active` (boolean, default: true) - Form status
- `is_default` (boolean, default: false) - Default form flag
- `embed_code` (text) - Generated embed snippet
- `custom_domain` (string) - White-label domain
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :business`
- `has_many :quote_requests, dependent: :destroy`

### QuoteRequestService
Services selected in quote requests (many-to-many).

**Fields:**
- `id` (primary key)
- `quote_request_id` (foreign key, required)
- `service_id` (foreign key, required)
- `quantity` (integer, default: 1) - Service quantity
- `specific_requirements` (text) - Service-specific notes
- `estimated_scope` (text) - Customer's scope description
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :quote_request`
- `belongs_to :service`

### QuoteRequestAttachment
File uploads associated with quote requests.

**Fields:**
- `id` (primary key)
- `quote_request_id` (foreign key, required)
- `file_name` (string, required) - Original filename
- `file_size` (integer) - File size in bytes
- `file_type` (string) - MIME type
- `storage_key` (string, required) - Storage service key
- `description` (text) - File description
- `uploaded_at` (timestamp) - Upload timestamp
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :quote_request`

### IndustryTemplate
Pre-built form templates with industry-specific defaults.

**Fields:**
- `id` (primary key)
- `industry_name` (string, required) - Industry identifier
- `template_name` (string, required) - Template display name
- `description` (text) - Template description
- `default_fields_schema` (json) - Default form fields configuration
- `measurement_units` (json) - Industry-standard units
- `terminology_guide` (json) - Industry-specific terms and explanations
- `seasonal_defaults` (json) - Date-based default adjustments
- `geographical_defaults` (json) - Location-based defaults
- `is_active` (boolean, default: true) - Template availability
- `sort_order` (integer, default: 0) - Display order
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `has_many :form_configurations, dependent: :nullify`

## Document Management Models

### Document
Centralized document storage and management.

**Fields:**
- `id` (primary key)
- `business_id` (foreign key, required) - Document owner business
- `customer_id` (foreign key, optional) - Associated customer
- `quote_id` (foreign key, optional) - Associated quote
- `appointment_id` (foreign key, optional) - Associated appointment
- `service_history_id` (foreign key, optional) - Associated service
- `document_type` (string, required) - quote, invoice, contract, receipt, report, warranty
- `title` (string, required) - Document title
- `description` (text) - Document description
- `file_name` (string, required) - Original filename
- `file_size` (integer) - File size in bytes
- `file_type` (string) - MIME type
- `storage_key` (string, required) - Storage service key
- `pdf_url` (string) - Generated PDF URL
- `version` (integer, default: 1) - Document version
- `status` (string, default: 'active') - active, archived, deleted
- `tags` (json) - Document tags for categorization
- `metadata` (json) - Additional document metadata
- `access_level` (string, default: 'customer') - customer, business, internal
- `is_signed` (boolean, default: false) - Digital signature status
- `retention_expires_at` (date) - Document retention expiration
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :business`
- `belongs_to :customer, optional: true`
- `belongs_to :quote, optional: true`
- `belongs_to :appointment, optional: true`
- `belongs_to :service_history, optional: true`
- `has_many :document_access_logs, dependent: :destroy`
- `has_many :digital_signatures, dependent: :destroy`

### DocumentAccessLog
Audit trail for document access and actions.

**Fields:**
- `id` (primary key)
- `document_id` (foreign key, required) - Accessed document
- `user_id` (foreign key, optional) - User who accessed (if logged in)
- `customer_id` (foreign key, optional) - Customer who accessed
- `action` (string, required) - view, download, share, print
- `ip_address` (string) - Access IP address
- `user_agent` (text) - Browser information
- `accessed_at` (timestamp, required) - Access timestamp
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :document`
- `belongs_to :user, optional: true`
- `belongs_to :customer, optional: true`

## Digital Signature Models

### DigitalSignature
Digital signatures for documents and agreements.

**Fields:**
- `id` (primary key)
- `document_id` (foreign key, required) - Signed document
- `quote_id` (foreign key, optional) - Associated quote
- `signer_name` (string, required) - Signatory full name
- `signer_email` (string, required) - Signatory email
- `signer_ip_address` (string) - Signing IP address
- `signature_method` (string, required) - draw, type, click, upload
- `signature_data` (text) - Signature image/vector data
- `signature_position` (json) - Position on document
- `typed_signature_font` (string) - Font used for typed signatures
- `user_agent` (text) - Browser information
- `signed_at` (timestamp, required) - Signature timestamp
- `verification_code` (string) - Signature verification hash
- `is_verified` (boolean, default: true) - Signature validity
- `witness_email` (string) - Witness email (if required)
- `witness_signed_at` (timestamp) - Witness signature time
- `compliance_data` (json) - Legal compliance metadata
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :document`
- `belongs_to :quote, optional: true`

## Payment Scheduling Models

### PaymentSchedule
Payment plans and installment schedules.

**Fields:**
- `id` (primary key)
- `quote_id` (foreign key, required) - Associated quote
- `customer_id` (foreign key, required) - Customer making payments
- `total_amount` (decimal, required) - Total amount to be paid
- `schedule_type` (string, required) - deposit, installments, milestone
- `number_of_payments` (integer, required) - Total payment count
- `deposit_amount` (decimal) - Required deposit amount
- `deposit_percentage` (decimal) - Deposit as percentage
- `installment_amount` (decimal) - Regular installment amount
- `payment_frequency` (string) - weekly, monthly, milestone
- `first_payment_date` (date, required) - First payment due date
- `final_payment_date` (date) - Final payment due date
- `auto_charge` (boolean, default: false) - Automatic payment flag
- `late_fee_amount` (decimal) - Late payment fee
- `late_fee_percentage` (decimal) - Late fee as percentage
- `grace_period_days` (integer, default: 0) - Grace period before late fees
- `status` (string, default: 'active') - active, completed, cancelled, defaulted
- `notes` (text) - Payment schedule notes
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :quote`
- `belongs_to :customer`
- `has_many :scheduled_payments, dependent: :destroy`

### ScheduledPayment
Individual payments within a payment schedule.

**Fields:**
- `id` (primary key)
- `payment_schedule_id` (foreign key, required) - Associated schedule
- `payment_number` (integer, required) - Payment sequence number
- `amount_due` (decimal, required) - Payment amount
- `due_date` (date, required) - Payment due date
- `payment_type` (string, required) - deposit, installment, final, late_fee
- `description` (string) - Payment description
- `status` (string, default: 'pending') - pending, paid, overdue, waived
- `paid_amount` (decimal, default: 0) - Amount actually paid
- `paid_date` (date) - Date payment was made
- `payment_id` (foreign key, optional) - Actual payment record
- `reminder_sent_at` (timestamp) - Last reminder sent
- `late_fee_applied` (decimal, default: 0) - Applied late fees
- `notes` (text) - Payment-specific notes
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :payment_schedule`
- `belongs_to :payment, optional: true`

## Calendar Integration Models

### CalendarIntegration
Customer calendar integration for appointments.

**Fields:**
- `id` (primary key)
- `customer_id` (foreign key, required) - Associated customer
- `calendar_provider` (string, required) - google, outlook, apple, ical
- `calendar_id` (string) - External calendar identifier
- `access_token` (text) - OAuth access token (encrypted)
- `refresh_token` (text) - OAuth refresh token (encrypted)
- `token_expires_at` (timestamp) - Token expiration
- `sync_enabled` (boolean, default: true) - Sync status
- `sync_preferences` (json) - Sync settings and preferences
- `last_sync_at` (timestamp) - Last successful sync
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :customer`
- `has_many :calendar_events, dependent: :destroy`

### CalendarEvent
Synchronized calendar events for appointments.

**Fields:**
- `id` (primary key)
- `calendar_integration_id` (foreign key, required) - Associated integration
- `appointment_id` (foreign key, required) - Associated appointment
- `external_event_id` (string) - Calendar provider event ID
- `event_title` (string, required) - Calendar event title
- `event_description` (text) - Event description
- `event_start` (datetime, required) - Event start time
- `event_end` (datetime, required) - Event end time
- `event_location` (text) - Event location
- `sync_status` (string, default: 'pending') - pending, synced, failed, cancelled
- `last_sync_attempt` (timestamp) - Last sync attempt
- `sync_error` (text) - Sync error message
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :calendar_integration`
- `belongs_to :appointment`

## Quote & Approval Models

### Quote
Business-generated quotes in response to customer requests.

**Fields:**
- `id` (primary key)
- `business_id` (foreign key, required) - Issuing business
- `quote_request_id` (foreign key, required) - Original request
- `customer_id` (foreign key, optional) - Associated customer
- `quote_number` (string, required, unique) - Business quote number
- `status` (string, default: 'draft') - draft, sent, viewed, approved, declined, expired
- `title` (string, required) - Quote title/description
- `description` (text) - Detailed quote description
- `subtotal` (decimal, required) - Pre-tax/fee total
- `tax_amount` (decimal, default: 0) - Tax amount
- `fee_amount` (decimal, default: 0) - Additional fees
- `total_amount` (decimal, required) - Final total amount
- `currency` (string, default: 'USD') - Quote currency
- `valid_until` (date, required) - Quote expiration date
- `terms_and_conditions` (text) - Quote terms
- `payment_terms` (text) - Payment requirements
- `estimated_start_date` (date) - Estimated work start
- `estimated_completion_date` (date) - Estimated completion
- `deposit_required` (boolean, default: false) - Deposit requirement
- `deposit_amount` (decimal) - Required deposit amount
- `deposit_percentage` (decimal) - Deposit percentage
- `notes` (text) - Internal business notes
- `sent_at` (timestamp) - Quote sent timestamp
- `viewed_at` (timestamp) - Customer view timestamp
- `approved_at` (timestamp) - Customer approval timestamp
- `declined_at` (timestamp) - Customer decline timestamp
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :business`
- `belongs_to :quote_request`
- `belongs_to :customer, optional: true`
- `has_many :quote_line_items, dependent: :destroy`
- `has_many :quote_approvals, dependent: :destroy`
- `has_many :quote_change_requests, dependent: :destroy`
- `has_many :payments, dependent: :destroy`
- `has_many :appointments, dependent: :destroy`

### QuoteLineItem
Individual services/items within a quote.

**Fields:**
- `id` (primary key)
- `quote_id` (foreign key, required) - Associated quote
- `service_id` (foreign key, optional) - Associated service
- `description` (text, required) - Line item description
- `quantity` (decimal, default: 1) - Item quantity
- `unit_price` (decimal, required) - Price per unit
- `line_total` (decimal, required) - Line total amount
- `sort_order` (integer, default: 0) - Display order
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :quote`
- `belongs_to :service, optional: true`

### QuoteApproval
Customer quote approval with digital signature.

**Fields:**
- `id` (primary key)
- `quote_id` (foreign key, required) - Approved quote
- `customer_name` (string, required) - Signatory name
- `customer_email` (string, required) - Signatory email
- `signature_type` (string, required) - draw, type, click
- `signature_data` (text) - Signature image/data
- `ip_address` (string) - Approval IP address
- `user_agent` (text) - Browser information
- `terms_accepted` (boolean, required) - Terms acceptance
- `approved_at` (timestamp, required) - Approval timestamp
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :quote`

### QuoteChangeRequest
Customer requests for quote modifications.

**Fields:**
- `id` (primary key)
- `quote_id` (foreign key, required) - Associated quote
- `customer_name` (string, required) - Requester name
- `customer_email` (string, required) - Requester email
- `change_description` (text, required) - Requested changes
- `status` (string, default: 'pending') - pending, reviewed, implemented, declined
- `business_response` (text) - Business response to request
- `responded_at` (timestamp) - Response timestamp
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :quote`

## Customer Management Models

### Customer
Customer profiles and contact information.

**Fields:**
- `id` (primary key)
- `user_id` (foreign key, optional) - Associated user account
- `first_name` (string, required) - Customer first name
- `last_name` (string, required) - Customer last name
- `email` (string, required) - Customer email
- `phone` (string) - Customer phone number
- `company_name` (string) - Company name (if business customer)
- `customer_type` (string, default: 'residential') - residential, commercial
- `preferred_contact_method` (string) - email, phone, sms
- `status` (string, default: 'active') - active, inactive, blocked
- `notes` (text) - Internal customer notes
- `referral_source` (string) - How customer found business
- `total_lifetime_value` (decimal, default: 0) - Total spent
- `average_project_value` (decimal, default: 0) - Average project cost
- `last_service_date` (date) - Most recent service
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :user, optional: true`
- `has_many :customer_addresses, dependent: :destroy`
- `has_many :quote_requests, dependent: :destroy`
- `has_many :quotes, dependent: :destroy`
- `has_many :appointments, dependent: :destroy`
- `has_many :payments, dependent: :destroy`
- `has_many :service_histories, dependent: :destroy`
- `has_many :customer_feedbacks, dependent: :destroy`

### CustomerAddress
Customer property addresses for service delivery.

**Fields:**
- `id` (primary key)
- `customer_id` (foreign key, required) - Associated customer
- `address_type` (string, default: 'service') - service, billing, mailing
- `label` (string) - Address nickname (e.g., "Main House")
- `address_line_1` (text, required) - Street address
- `address_line_2` (text) - Apartment/unit number
- `city` (string, required) - City
- `state` (string, required) - State/Province
- `zip_code` (string, required) - Postal code
- `country` (string, default: 'US') - Country code
- `latitude` (decimal, precision: 10, scale: 6) - GPS latitude
- `longitude` (decimal, precision: 10, scale: 6) - GPS longitude
- `is_primary` (boolean, default: false) - Primary address flag
- `access_instructions` (text) - Property access notes
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :customer`

## Appointment & Scheduling Models

### Appointment
Scheduled service appointments with customers.

**Fields:**
- `id` (primary key)
- `business_id` (foreign key, required) - Service business
- `customer_id` (foreign key, required) - Customer receiving service
- `quote_id` (foreign key, optional) - Associated quote
- `staff_member_id` (foreign key, optional) - Assigned staff
- `location_id` (foreign key, optional) - Service location
- `service_address_id` (foreign key, optional) - Service address
- `appointment_type` (string, required) - consultation, service, followup
- `title` (string, required) - Appointment title
- `description` (text) - Appointment description
- `scheduled_start` (datetime, required) - Start date/time
- `scheduled_end` (datetime, required) - End date/time
- `actual_start` (datetime) - Actual start time
- `actual_end` (datetime) - Actual end time
- `status` (string, default: 'scheduled') - scheduled, confirmed, in_progress, completed, cancelled, no_show
- `confirmation_required` (boolean, default: true) - Requires customer confirmation
- `confirmed_at` (timestamp) - Customer confirmation time
- `reminder_sent_at` (timestamp) - Last reminder sent
- `cancellation_reason` (text) - Cancellation reason
- `cancelled_at` (timestamp) - Cancellation time
- `notes` (text) - Appointment notes
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :business`
- `belongs_to :customer`
- `belongs_to :quote, optional: true`
- `belongs_to :staff_member, optional: true`
- `belongs_to :location, optional: true`
- `belongs_to :service_address, class_name: 'CustomerAddress', optional: true`
- `has_many :appointment_services, dependent: :destroy`
- `has_many :services, through: :appointment_services`
- `has_many :appointment_reminders, dependent: :destroy`

### AppointmentService
Services included in an appointment (many-to-many).

**Fields:**
- `id` (primary key)
- `appointment_id` (foreign key, required)
- `service_id` (foreign key, required)
- `duration` (integer) - Service duration in minutes
- `estimated_cost` (decimal) - Estimated service cost
- `actual_cost` (decimal) - Actual service cost
- `notes` (text) - Service-specific notes
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :appointment`
- `belongs_to :service`

### AppointmentReminder
Automated reminder notifications for appointments.

**Fields:**
- `id` (primary key)
- `appointment_id` (foreign key, required) - Associated appointment
- `reminder_type` (string, required) - email, sms, push
- `reminder_timing` (integer, required) - Hours before appointment
- `status` (string, default: 'pending') - pending, sent, delivered, failed
- `message_content` (text) - Reminder message
- `sent_at` (timestamp) - Sent timestamp
- `delivered_at` (timestamp) - Delivery confirmation
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :appointment`

### AppointmentRescheduling
Tracking appointment rescheduling requests and policies.

**Fields:**
- `id` (primary key)
- `appointment_id` (foreign key, required) - Original appointment
- `new_appointment_id` (foreign key, optional) - Rescheduled appointment
- `customer_id` (foreign key, required) - Customer requesting reschedule
- `business_id` (foreign key, required) - Associated business
- `reschedule_reason` (text) - Reason for rescheduling
- `original_start_time` (datetime, required) - Original appointment time
- `requested_start_time` (datetime) - Customer's requested new time
- `final_start_time` (datetime) - Final confirmed new time
- `status` (string, default: 'pending') - pending, approved, declined, completed
- `reschedule_fee` (decimal, default: 0) - Fee charged for rescheduling
- `reschedule_count` (integer, default: 1) - Number of times this appointment has been rescheduled
- `policy_compliance` (json) - Policy rules applied
- `requested_at` (timestamp, required) - Reschedule request time
- `approved_at` (timestamp) - Approval timestamp
- `completed_at` (timestamp) - Completion timestamp
- `notes` (text) - Rescheduling notes
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :appointment`
- `belongs_to :new_appointment, class_name: 'Appointment', optional: true`
- `belongs_to :customer`
- `belongs_to :business`

### ReschedulingPolicy
Business-defined policies for appointment rescheduling.

**Fields:**
- `id` (primary key)
- `business_id` (foreign key, required) - Associated business
- `service_id` (foreign key, optional) - Service-specific policy
- `policy_name` (string, required) - Policy name
- `minimum_notice_hours` (integer, required) - Required notice period
- `maximum_reschedules` (integer, default: 3) - Max reschedules per appointment
- `reschedule_fee_amount` (decimal, default: 0) - Fee for rescheduling
- `reschedule_fee_type` (string, default: 'fixed') - fixed, percentage
- `grace_period_hours` (integer, default: 0) - Free reschedule period
- `blackout_periods` (json) - Periods when rescheduling is not allowed
- `auto_approval` (boolean, default: true) - Automatic approval flag
- `staff_notification_required` (boolean, default: true) - Staff notification
- `is_active` (boolean, default: true) - Policy status
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :business`
- `belongs_to :service, optional: true`

## Quote Approval & Token Management Models

### QuoteApprovalToken
Secure tokens for quote approval mechanisms.

**Fields:**
- `id` (primary key)
- `quote_id` (foreign key, required) - Associated quote
- `token` (string, required, unique) - Secure approval token
- `approval_method` (string, required) - email, sms, web
- `token_type` (string, required) - approval, decline, view
- `expires_at` (timestamp, required) - Token expiration
- `used_at` (timestamp) - Token usage timestamp
- `ip_address` (string) - IP when token was used
- `user_agent` (text) - Browser info when used
- `is_active` (boolean, default: true) - Token status
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :quote`

## Payment Method Management Models

### PaymentMethodConfiguration
Business settings for enabled payment methods.

**Fields:**
- `id` (primary key)
- `business_id` (foreign key, required) - Associated business
- `payment_method` (string, required) - credit_card, ach, paypal, apple_pay, google_pay
- `is_enabled` (boolean, default: true) - Method availability
- `display_name` (string) - Custom display name
- `processing_fee_percentage` (decimal, default: 0) - Processing fee percentage
- `processing_fee_fixed` (decimal, default: 0) - Fixed processing fee
- `minimum_amount` (decimal) - Minimum transaction amount
- `maximum_amount` (decimal) - Maximum transaction amount
- `is_default` (boolean, default: false) - Default method flag
- `sort_order` (integer, default: 0) - Display order
- `configuration_data` (json) - Method-specific settings
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :business`
- `has_many :saved_payment_methods, dependent: :destroy`

### SavedPaymentMethod
Customer's saved payment methods for future use.

**Fields:**
- `id` (primary key)
- `customer_id` (foreign key, required) - Associated customer
- `payment_method_type` (string, required) - credit_card, ach, paypal
- `processor_customer_id` (string) - External processor customer ID
- `processor_payment_method_id` (string) - External payment method ID
- `display_name` (string) - Customer-friendly name
- `last_four_digits` (string) - Last 4 digits for cards
- `expiry_month` (integer) - Card expiry month
- `expiry_year` (integer) - Card expiry year
- `card_brand` (string) - visa, mastercard, amex, discover
- `is_default` (boolean, default: false) - Default payment method
- `is_active` (boolean, default: true) - Payment method status
- `verified_at` (timestamp) - Verification timestamp
- `last_used_at` (timestamp) - Last usage timestamp
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :customer`
- `has_many :payments, dependent: :nullify`

## Service Timeline & Event Models

### ServiceTimelineEvent
Individual events in customer service timeline.

**Fields:**
- `id` (primary key)
- `customer_id` (foreign key, required) - Associated customer
- `business_id` (foreign key, required) - Associated business
- `event_type` (string, required) - quote_request, quote_sent, quote_approved, appointment_scheduled, service_completed, payment_received, feedback_submitted
- `event_date` (datetime, required) - Event timestamp
- `title` (string, required) - Event title
- `description` (text) - Event description
- `related_id` (integer) - Related record ID (polymorphic)
- `related_type` (string) - Related record type (polymorphic)
- `metadata` (json) - Additional event data
- `is_milestone` (boolean, default: false) - Milestone event flag
- `milestone_type` (string) - first_service, anniversary, high_value, loyalty
- `display_priority` (integer, default: 0) - Display importance
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :customer`
- `belongs_to :business`
- `belongs_to :related, polymorphic: true, optional: true`

### ServiceMilestone
Predefined milestones for customer recognition.

**Fields:**
- `id` (primary key)
- `business_id` (foreign key, required) - Associated business
- `milestone_type` (string, required) - first_service, anniversary, spending_threshold, service_count
- `milestone_name` (string, required) - Milestone display name
- `description` (text) - Milestone description
- `trigger_condition` (json) - Conditions for milestone achievement
- `reward_type` (string) - discount, free_service, recognition, gift
- `reward_value` (decimal) - Reward amount/percentage
- `reward_description` (text) - Reward details
- `is_active` (boolean, default: true) - Milestone status
- `auto_apply` (boolean, default: false) - Automatic reward application
- `notification_enabled` (boolean, default: true) - Send milestone notifications
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :business`
- `has_many :customer_milestones, dependent: :destroy`

### CustomerMilestone
Achieved milestones for individual customers.

**Fields:**
- `id` (primary key)
- `customer_id` (foreign key, required) - Associated customer
- `service_milestone_id` (foreign key, required) - Achieved milestone
- `achieved_at` (timestamp, required) - Achievement timestamp
- `reward_applied` (boolean, default: false) - Reward application status
- `reward_applied_at` (timestamp) - Reward application time
- `notification_sent` (boolean, default: false) - Notification status
- `notification_sent_at` (timestamp) - Notification timestamp
- `milestone_value` (decimal) - Value that triggered milestone
- `notes` (text) - Achievement notes
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :customer`
- `belongs_to :service_milestone`

## Key Indexes

```sql
-- Quote and Request indexes
CREATE INDEX index_quote_requests_on_business_id ON quote_requests(business_id);
CREATE INDEX index_quote_requests_on_customer_email ON quote_requests(customer_email);
CREATE INDEX index_quote_requests_on_status ON quote_requests(status);
CREATE INDEX index_quote_requests_on_submitted_at ON quote_requests(submitted_at);

CREATE INDEX index_quotes_on_business_id ON quotes(business_id);
CREATE INDEX index_quotes_on_quote_request_id ON quotes(quote_request_id);
CREATE INDEX index_quotes_on_status ON quotes(status);
CREATE INDEX index_quotes_on_quote_number ON quotes(quote_number);

-- Customer indexes
CREATE INDEX index_customers_on_email ON customers(email);
CREATE INDEX index_customers_on_customer_type ON customers(customer_type);
CREATE INDEX index_customers_on_status ON customers(status);

-- Appointment indexes
CREATE INDEX index_appointments_on_business_id ON appointments(business_id);
CREATE INDEX index_appointments_on_customer_id ON appointments(customer_id);
CREATE INDEX index_appointments_on_scheduled_start ON appointments(scheduled_start);
CREATE INDEX index_appointments_on_status ON appointments(status);

-- Payment indexes
CREATE INDEX index_payments_on_business_id ON payments(business_id);
CREATE INDEX index_payments_on_customer_id ON payments(customer_id);
CREATE INDEX index_payments_on_status ON payments(status);
CREATE INDEX index_payments_on_payment_date ON payments(payment_date);

-- Service History indexes
CREATE INDEX index_service_histories_on_business_id ON service_histories(business_id);
CREATE INDEX index_service_histories_on_customer_id ON service_histories(customer_id);
CREATE INDEX index_service_histories_on_service_date ON service_histories(service_date);

-- Document indexes
CREATE INDEX index_documents_on_business_id ON documents(business_id);
CREATE INDEX index_documents_on_customer_id ON documents(customer_id);
CREATE INDEX index_documents_on_document_type ON documents(document_type);
CREATE INDEX index_documents_on_status ON documents(status);

-- Payment Schedule indexes
CREATE INDEX index_payment_schedules_on_quote_id ON payment_schedules(quote_id);
CREATE INDEX index_payment_schedules_on_customer_id ON payment_schedules(customer_id);
CREATE INDEX index_scheduled_payments_on_due_date ON scheduled_payments(due_date);
CREATE INDEX index_scheduled_payments_on_status ON scheduled_payments(status);

-- Digital Signature indexes
CREATE INDEX index_digital_signatures_on_document_id ON digital_signatures(document_id);
CREATE INDEX index_digital_signatures_on_signed_at ON digital_signatures(signed_at);

-- Calendar Integration indexes
CREATE INDEX index_calendar_integrations_on_customer_id ON calendar_integrations(customer_id);
CREATE INDEX index_calendar_events_on_appointment_id ON calendar_events(appointment_id);

-- Appointment Rescheduling indexes
CREATE INDEX index_appointment_reschedulings_on_appointment_id ON appointment_reschedulings(appointment_id);
CREATE INDEX index_appointment_reschedulings_on_customer_id ON appointment_reschedulings(customer_id);
CREATE INDEX index_appointment_reschedulings_on_status ON appointment_reschedulings(status);
CREATE INDEX index_rescheduling_policies_on_business_id ON rescheduling_policies(business_id);

-- Quote Approval Token indexes
CREATE INDEX index_quote_approval_tokens_on_quote_id ON quote_approval_tokens(quote_id);
CREATE INDEX index_quote_approval_tokens_on_token ON quote_approval_tokens(token);
CREATE INDEX index_quote_approval_tokens_on_expires_at ON quote_approval_tokens(expires_at);

-- Payment Method indexes
CREATE INDEX index_payment_method_configs_on_business_id ON payment_method_configurations(business_id);
CREATE INDEX index_saved_payment_methods_on_customer_id ON saved_payment_methods(customer_id);
CREATE INDEX index_saved_payment_methods_on_is_default ON saved_payment_methods(is_default);

-- Service Timeline indexes
CREATE INDEX index_service_timeline_events_on_customer_id ON service_timeline_events(customer_id);
CREATE INDEX index_service_timeline_events_on_event_date ON service_timeline_events(event_date);
CREATE INDEX index_service_timeline_events_on_event_type ON service_timeline_events(event_type);
CREATE INDEX index_customer_milestones_on_customer_id ON customer_milestones(customer_id);
CREATE INDEX index_customer_milestones_on_achieved_at ON customer_milestones(achieved_at);
```

## Foreign Key Constraints

```sql
-- Quote Request relationships
ALTER TABLE quote_requests ADD CONSTRAINT fk_quote_requests_business FOREIGN KEY (business_id) REFERENCES businesses(id);
ALTER TABLE quote_requests ADD CONSTRAINT fk_quote_requests_customer FOREIGN FOREIGN KEY (customer_id) REFERENCES customers(id);
ALTER TABLE quote_requests ADD CONSTRAINT fk_quote_requests_form_config FOREIGN KEY (form_configuration_id) REFERENCES form_configurations(id);

-- Quote relationships
ALTER TABLE quotes ADD CONSTRAINT fk_quotes_business FOREIGN KEY (business_id) REFERENCES businesses(id);
ALTER TABLE quotes ADD CONSTRAINT fk_quotes_quote_request FOREIGN KEY (quote_request_id) REFERENCES quote_requests(id);
ALTER TABLE quotes ADD CONSTRAINT fk_quotes_customer FOREIGN KEY (customer_id) REFERENCES customers(id);

-- Customer relationships
ALTER TABLE customers ADD CONSTRAINT fk_customers_user FOREIGN KEY (user_id) REFERENCES users(id);
ALTER TABLE customer_addresses ADD CONSTRAINT fk_customer_addresses_customer FOREIGN KEY (customer_id) REFERENCES customers(id);

-- Appointment relationships
ALTER TABLE appointments ADD CONSTRAINT fk_appointments_business FOREIGN KEY (business_id) REFERENCES businesses(id);
ALTER TABLE appointments ADD CONSTRAINT fk_appointments_customer FOREIGN KEY (customer_id) REFERENCES customers(id);
ALTER TABLE appointments ADD CONSTRAINT fk_appointments_quote FOREIGN KEY (quote_id) REFERENCES quotes(id);

-- Payment relationships
ALTER TABLE payments ADD CONSTRAINT fk_payments_business FOREIGN KEY (business_id) REFERENCES businesses(id);
ALTER TABLE payments ADD CONSTRAINT fk_payments_customer FOREIGN KEY (customer_id) REFERENCES customers(id);
ALTER TABLE payments ADD CONSTRAINT fk_payments_quote FOREIGN KEY (quote_id) REFERENCES quotes(id);

-- Service History relationships
ALTER TABLE service_histories ADD CONSTRAINT fk_service_histories_business FOREIGN KEY (business_id) REFERENCES businesses(id);
ALTER TABLE service_histories ADD CONSTRAINT fk_service_histories_customer FOREIGN KEY (customer_id) REFERENCES customers(id);
ALTER TABLE service_histories ADD CONSTRAINT fk_service_histories_appointment FOREIGN KEY (appointment_id) REFERENCES appointments(id);

-- Document relationships
ALTER TABLE documents ADD CONSTRAINT fk_documents_business FOREIGN KEY (business_id) REFERENCES businesses(id);
ALTER TABLE documents ADD CONSTRAINT fk_documents_customer FOREIGN KEY (customer_id) REFERENCES customers(id);
ALTER TABLE documents ADD CONSTRAINT fk_documents_quote FOREIGN KEY (quote_id) REFERENCES quotes(id);

-- Digital Signature relationships
ALTER TABLE digital_signatures ADD CONSTRAINT fk_digital_signatures_document FOREIGN KEY (document_id) REFERENCES documents(id);
ALTER TABLE digital_signatures ADD CONSTRAINT fk_digital_signatures_quote FOREIGN KEY (quote_id) REFERENCES quotes(id);

-- Payment Schedule relationships
ALTER TABLE payment_schedules ADD CONSTRAINT fk_payment_schedules_quote FOREIGN KEY (quote_id) REFERENCES quotes(id);
ALTER TABLE payment_schedules ADD CONSTRAINT fk_payment_schedules_customer FOREIGN KEY (customer_id) REFERENCES customers(id);
ALTER TABLE scheduled_payments ADD CONSTRAINT fk_scheduled_payments_schedule FOREIGN KEY (payment_schedule_id) REFERENCES payment_schedules(id);
ALTER TABLE scheduled_payments ADD CONSTRAINT fk_scheduled_payments_payment FOREIGN KEY (payment_id) REFERENCES payments(id);

-- Calendar Integration relationships
ALTER TABLE calendar_integrations ADD CONSTRAINT fk_calendar_integrations_customer FOREIGN KEY (customer_id) REFERENCES customers(id);
ALTER TABLE calendar_events ADD CONSTRAINT fk_calendar_events_integration FOREIGN KEY (calendar_integration_id) REFERENCES calendar_integrations(id);
ALTER TABLE calendar_events ADD CONSTRAINT fk_calendar_events_appointment FOREIGN KEY (appointment_id) REFERENCES appointments(id);

-- Appointment Rescheduling relationships
ALTER TABLE appointment_reschedulings ADD CONSTRAINT fk_appointment_reschedulings_appointment FOREIGN KEY (appointment_id) REFERENCES appointments(id);
ALTER TABLE appointment_reschedulings ADD CONSTRAINT fk_appointment_reschedulings_customer FOREIGN KEY (customer_id) REFERENCES customers(id);
ALTER TABLE appointment_reschedulings ADD CONSTRAINT fk_appointment_reschedulings_business FOREIGN KEY (business_id) REFERENCES businesses(id);
ALTER TABLE rescheduling_policies ADD CONSTRAINT fk_rescheduling_policies_business FOREIGN KEY (business_id) REFERENCES businesses(id);

-- Quote Approval Token relationships
ALTER TABLE quote_approval_tokens ADD CONSTRAINT fk_quote_approval_tokens_quote FOREIGN KEY (quote_id) REFERENCES quotes(id);

-- Payment Method relationships
ALTER TABLE payment_method_configurations ADD CONSTRAINT fk_payment_method_configs_business FOREIGN KEY (business_id) REFERENCES businesses(id);
ALTER TABLE saved_payment_methods ADD CONSTRAINT fk_saved_payment_methods_customer FOREIGN KEY (customer_id) REFERENCES customers(id);

-- Service Timeline relationships
ALTER TABLE service_timeline_events ADD CONSTRAINT fk_service_timeline_events_customer FOREIGN KEY (customer_id) REFERENCES customers(id);
ALTER TABLE service_timeline_events ADD CONSTRAINT fk_service_timeline_events_business FOREIGN KEY (business_id) REFERENCES businesses(id);
ALTER TABLE service_milestones ADD CONSTRAINT fk_service_milestones_business FOREIGN KEY (business_id) REFERENCES businesses(id);
ALTER TABLE customer_milestones ADD CONSTRAINT fk_customer_milestones_customer FOREIGN KEY (customer_id) REFERENCES customers(id);
ALTER TABLE customer_milestones ADD CONSTRAINT fk_customer_milestones_milestone FOREIGN KEY (service_milestone_id) REFERENCES service_milestones(id);
```
