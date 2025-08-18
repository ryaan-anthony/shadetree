# Admin Portal Models & Database Schema

This document outlines the models, fields, and relationships required for the Shadetree admin portal based on the feature requirements.

## Core Business Models

### Business
Primary business entity containing core company information.

**Fields:**
- `id` (primary key)
- `name` (string, required) - Business name
- `timezone` (string) - Business timezone
- `email` (string, required) - Primary business email
- `phone` (string) - Primary business phone
- `website` (string) - Business website URL
- `currency` (string, default: 'USD') - Business currency
- `brand_color` (string, default: '#059669') - Primary brand color
- `logo_url` (string) - Business logo URL
- `active` (boolean, default: true) - Business status
- `owner_id` (foreign key to users) - Business owner
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :owner, class_name: 'User'`
- `has_many :users, dependent: :nullify`
- `has_many :locations, dependent: :destroy`
- `has_many :staff_members, dependent: :destroy`
- `has_many :services, dependent: :destroy`
- `has_many :service_categories, dependent: :destroy`

### User
User accounts for business owners, staff, and customers.

**Fields:**
- `id` (primary key)
- `email` (string, required, unique) - User email
- `encrypted_password` (string, required) - Encrypted password
- `first_name` (string) - First name
- `last_name` (string) - Last name
- `reset_password_token` (string)
- `reset_password_sent_at` (timestamp)
- `remember_created_at` (timestamp)
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :business, optional: true`
- `has_many :owned_businesses, class_name: 'Business', foreign_key: 'owner_id'`
- `has_one :staff_member, dependent: :destroy`

## Location & Service Area Models

### Location
Physical business locations and service points.

**Fields:**
- `id` (primary key)
- `business_id` (foreign key, required) - Associated business
- `name` (string, required) - Location name
- `timezone` (string) - Location timezone
- `address` (text, required) - Street address
- `city` (string, required) - City
- `state` (string, required) - State/Province
- `zip_code` (string, required) - Postal code
- `latitude` (decimal, precision: 10, scale: 6) - GPS latitude
- `longitude` (decimal, precision: 10, scale: 6) - GPS longitude
- `is_primary` (boolean, default: false) - Primary location flag
- `phone` (string) - Location-specific phone
- `email` (string) - Location-specific email
- `active` (boolean, default: true) - Location status
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :business`
- `has_many :service_areas, dependent: :destroy`
- `has_many :operating_hours, dependent: :destroy`
- `has_many :business_closures, dependent: :destroy`
- `has_many :special_availabilities, dependent: :destroy`
- `has_many :service_prices, dependent: :destroy`

### ServiceArea
Service delivery territories for each location.

**Fields:**
- `id` (primary key)
- `location_id` (foreign key, required) - Associated location
- `radius` (decimal) - Service radius in miles/km
- `active` (boolean, default: true) - Service area status
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :location`
- `has_many :service_area_restrictions, dependent: :destroy`

### ServiceAreaRestriction
Geographic exclusions within service areas.

**Fields:**
- `id` (primary key)
- `service_area_id` (foreign key, required) - Associated service area
- `restriction_type` (string, required) - 'city', 'state', 'zip_code'
- `city` (string) - Excluded city
- `state` (string) - Excluded state
- `zip_code` (string) - Excluded zip code
- `reason` (text) - Restriction reason
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :service_area`

### OperatingHours
Location-specific weekly operating hours.

**Fields:**
- `id` (primary key)
- `location_id` (foreign key, required) - Associated location
- `day_of_week` (integer, required) - 0-6 (Sunday-Saturday)
- `open_time` (time) - Opening time
- `close_time` (time) - Closing time
- `is_closed` (boolean, default: false) - Closed all day flag
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :location`

### BusinessClosure
Special closures and holiday schedules per location.

