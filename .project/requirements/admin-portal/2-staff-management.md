# Epic: Staff Management

## Overview
Provide business owners with essential staff management capabilities including invitations, role assignments, and availability scheduling. Focus on core team coordination features that directly support quote-to-payment workflow.

## Goals
- Enable quick team member onboarding (< 5 minutes per staff)
- Implement clear role-based access control
- Support staff availability scheduling for appointment booking
- Track essential staff activity for business operations
- Ensure secure team collaboration

## Success Metrics
- Staff invitation completion rate > 95%
- Average staff onboarding time < 5 minutes
- Role-based access violations = 0
- Staff availability accuracy > 90%
- Time to schedule staff appointment < 2 minutes

## User Stories
- As a business owner, I want to invite team members so they can help manage the business
- As a business owner, I want to set staff roles so team members have appropriate access
- As a staff member, I want to set my availability so I can receive appropriate appointment assignments
- As a business owner, I want to see staff activity so I can monitor business operations
- As a staff member, I want to access only the features relevant to my role

## Features

### MVP Phase (P0 - Critical Path)
1. [Staff Invitations](staff/01-staff-invitations.md) - Email invitations and account setup
2. [Role & Permission Management](staff/02-roles-permissions.md) - Basic role system with clear permissions

### Growth Phase (P1 - Early Value)
3. [Staff Availability](staff/03-staff-availability.md) - Weekly schedules and appointment availability

### Scale Phase (P2 - Advanced Features)
4. [Staff Activity Tracking](staff/04-activity-tracking.md) - Activity logs and performance insights

## Technical Architecture

### Core Models
```ruby
# MVP Models - simplified from existing
class User < ApplicationRecord
  has_many :business_users, dependent: :destroy
  has_many :businesses, through: :business_users
  
  validates :email, presence: true, uniqueness: true
  enum status: { pending: 0, active: 1, inactive: 2 }
end

class BusinessUser < ApplicationRecord
  belongs_to :business
  belongs_to :user
  
  validates :role, presence: true
  enum role: { owner: 0, admin: 1, staff: 2 }
  
  scope :active, -> { joins(:user).where(users: { status: 'active' }) }
end

# Growth Phase
class StaffAvailability < ApplicationRecord
  belongs_to :business_user
  
  validates :day_of_week, :start_time, :end_time, presence: true
  validates :day_of_week, inclusion: { in: 0..6 }
end
```

### Permission System
```ruby
# Simple role-based permissions for MVP
module Permissions
  ROLES = {
    owner: %w[manage_business manage_staff manage_services manage_quotes manage_billing],
    admin: %w[manage_staff manage_services manage_quotes view_reports],
    staff: %w[create_quotes view_quotes manage_appointments]
  }.freeze
  
  def can?(user, action, business)
    role = user.business_users.find_by(business: business)&.role
    ROLES[role.to_sym]&.include?(action.to_s)
  end
end
```

## Integration Points
- Business Profile (business-scoped teams)
- Service & Pricing (staff service assignments)
- Admin Dashboard (staff activity metrics)
- Quote Management (staff quote creation permissions)

## Security Considerations
- Validate business membership for all staff operations
- Secure invitation tokens with expiration
- Audit role changes and permission escalations
- Prevent staff from accessing other businesses' data

## MVP Scope Reduction
**Removed from MVP:**
- Complex role hierarchies or custom roles
- Advanced availability rules (holidays, time-off requests)
- Staff performance analytics
- Time tracking integration
- Staff communication tools

**Simplified for MVP:**
- Three basic roles only (owner, admin, staff)
- Simple email invitation flow
- Basic activity logging (creation/modification events only)
- Essential permissions for quote-to-payment workflow

## Phase Progression
- **MVP**: Basic invitations and role management
- **Growth**: Staff availability scheduling
- **Scale**: Advanced activity tracking and performance insights

## Dependencies
- User Authentication System (Devise)
- Email System (for invitations)
- Business Profile Management Epic

## Estimate
- MVP Features: 8 story points (1 week)
- Growth Features: 8 story points (1 week)  
- Scale Features: 5 story points (0.5 weeks)
- Total: 21 story points (2.5 weeks)
