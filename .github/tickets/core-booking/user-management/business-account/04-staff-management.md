# Implementation Task: Staff Management Interface

## Overview
Create the interface and underlying functionality for managing staff members, including invitations, roles, and permissions.

## Technical Design

### Models
```ruby
class StaffInvitation < ApplicationRecord
  belongs_to :business
  belongs_to :inviter, class_name: 'User'
  
  has_secure_token :invitation_token
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  
  scope :pending, -> { where(accepted_at: nil).where('expires_at > ?', Time.current) }
end

class StaffMember < ApplicationRecord
  belongs_to :business
  belongs_to :user
  has_many :staff_roles
  has_many :roles, through: :staff_roles
  
  validates :status, inclusion: { in: %w[active inactive suspended] }
end
```

### Service Objects
```ruby
class StaffManagementService
  def self.invite_staff(business, params, inviter)
    Business.transaction do
      # Create invitation
      # Set up initial role
      # Send invitation email
    end
  end
  
  def self.process_invitation(token, user_params)
    StaffInvitation.transaction do
      # Validate token
      # Create or update user
      # Create staff member
      # Assign initial role
    end
  end
end
```

### Controllers
```ruby
class Business::StaffController < BusinessController
  def index
    @staff_members = @business.staff_members.includes(:user, :roles)
    @pending_invitations = @business.staff_invitations.pending
  end
  
  def invite
    result = StaffManagementService.invite_staff(@business, staff_params, current_user)
    # Handle result
  end
  
  def update_status
    @staff_member = @business.staff_members.find(params[:id])
    # Update status with audit trail
  end
end
```

### Background Jobs
```ruby
class StaffInvitationReminderJob < ApplicationJob
  def perform(invitation_id)
    # Send reminder for pending invitations
    # Track reminder count
  end
end
```

## Views
1. Staff List
   - Active staff table
   - Pending invitations
   - Quick actions

2. Staff Invite Form
   - Email input
   - Role selection
   - Custom message

3. Staff Member Detail
   - Profile information
   - Role management
   - Activity history

## API Endpoints
```ruby
# POST /api/v1/business/staff/invite
{
  "email": "string",
  "role_ids": ["uuid"],
  "message": "string"
}

# PATCH /api/v1/business/staff/:id/status
{
  "status": "active|inactive|suspended",
  "reason": "string"
}
```

## Testing Strategy
1. Model Tests
   - Invitation token generation
   - Status transitions
   - Role assignments

2. Service Tests
   - Invitation process
   - Status updates
   - Role management

3. Integration Tests
   - Complete invitation flow
   - Staff management workflow
   - Permission enforcement

## Security Considerations
- Invitation token security
- Role-based access control
- Audit logging
- Rate limiting invitations
- Staff data privacy

## Estimated Hours: 24

## Dependencies
- Core Models implementation
- Role Management system
- Email service configuration