**Fields:**
- `id` (primary key)
- `location_id` (foreign key, required) - Associated location
- `date` (date, required) - Closure date
- `reason` (string, required) - Closure reason
- `is_full_day` (boolean, default: true) - Full day closure flag
- `modified_open_time` (time) - Modified opening time
- `modified_close_time` (time) - Modified closing time
- `is_recurring` (boolean, default: false) - Annual recurrence flag
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :location`

### SpecialAvailability
Extended hours and special availability windows per location.

**Fields:**
- `id` (primary key)
- `location_id` (foreign key, required) - Associated location
- `date` (date, required) - Special availability date
- `start_time` (time, required) - Start time
- `end_time` (time, required) - End time
- `reason` (string, required) - Availability reason
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :location`

## Staff Management Models

### StaffMember
Staff member profiles and information.

**Fields:**
- `id` (primary key)
- `business_id` (foreign key, required) - Associated business
- `user_id` (foreign key, required) - Associated user account
- `status` (string, default: 'active') - active, inactive, pending
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :business`
- `belongs_to :user`
- `has_many :staff_roles, dependent: :destroy`
- `has_many :roles, through: :staff_roles`
- `has_many :staff_availabilities, dependent: :destroy`
- `has_many :staff_service_assignments, dependent: :destroy`
- `has_many :services, through: :staff_service_assignments`

### BusinessRole
Business roles and permissions.

**Fields:**
- `id` (primary key)
- `business_id` (foreign key, required) - Associated business
- `name` (string, required) - Role name
- `description` (text) - Role description
- `permissions` (json) - Permission settings
- `is_default` (boolean, default: false) - Default role flag
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :business`
- `has_many :staff_roles, dependent: :destroy`
- `has_many :staff_members, through: :staff_roles`

### StaffRole
Join table for staff members and business roles.

**Fields:**
- `id` (primary key)
- `staff_member_id` (foreign key, required)
- `business_role_id` (foreign key, required)
- `assigned_at` (timestamp, default: current_time)
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :staff_member`
- `belongs_to :business_role`

### StaffAvailability
Staff scheduling availability.

**Fields:**
- `id` (primary key)
- `staff_member_id` (foreign key, required) - Associated staff member
- `day_of_week` (integer, required) - 0-6 (Sunday-Saturday)
- `start_time` (time, required) - Available start time
- `end_time` (time, required) - Available end time
- `location_id` (foreign key, optional) - Location assignment
- `is_available` (boolean, default: true) - Availability flag
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :staff_member`
- `belongs_to :location, optional: true`

## Service & Pricing Models

### ServiceCategory
Hierarchical service organization.

**Fields:**
- `id` (primary key)
- `business_id` (foreign key, required) - Associated business
- `name` (string, required) - Category name
- `description` (text) - Category description
- `parent_id` (foreign key, optional) - Parent category
- `sort_order` (integer, default: 0) - Display order
- `active` (boolean, default: true) - Category status
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :business`
- `belongs_to :parent, class_name: 'ServiceCategory', optional: true`
- `has_many :subcategories, class_name: 'ServiceCategory', foreign_key: 'parent_id'`
- `has_many :services, dependent: :destroy`

### Service
Individual services offered by the business.

**Fields:**
- `id` (primary key)
- `business_id` (foreign key, required) - Associated business
- `service_category_id` (foreign key, required) - Service category
- `name` (string, required) - Service name
- `description` (text) - Service description
- `duration` (integer, required) - Service duration in minutes
- `requires_location` (boolean, default: false) - Location requirement
- `is_active` (boolean, default: true) - Service status
- `sort_order` (integer, default: 0) - Display order
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :business`
- `belongs_to :service_category`
- `has_many :service_prices, dependent: :destroy`
- `has_many :service_taxes, dependent: :destroy`
- `has_many :service_fees, dependent: :destroy`
- `has_many :service_requirements, dependent: :destroy`
- `has_many :pricing_tiers, dependent: :destroy`
- `has_many :staff_service_assignments, dependent: :destroy`
- `has_many :staff_members, through: :staff_service_assignments`

