# Feature: Staff Onboarding & Profile Management

## Description
Comprehensive staff member management system that handles the complete lifecycle of team members from invitation and onboarding through profile maintenance and offboarding.

## User Stories
- As a business owner, I want to invite new staff members so I can build my team
- As a new staff member, I want to complete my profile so I can start working
- As a manager, I want to view all staff information so I can coordinate effectively
- As a staff member, I want to update my profile so my information stays current

## Tasks

### Task 1: Create Staff Models
**Implementation Notes:**
- Create models for staff members, invitations, and profile information
- Include status tracking and profile completion workflow
- Support different employment types and relationships

```ruby
# app/models/staff_member.rb
class StaffMember < ApplicationRecord
  belongs_to :business
  belongs_to :user
  belongs_to :invited_by, class_name: 'User', optional: true
  
  has_many :staff_service_assignments, dependent: :destroy
  has_many :services, through: :staff_service_assignments
  has_many :staff_schedules, dependent: :destroy
  has_many :bookings, dependent: :nullify
  
  validates :employee_id, uniqueness: { scope: :business_id }, allow_blank: true
  validates :hire_date, presence: true
  validates :employment_type, presence: true
  validates :hourly_rate, numericality: { greater_than: 0 }, allow_blank: true
  
  enum status: {
    invited: 0,
    active: 1,
    inactive: 2,
    terminated: 3
  }
  
  enum employment_type: {
    employee: 0,
    contractor: 1,
    part_time: 2,
    intern: 3
  }
  
  scope :active_staff, -> { where(status: [:active]) }
  scope :available_staff, -> { active_staff.where(available: true) }
  
  delegate :name, :email, :phone, to: :user, prefix: false
  
  def full_name
    user.name
  end
  
  def profile_complete?
    required_fields_complete? && user.profile_complete?
  end
  
  def can_provide_service?(service)
    services.include?(service) && active? && available?
  end
  
  def current_workload
    # Calculate current booking load for capacity planning
    upcoming_bookings = bookings.where('scheduled_at > ?', Time.current).count
    total_hours_this_week = bookings.where(
      scheduled_at: Time.current.beginning_of_week..Time.current.end_of_week
    ).sum(:duration_minutes) / 60.0
    
    {
      upcoming_bookings: upcoming_bookings,
      hours_this_week: total_hours_this_week,
      capacity_percentage: calculate_capacity_percentage(total_hours_this_week)
    }
  end
  
  def earnings_summary(period = :current_month)
    case period
    when :current_month
      date_range = Date.current.beginning_of_month..Date.current.end_of_month
    when :last_month
      date_range = 1.month.ago.beginning_of_month..1.month.ago.end_of_month
    when :year_to_date
      date_range = Date.current.beginning_of_year..Date.current.end_of_year
    end
    
    completed_bookings = bookings.completed.where(scheduled_at: date_range)
    
    {
      total_bookings: completed_bookings.count,
      gross_revenue: completed_bookings.sum(:total_amount),
      commission_earned: calculate_commission(completed_bookings),
      hours_worked: completed_bookings.sum(:duration_minutes) / 60.0
    }
  end
  
  private
  
  def required_fields_complete?
    hire_date.present? && employment_type.present?
  end
  
  def calculate_capacity_percentage(hours_worked)
    return 0 unless max_hours_per_week.present? && max_hours_per_week > 0
    (hours_worked / max_hours_per_week * 100).round(1)
  end
  
  def calculate_commission(bookings)
    return 0 unless commission_rate.present?
    
    total_revenue = bookings.sum(:total_amount)
    (total_revenue * commission_rate / 100.0).round(2)
  end
end

# app/models/staff_invitation.rb
class StaffInvitation < ApplicationRecord
  belongs_to :business
  belongs_to :invited_by, class_name: 'User'
  
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :role, presence: true
  validates :invitation_token, presence: true, uniqueness: true
  
  enum status: {
    pending: 0,
    accepted: 1,
    expired: 2,
    cancelled: 3
  }
  
  enum role: {
    staff: 0,
    manager: 1,
    admin: 2
  }
  
  before_create :generate_invitation_token
  before_create :set_expiration_date
  
  scope :valid, -> { where(status: :pending).where('expires_at > ?', Time.current) }
  
  def expired?
    expires_at < Time.current
  end
  
  def accept!(accepting_user)
    return false if expired? || !pending?
    
    transaction do
      # Create staff member record
      staff_member = business.staff_members.create!(
        user: accepting_user,
        invited_by: invited_by,
        hire_date: Date.current,
        employment_type: :employee,
        status: :active
      )
      
      # Assign role to user
      accepting_user.assign_role(role, business)
      
      # Update invitation status
      update!(status: :accepted, accepted_at: Time.current)
      
      staff_member
    end
  end
  
  private
  
  def generate_invitation_token
    self.invitation_token = SecureRandom.urlsafe_base64(32)
  end
  
  def set_expiration_date
    self.expires_at = 7.days.from_now
  end
end

# Migrations
# rails g model StaffMember business:references user:references employee_id:string hire_date:date employment_type:integer status:integer hourly_rate:decimal commission_rate:decimal max_hours_per_week:integer available:boolean
class CreateStaffMembers < ActiveRecord::Migration[8.0]
  def change
    create_table :staff_members do |t|
      t.references :business, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :invited_by, null: true, foreign_key: { to_table: :users }
      t.string :employee_id
      t.date :hire_date, null: false
      t.integer :employment_type, default: 0
      t.integer :status, default: 0
      t.decimal :hourly_rate, precision: 8, scale: 2
      t.decimal :commission_rate, precision: 5, scale: 2
      t.integer :max_hours_per_week, default: 40
      t.boolean :available, default: true
      t.text :bio
      t.text :specialties
      t.text :certifications
      t.date :termination_date
      t.text :notes
      t.timestamps
    end
    
    add_index :staff_members, [:business_id, :user_id], unique: true
    add_index :staff_members, [:business_id, :employee_id], unique: true
    add_index :staff_members, [:business_id, :status]
  end
end

# rails g model StaffInvitation business:references invited_by:references email:string role:integer status:integer invitation_token:string expires_at:datetime accepted_at:datetime
class CreateStaffInvitations < ActiveRecord::Migration[8.0]
  def change
    create_table :staff_invitations do |t|
      t.references :business, null: false, foreign_key: true
      t.references :invited_by, null: false, foreign_key: { to_table: :users }
      t.string :email, null: false
      t.integer :role, default: 0
      t.integer :status, default: 0
      t.string :invitation_token, null: false
      t.datetime :expires_at, null: false
      t.datetime :accepted_at
      t.text :welcome_message
      t.timestamps
    end
    
    add_index :staff_invitations, :invitation_token, unique: true
    add_index :staff_invitations, [:business_id, :email]
  end
end
```

