# Feature: Staff Invitations

## Overview
Enable business owners to invite team members to join their business account via email invitations with role assignments.

## User Stories
- As a business owner, I want to invite staff members via email so they can access the system
- As a business owner, I want to set roles when inviting staff so permissions are configured correctly
- As an invited staff member, I want to easily accept invitations and set up my account

## Tasks

### 1. Create StaffInvitation Model
**File**: `app/models/staff_invitation.rb`

**Implementation Notes**:
```ruby
class StaffInvitation < ApplicationRecord
  belongs_to :business
  belongs_to :invited_by, class_name: 'User'
  
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :role, presence: true
  validates :token, presence: true, uniqueness: true
  validates :expires_at, presence: true
  
  enum status: { pending: 0, accepted: 1, expired: 2, cancelled: 3 }
  enum role: { staff: 0, manager: 1, admin: 2 }
  
  scope :active, -> { where(status: 'pending').where('expires_at > ?', Time.current) }
  scope :expired, -> { where('expires_at < ?', Time.current) }
  
  before_validation :generate_token, on: :create
  before_validation :set_expiration, on: :create
  
  def expired?
    expires_at < Time.current
  end
  
  def accept!(user)
    return false if expired? || !pending?
    
    transaction do
      # Create business user relationship
      business_user = business.business_users.create!(
        user: user,
        role: role,
        invited_by: invited_by,
        joined_at: Time.current
      )
      
      # Mark invitation as accepted
      update!(status: 'accepted', accepted_at: Time.current)
      
      business_user
    end
  end
  
  def send_invitation_email
    StaffInvitationMailer.invitation_email(self).deliver_later
  end
  
  private
  
  def generate_token
    self.token = SecureRandom.urlsafe_base64(32)
  end
  
  def set_expiration
    self.expires_at = 7.days.from_now
  end
end
```

### 2. Create BusinessUser Model
**File**: `app/models/business_user.rb`

**Implementation Notes**:
```ruby
class BusinessUser < ApplicationRecord
  belongs_to :business
  belongs_to :user
  belongs_to :invited_by, class_name: 'User', optional: true
  
  validates :role, presence: true
  validates :user_id, uniqueness: { scope: :business_id }
  
  enum role: { staff: 0, manager: 1, admin: 2, owner: 3 }
  
  scope :active, -> { where(is_active: true) }
  scope :by_role, ->(role) { where(role: role) }
  
  def can_manage_staff?
    admin? || owner?
  end
  
  def can_view_financials?
    manager? || admin? || owner?
  end
  
  def can_manage_business_settings?
    admin? || owner?
  end
end
```

### 3. Staff Invitations Controller
**File**: `app/controllers/admin/staff_invitations_controller.rb`

**Implementation Notes**:
```ruby
class Admin::StaffInvitationsController < Admin::BaseController
  before_action :set_business
  before_action :ensure_can_manage_staff
  before_action :set_invitation, only: [:show, :destroy, :resend]
  
  def index
    @pending_invitations = @business.staff_invitations.pending.includes(:invited_by)
    @staff_members = @business.business_users.active.includes(:user)
  end
  
  def new
    @invitation = @business.staff_invitations.build
  end
  
  def create
    @invitation = @business.staff_invitations.build(invitation_params)
    @invitation.invited_by = current_user
    
    if @invitation.save
      @invitation.send_invitation_email
      redirect_to admin_staff_invitations_path, 
                  notice: "Invitation sent to #{@invitation.email}"
    else
      render :new, status: :unprocessable_entity
    end
  end
  
  def destroy
    @invitation.update!(status: 'cancelled')
    redirect_to admin_staff_invitations_path, 
                notice: 'Invitation cancelled'
  end
  
  def resend
    if @invitation.pending? && !@invitation.expired?
      @invitation.send_invitation_email
      redirect_to admin_staff_invitations_path, 
                  notice: 'Invitation resent'
    else
      redirect_to admin_staff_invitations_path, 
                  alert: 'Cannot resend this invitation'
    end
  end
  
  private
  
  def set_business
    @business = current_user.owned_business || current_user.business
  end
  
  def ensure_can_manage_staff
    business_user = current_user.business_users.find_by(business: @business)
    redirect_to admin_dashboard_path unless business_user&.can_manage_staff?
  end
  
  def set_invitation
    @invitation = @business.staff_invitations.find(params[:id])
  end
  
  def invitation_params
    params.require(:staff_invitation).permit(:email, :role, :message)
  end
end
```

### 4. Invitation Acceptance Controller
**File**: `app/controllers/staff_invitations_controller.rb`

**Implementation Notes**:
```ruby
class StaffInvitationsController < ApplicationController
  before_action :set_invitation
  
  def show
    if @invitation.expired?
      render :expired
    elsif @invitation.accepted?
      render :already_accepted
    elsif current_user
      render :accept
    else
      redirect_to new_user_registration_path(invitation_token: @invitation.token)
    end
  end
  
  def accept
    if current_user && @invitation.pending? && !@invitation.expired?
      business_user = @invitation.accept!(current_user)
      
      if business_user
        redirect_to admin_dashboard_path, 
                    notice: "Welcome to #{@invitation.business.name}!"
      else
        redirect_to root_path, alert: 'Unable to accept invitation'
      end
    else
      redirect_to root_path, alert: 'Invalid or expired invitation'
    end
  end
  
  private
  
  def set_invitation
    @invitation = StaffInvitation.find_by!(token: params[:token])
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: 'Invalid invitation link'
  end
end
```

