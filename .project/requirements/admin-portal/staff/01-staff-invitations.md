# Feature: Staff Invitations - MVP

## Overview
Enable business owners to invite team members to join their business account via simple email invitations with basic role assignments. Focus on essential team onboarding with minimal complexity.

## User Stories
- As a business owner, I want to invite staff members via email so they can access the system
- As a business owner, I want to assign one of three basic roles (Owner, Admin, Staff) when inviting
- As an invited staff member, I want to easily accept invitations and create my account

## MVP Scope
**Included:**
- Email invitation system with secure tokens
- Three basic roles only (Owner, Admin, Staff)
- Simple invitation acceptance flow
- Basic invitation management (resend, cancel)

**Excluded from MVP:**
- Complex role hierarchies or custom roles
- Invitation templates or customization
- Bulk invitation features
- Advanced permission granularity

## Tasks

### 1. Create Simplified StaffInvitation Model
**File**: `app/models/staff_invitation.rb`

**Implementation Notes**:
```ruby
class StaffInvitation < ApplicationRecord
  belongs_to :business
  belongs_to :invited_by, class_name: 'User'
  
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :email, uniqueness: { scope: :business_id, conditions: -> { where(status: 'pending') } }
  validates :role, presence: true
  validates :token, presence: true, uniqueness: true
  
  enum status: { pending: 0, accepted: 1, expired: 2, cancelled: 3 }
  enum role: { staff: 0, admin: 1 } # Owner role handled separately
  
  scope :active, -> { where(status: 'pending').where('expires_at > ?', Time.current) }
  
  before_validation :generate_token, on: :create
  before_validation :set_expiration, on: :create
  
  def expired?
    expires_at < Time.current
  end
  
  def accept!(user)
    return false if expired? || !pending?
    
    ActiveRecord::Base.transaction do
      # Create business user relationship
      business.business_users.create!(
        user: user,
        role: role
      )
      
      # Mark invitation as accepted
      update!(status: 'accepted')
    end
  end
  
  private
  
  def generate_token
    self.token = SecureRandom.urlsafe_base64(24)
  end
  
  def set_expiration
    self.expires_at = 7.days.from_now
  end
end
```

### 2. Simplified BusinessUser Model
**File**: `app/models/business_user.rb`

**Implementation Notes**:
```ruby
class BusinessUser < ApplicationRecord
  belongs_to :business
  belongs_to :user
  
  validates :role, presence: true
  validates :user_id, uniqueness: { scope: :business_id }
  
  enum role: { owner: 0, admin: 1, staff: 2 }
  
  scope :active, -> { where(active: true) }
  
  # Simple permission checks for MVP
  def can_manage_staff?
    owner? || admin?
  end
  
  def can_manage_services?
    owner? || admin?
  end
  
  def can_view_business_settings?
    owner? || admin?
  end
end
```

### 3. Create Invitation Controller
**File**: `app/controllers/admin/staff_invitations_controller.rb`

**Implementation Notes**:
```ruby
class Admin::StaffInvitationsController < Admin::BaseController
  before_action :ensure_can_manage_staff
  
  def index
    @invitations = current_business.staff_invitations
      .includes(:invited_by)
      .order(created_at: :desc)
    @team_members = current_business.business_users
      .includes(:user)
      .active
      .order(created_at: :desc)
  end
  
  def create
    @invitation = current_business.staff_invitations.build(invitation_params)
    @invitation.invited_by = current_user
    
    if @invitation.save
      StaffInvitationMailer.invitation_email(@invitation).deliver_later
      redirect_to admin_staff_path, notice: 'Invitation sent successfully'
    else
      redirect_to admin_staff_path, alert: @invitation.errors.full_messages.first
    end
  end
  
  def resend
    @invitation = current_business.staff_invitations.find(params[:id])
    
    if @invitation.pending?
      StaffInvitationMailer.invitation_email(@invitation).deliver_later
      redirect_to admin_staff_path, notice: 'Invitation resent'
    else
      redirect_to admin_staff_path, alert: 'Cannot resend this invitation'
    end
  end
  
  def cancel
    @invitation = current_business.staff_invitations.find(params[:id])
    @invitation.update!(status: 'cancelled')
    redirect_to admin_staff_path, notice: 'Invitation cancelled'
  end
  
  private
  
  def invitation_params
    params.require(:staff_invitation).permit(:email, :role)
  end
  
  def ensure_can_manage_staff
    unless current_business_user.can_manage_staff?
      redirect_to admin_dashboard_path, alert: 'Access denied'
    end
  end
end
```