### Task 2: Create Staff Management Service
**Implementation Notes:**
- Service for staff lifecycle management
- Handle invitation workflow and onboarding process
- Provide staff analytics and reporting

```ruby
# app/services/admin/staff_management_service.rb
class Admin::StaffManagementService
  attr_reader :business

  def initialize(business)
    @business = business
  end

  def invite_staff_member(email, role, invited_by, welcome_message = nil)
    # Check if user already exists
    existing_user = User.find_by(email: email)
    if existing_user&.staff_member_for(business)
      return { success: false, error: 'User is already a staff member' }
    end
    
    # Check for existing pending invitation
    existing_invitation = business.staff_invitations.valid.find_by(email: email)
    if existing_invitation
      return { success: false, error: 'Invitation already sent to this email' }
    end
    
    # Create invitation
    invitation = business.staff_invitations.create!(
      email: email,
      role: role,
      invited_by: invited_by,
      welcome_message: welcome_message
    )
    
    # Send invitation email
    StaffInvitationMailer.invitation_email(invitation).deliver_later
    
    { success: true, invitation: invitation }
  rescue ActiveRecord::RecordInvalid => e
    { success: false, error: e.message }
  end

  def accept_invitation(token, accepting_user)
    invitation = business.staff_invitations.valid.find_by(invitation_token: token)
    return { success: false, error: 'Invalid or expired invitation' } unless invitation
    
    if invitation.email != accepting_user.email
      return { success: false, error: 'Email mismatch' }
    end
    
    staff_member = invitation.accept!(accepting_user)
    
    # Send welcome email and trigger onboarding
    StaffWelcomeMailer.welcome_email(staff_member).deliver_later
    
    { success: true, staff_member: staff_member }
  rescue ActiveRecord::RecordInvalid => e
    { success: false, error: e.message }
  end

  def staff_analytics
    staff_members = business.staff_members.includes(:user)
    
    {
      total_staff: staff_members.count,
      active_staff: staff_members.active.count,
      staff_by_type: staff_members.group(:employment_type).count,
      pending_invitations: business.staff_invitations.valid.count,
      avg_tenure_months: calculate_average_tenure,
      capacity_utilization: calculate_capacity_utilization,
      top_performers: top_performing_staff(5)
    }
  end

  def staff_directory
    business.staff_members.active_staff.includes(:user, :services).map do |staff|
      {
        id: staff.id,
        name: staff.full_name,
        email: staff.email,
        role: staff.user.role_for(business),
        services: staff.services.pluck(:name),
        hire_date: staff.hire_date,
        available: staff.available?,
        profile_complete: staff.profile_complete?,
        workload: staff.current_workload
      }
    end
  end

  def onboarding_checklist(staff_member)
    checklist = [
      {
        task: 'Complete profile information',
        completed: staff_member.profile_complete?,
        required: true
      },
      {
        task: 'Set up service assignments',
        completed: staff_member.services.any?,
        required: true
      },
      {
        task: 'Configure availability schedule',
        completed: staff_member.staff_schedules.any?,
        required: true
      },
      {
        task: 'Review business policies',
        completed: staff_member.user.terms_accepted_at.present?,
        required: false
      }
    ]
    
    completion_rate = checklist.count { |item| item[:completed] }.to_f / checklist.size * 100
    
    {
      checklist: checklist,
      completion_rate: completion_rate.round(1),
      all_required_complete: checklist.select { |item| item[:required] }.all? { |item| item[:completed] }
    }
  end

  private

  def calculate_average_tenure
    active_staff = business.staff_members.active
    return 0 if active_staff.empty?
    
    total_months = active_staff.sum do |staff|
      ((Date.current - staff.hire_date) / 30).to_i
    end
    
    (total_months.to_f / active_staff.count).round(1)
  end

  def calculate_capacity_utilization
    staff_with_capacity = business.staff_members.active.where.not(max_hours_per_week: nil)
    return 0 if staff_with_capacity.empty?
    
    total_capacity = staff_with_capacity.sum(:max_hours_per_week)
    total_scheduled = staff_with_capacity.joins(:bookings)
                                        .where(bookings: { 
                                          scheduled_at: Time.current.beginning_of_week..Time.current.end_of_week 
                                        })
                                        .sum('bookings.duration_minutes') / 60.0
    
    return 0 if total_capacity.zero?
    (total_scheduled / total_capacity * 100).round(1)
  end

  def top_performing_staff(limit)
    # Calculate performance based on bookings and revenue
    business.staff_members.active
           .joins(:bookings)
           .where(bookings: { 
             scheduled_at: 1.month.ago..Time.current,
             status: 'completed'
           })
           .group('staff_members.id')
           .order('SUM(bookings.total_amount) DESC')
           .limit(limit)
           .includes(:user)
           .map do |staff|
      {
        name: staff.full_name,
        bookings_count: staff.bookings.completed.where(scheduled_at: 1.month.ago..Time.current).count,
        revenue_generated: staff.bookings.completed.where(scheduled_at: 1.month.ago..Time.current).sum(:total_amount)
      }
    end
  end
end
```