### 5. Staff Invitation Mailer
**File**: `app/mailers/staff_invitation_mailer.rb`

**Implementation Notes**:
```ruby
class StaffInvitationMailer < ApplicationMailer
  def invitation_email(invitation)
    @invitation = invitation
    @business = invitation.business
    @invited_by = invitation.invited_by
    @accept_url = staff_invitation_url(@invitation.token)
    
    mail(
      to: @invitation.email,
      subject: "You're invited to join #{@business.name} on Shadetree"
    )
  end
end
```

### 6. Staff Invitations Index View
**File**: `app/views/admin/staff_invitations/index.html.erb`

**Implementation Notes**:
```erb
<div class="max-w-6xl mx-auto py-8">
  <div class="flex justify-between items-center mb-6">
    <h1 class="text-2xl font-bold text-gray-900">Team Management</h1>
    <%= link_to "Invite Staff Member", new_admin_staff_invitation_path,
                class: "bg-blue-600 hover:bg-blue-700 text-white font-medium py-2 px-4 rounded-md" %>
  </div>
  
  <!-- Active Staff Members -->
  <div class="bg-white shadow rounded-lg mb-6">
    <div class="px-6 py-4 border-b border-gray-200">
      <h2 class="text-lg font-medium text-gray-900">Active Staff</h2>
    </div>
    
    <div class="overflow-x-auto">
      <table class="min-w-full divide-y divide-gray-200">
        <thead class="bg-gray-50">
          <tr>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Name</th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Email</th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Role</th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Joined</th>
            <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">Actions</th>
          </tr>
        </thead>
        <tbody class="bg-white divide-y divide-gray-200">
          <% @staff_members.each do |business_user| %>
            <tr>
              <td class="px-6 py-4 whitespace-nowrap">
                <div class="flex items-center">
                  <div class="h-8 w-8 rounded-full bg-gray-300 flex items-center justify-center">
                    <span class="text-sm font-medium text-gray-700">
                      <%= business_user.user.name.first.upcase %>
                    </span>
                  </div>
                  <div class="ml-3">
                    <div class="text-sm font-medium text-gray-900"><%= business_user.user.name %></div>
                  </div>
                </div>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                <%= business_user.user.email %>
              </td>
              <td class="px-6 py-4 whitespace-nowrap">
                <span class="inline-flex px-2 py-1 text-xs font-semibold rounded-full bg-green-100 text-green-800">
                  <%= business_user.role.titleize %>
                </span>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                <%= business_user.joined_at&.strftime("%B %d, %Y") || "Owner" %>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                <% unless business_user.owner? %>
                  <%= link_to "Edit", "#", class: "text-blue-600 hover:text-blue-900 mr-3" %>
                  <%= link_to "Remove", "#", class: "text-red-600 hover:text-red-900" %>
                <% end %>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
  </div>
  
  <!-- Pending Invitations -->
  <% if @pending_invitations.any? %>
    <div class="bg-white shadow rounded-lg">
      <div class="px-6 py-4 border-b border-gray-200">
        <h2 class="text-lg font-medium text-gray-900">Pending Invitations</h2>
      </div>
      
      <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Email</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Role</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Sent</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Expires</th>
              <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">Actions</th>
            </tr>
          </thead>
          <tbody class="bg-white divide-y divide-gray-200">
            <% @pending_invitations.each do |invitation| %>
              <tr>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  <%= invitation.email %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap">
                  <span class="inline-flex px-2 py-1 text-xs font-semibold rounded-full bg-yellow-100 text-yellow-800">
                    <%= invitation.role.titleize %>
                  </span>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  <%= invitation.created_at.strftime("%B %d, %Y") %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  <%= invitation.expires_at.strftime("%B %d, %Y") %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                  <%= link_to "Resend", resend_admin_staff_invitation_path(invitation), 
                              method: :patch, class: "text-blue-600 hover:text-blue-900 mr-3" %>
                  <%= link_to "Cancel", admin_staff_invitation_path(invitation), 
                              method: :delete, class: "text-red-600 hover:text-red-900",
                              confirm: "Are you sure you want to cancel this invitation?" %>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
  <% end %>
</div>
```

## Acceptance Criteria
- [ ] Business owners can invite staff via email with role selection
- [ ] Invitation emails are sent with secure tokens
- [ ] Invited users can accept invitations and join the business
- [ ] Invitations expire after 7 days
- [ ] Pending invitations can be resent or cancelled
- [ ] Role-based permissions are properly applied

## Testing Requirements
- Model tests for invitation lifecycle
- Email delivery tests
- Controller tests for invitation management
- System tests for invitation acceptance flow