### 4. Create Invitation Acceptance Controller
**File**: `app/controllers/invitations_controller.rb`

**Implementation Notes**:
```ruby
class InvitationsController < ApplicationController
  def show
    @invitation = StaffInvitation.find_by!(token: params[:token])
    
    if @invitation.expired?
      render :expired
    elsif @invitation.accepted?
      render :already_accepted
    else
      @user = User.new
    end
  end
  
  def accept
    @invitation = StaffInvitation.find_by!(token: params[:token])
    
    if @invitation.expired?
      redirect_to invitation_path(params[:token]), alert: 'This invitation has expired'
      return
    end
    
    # Check if user already exists
    user = User.find_by(email: @invitation.email)
    
    if user
      # Existing user - just add to business
      if @invitation.accept!(user)
        sign_in user
        redirect_to admin_dashboard_path, notice: 'Welcome to the team!'
      else
        redirect_to invitation_path(params[:token]), alert: 'Unable to accept invitation'
      end
    else
      # New user - create account and add to business
      user = User.new(user_params)
      user.email = @invitation.email
      
      if user.save && @invitation.accept!(user)
        sign_in user
        redirect_to admin_dashboard_path, notice: 'Account created! Welcome to the team!'
      else
        @user = user
        render :show
      end
    end
  end
  
  private
  
  def user_params
    params.require(:user).permit(:name, :password, :password_confirmation)
  end
end
```

### 5. Create Invitation Mailer
**File**: `app/mailers/staff_invitation_mailer.rb`

**Implementation Notes**:
```ruby
class StaffInvitationMailer < ApplicationMailer
  def invitation_email(invitation)
    @invitation = invitation
    @business = invitation.business
    @invite_url = invitation_url(invitation.token)
    
    mail(
      to: invitation.email,
      subject: "You're invited to join #{@business.name} on Shadetree"
    )
  end
end
```

### 6. Create Database Migration
**File**: `db/migrate/xxx_create_staff_invitations.rb`

**Implementation Notes**:
```ruby
class CreateStaffInvitations < ActiveRecord::Migration[8.0]
  def change
    create_table :staff_invitations do |t|
      t.references :business, null: false, foreign_key: true
      t.references :invited_by, null: false, foreign_key: { to_table: :users }
      t.string :email, null: false
      t.integer :role, null: false
      t.string :token, null: false
      t.integer :status, default: 0
      t.datetime :expires_at, null: false
      t.datetime :accepted_at
      
      t.timestamps
    end
    
    add_index :staff_invitations, :token, unique: true
    add_index :staff_invitations, [:business_id, :email]
    add_index :staff_invitations, [:business_id, :status]
  end
end
```

## Technical Requirements

### Security
- Secure token generation for invitations
- 7-day expiration on invitation links
- Email validation and uniqueness per business
- Basic authorization checks

### Email Template
```erb
<!-- app/views/staff_invitation_mailer/invitation_email.html.erb -->
<div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
  <div style="background: #2563eb; color: white; padding: 20px; text-align: center;">
    <h1><%= @business.name %></h1>
  </div>
  
  <div style="padding: 30px;">
    <h2>You're invited to join our team!</h2>
    
    <p>Hello,</p>
    
    <p><%= @invitation.invited_by.name %> has invited you to join <strong><%= @business.name %></strong> as a <strong><%= @invitation.role.humanize %></strong> on Shadetree.</p>
    
    <div style="text-align: center; margin: 30px 0;">
      <a href="<%= @invite_url %>" 
         style="background: #2563eb; 
                color: white; 
                padding: 15px 30px; 
                text-decoration: none; 
                border-radius: 5px; 
                display: inline-block;">
        Accept Invitation
      </a>
    </div>
    
    <p><small>This invitation expires in 7 days. If you have any questions, please contact <%= @invitation.invited_by.name %> directly.</small></p>
  </div>
</div>
```

## Acceptance Criteria
- Business owners can invite staff via email with role selection
- Invitations expire after 7 days
- Staff can accept invitations and create accounts or join existing accounts
- Invitation status is tracked (pending, accepted, expired, cancelled)
- Business owners can resend or cancel pending invitations
- Email notifications are sent automatically

## Estimate
- Story Points: 5
- Timeline: 3 days
- Dependencies: User authentication system, email configuration