### ServicePrice
Location-specific service pricing.

**Fields:**
- `id` (primary key)
- `service_id` (foreign key, required) - Associated service
- `location_id` (foreign key, required) - Associated location
- `base_price` (decimal, required) - Base service price
- `currency` (string, default: 'USD') - Price currency
- `effective_date` (date) - Price effective date
- `expires_date` (date) - Price expiration date
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :service`
- `belongs_to :location`

### ServiceTax
Tax configuration for services.

**Fields:**
- `id` (primary key)
- `service_id` (foreign key, required) - Associated service
- `tax_name` (string, required) - Tax name/type
- `tax_rate` (decimal, required) - Tax rate percentage
- `tax_type` (string, required) - 'percentage' or 'fixed'
- `is_inclusive` (boolean, default: false) - Tax inclusion flag
- `location_id` (foreign key, optional) - Location-specific tax
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :service`
- `belongs_to :location, optional: true`

### ServiceFee
Additional fees for services.

**Fields:**
- `id` (primary key)
- `service_id` (foreign key, required) - Associated service
- `fee_name` (string, required) - Fee name/type
- `fee_amount` (decimal, required) - Fee amount
- `fee_type` (string, required) - 'percentage' or 'fixed'
- `is_mandatory` (boolean, default: true) - Mandatory fee flag
- `location_id` (foreign key, optional) - Location-specific fee
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :service`
- `belongs_to :location, optional: true`

## Notification & Communication Models

### MessageTemplate
Pre-defined message templates for automated communications.

**Fields:**
- `id` (primary key)
- `business_id` (foreign key, required) - Associated business
- `name` (string, required) - Template name
- `event` (string, required) - booking, reminder, cancellation, payment, general
- `message_type` (string, required) - email, sms
- `subject` (string) - Email subject line
- `message_content` (text, required) - Template content with variables
- `variables_used` (json) - Variables available in template
- `is_active` (boolean, default: true) - Template status
- `usage_count` (integer, default: 0) - Times template used
- `last_used_at` (timestamp) - Last usage timestamp
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :business`
- `has_many :notification_triggers, dependent: :destroy`
- `has_many :sent_notifications, dependent: :destroy`

### NotificationTrigger
Automated triggers for sending notifications based on events.

**Fields:**
- `id` (primary key)
- `business_id` (foreign key, required) - Associated business
- `message_template_id` (foreign key, required) - Template to send
- `trigger_name` (string, required) - Trigger identifier
- `trigger_event` (string, required) - appointment_booked, payment_received, etc.
- `trigger_conditions` (json) - Conditions for trigger activation
- `timing_offset` (integer, default: 0) - Minutes after event
- `is_active` (boolean, default: true) - Trigger status
- `delivery_channels` (json) - Enabled channels (email, sms)
- `last_triggered_at` (timestamp) - Last trigger execution
- `trigger_count` (integer, default: 0) - Total trigger executions
- `created_at` (timestamp)
- `updated_at` (timestamp)

**Relationships:**
- `belongs_to :business`
- `belongs_to :message_template`
- `has_many :sent_notifications, dependent: :destroy`

### CustomerNotificationPreference
Customer preferences for receiving notifications.

**Fields:**
- `id` (primary key)
- `customer_id` (foreign key, required) - Associated customer
- `business_id` (foreign key, required) - Associated business
- `email_notifications` (boolean, default: true) - Email preference
- `sms_notifications` (boolean, default: true) - SMS preference
- `booking_confirmations` (boolean, default: true) - Booking notifications
- `appointment_reminders` (boolean, default: true) - Reminder notifications
- `payment_notifications` (boolean, default: true) - Payment notifications
- `promotional_messages` (boolean, default: false) - Marketing notifications
- `updated_at` (timestamp)
- `created_at` (timestamp)

**Relationships:**
- `belongs_to :customer`
- `belongs_to :business`