### Task 3: Create Staff Controllers
**Implementation Notes:**
- Controllers for staff CRUD operations and invitations
- Handle invitation acceptance and onboarding workflow
- Include staff directory and analytics views

```ruby
# app/controllers/admin/staff_members_controller.rb
class Admin::StaffMembersController < Admin::BaseController
  before_action :authenticate_admin!
  before_action :authorize_staff_management!
  before_action :set_staff_member, only: [:show, :edit, :update, :destroy, :toggle_availability]

  def index
    @staff_service = Admin::StaffManagementService.new(current_admin.business)
    @staff_directory = @staff_service.staff_directory
    @staff_analytics = @staff_service.staff_analytics
    @pending_invitations = current_admin.business.staff_invitations.valid.includes(:invited_by)
  end

  def show
    @staff_service = Admin::StaffManagementService.new(current_admin.business)
    @onboarding_status = @staff_service.onboarding_checklist(@staff_member)
    @earnings_summary = @staff_member.earnings_summary
    @workload = @staff_member.current_workload
  end

  def new
    @staff_member = current_admin.business.staff_members.build
    @staff_member.build_user if @staff_member.user.nil?
  end

  def create
    @staff_member = current_admin.business.staff_members.build(staff_member_params)
    
    if @staff_member.save
      track_staff_creation
      redirect_to admin_staff_member_path(@staff_member), notice: 'Staff member created successfully'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @staff_member.update(staff_member_params)
      track_staff_update
      redirect_to admin_staff_member_path(@staff_member), notice: 'Staff member updated successfully'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @staff_member.update!(status: :terminated, termination_date: Date.current)
    track_staff_termination
    redirect_to admin_staff_members_path, notice: 'Staff member deactivated successfully'
  end

  def toggle_availability
    @staff_member.toggle!(:available)
    track_availability_change
    redirect_to admin_staff_members_path, notice: "#{@staff_member.full_name} availability updated"
  end

  def bulk_update
    staff_ids = params[:staff_ids]
    action = params[:bulk_action]
    
    case action
    when 'activate'
      current_admin.business.staff_members.where(id: staff_ids).update_all(status: :active)
      message = 'Staff members activated'
    when 'deactivate'
      current_admin.business.staff_members.where(id: staff_ids).update_all(status: :inactive)
      message = 'Staff members deactivated'
    else
      message = 'Unknown action'
    end
    
    redirect_to admin_staff_members_path, notice: message
  end

  private

  def set_staff_member
    @staff_member = current_admin.business.staff_members.find(params[:id])
  end

  def staff_member_params
    params.require(:staff_member).permit(
      :employee_id, :hire_date, :employment_type, :hourly_rate, :commission_rate,
      :max_hours_per_week, :bio, :specialties, :certifications, :notes,
      user_attributes: [:name, :email, :phone, :id]
    )
  end

  def track_staff_creation
    Admin::ActivityTrackingService.new(current_admin.business)
                                  .track_system_event(
                                    'staff_member_created',
                                    "Staff member added: #{@staff_member.full_name}",
                                    priority: 'normal'
                                  )
  end

  def track_staff_update
    Admin::ActivityTrackingService.new(current_admin.business)
                                  .track_business_setting_changed(
                                    'staff_member',
                                    current_admin,
                                    @staff_member.changes
                                  )
  end

  def track_staff_termination
    Admin::ActivityTrackingService.new(current_admin.business)
                                  .track_system_event(
                                    'staff_member_terminated',
                                    "Staff member terminated: #{@staff_member.full_name}",
                                    priority: 'high'
                                  )
  end

  def track_availability_change
    status = @staff_member.available? ? 'available' : 'unavailable'
    Admin::ActivityTrackingService.new(current_admin.business)
                                  .track_system_event(
                                    'staff_availability_changed',
                                    "#{@staff_member.full_name} marked as #{status}",
                                    priority: 'normal'
                                  )
  end
end

# app/controllers/admin/staff_invitations_controller.rb
class Admin::StaffInvitationsController < Admin::BaseController
  before_action :authenticate_admin!
  before_action :authorize_staff_management!

  def create
    staff_service = Admin::StaffManagementService.new(current_admin.business)
    result = staff_service.invite_staff_member(
      invitation_params[:email],
      invitation_params[:role],
      current_admin,
      invitation_params[:welcome_message]
    )
    
    if result[:success]
      track_invitation_sent(result[:invitation])
      redirect_to admin_staff_members_path, notice: 'Invitation sent successfully'
    else
      redirect_to admin_staff_members_path, alert: result[:error]
    end
  end

  def resend
    invitation = current_admin.business.staff_invitations.valid.find(params[:id])
    StaffInvitationMailer.invitation_email(invitation).deliver_later
    
    track_invitation_resent(invitation)
    redirect_to admin_staff_members_path, notice: 'Invitation resent'
  end

  def cancel
    invitation = current_admin.business.staff_invitations.valid.find(params[:id])
    invitation.update!(status: :cancelled)
    
    track_invitation_cancelled(invitation)
    redirect_to admin_staff_members_path, notice: 'Invitation cancelled'
  end

  private

  def invitation_params
    params.require(:staff_invitation).permit(:email, :role, :welcome_message)
  end

  def track_invitation_sent(invitation)
    Admin::ActivityTrackingService.new(current_admin.business)
                                  .track_system_event(
                                    'staff_invitation_sent',
                                    "Staff invitation sent to #{invitation.email}",
                                    priority: 'normal'
                                  )
  end

  def track_invitation_resent(invitation)
    Admin::ActivityTrackingService.new(current_admin.business)
                                  .track_system_event(
                                    'staff_invitation_resent',
                                    "Staff invitation resent to #{invitation.email}",
                                    priority: 'normal'
                                  )
  end

  def track_invitation_cancelled(invitation)
    Admin::ActivityTrackingService.new(current_admin.business)
                                  .track_system_event(
                                    'staff_invitation_cancelled',
                                    "Staff invitation cancelled for #{invitation.email}",
                                    priority: 'normal'
                                  )
  end
end
```

### Task 4: Add Staff Routes
**Implementation Notes:**
- Add routes for staff management and invitations
- Include bulk operations and special actions

```ruby
# Add to config/routes.rb
namespace :admin do
  # ...existing routes...
  resources :staff_members do
    member do
      patch :toggle_availability
    end
    collection do
      patch :bulk_update
    end
  end
  
  resources :staff_invitations, only: [:create] do
    member do
      post :resend
      patch :cancel
    end
  end
end
```

## Acceptance Criteria
- [ ] Business owners can invite staff members via email
- [ ] Staff members can complete their profiles during onboarding
- [ ] Staff directory displays current team with relevant information
- [ ] Analytics provide insights into staff performance and capacity
- [ ] Invitation workflow handles acceptance and expiration properly
- [ ] Bulk operations allow efficient staff management

## Testing Requirements
- Unit tests for StaffMember and StaffInvitation models
- Service tests for invitation and onboarding workflows
- Integration tests for staff CRUD operations
- Email delivery testing for invitations and welcome messages
- Analytics calculation verification
