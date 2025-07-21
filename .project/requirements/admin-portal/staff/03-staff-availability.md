# Feature: Staff Availability

## Overview
Enable staff members to set their availability schedules and business owners to view team availability for efficient appointment scheduling.

## User Stories
- As a staff member, I want to set my availability so appointments are only scheduled when I'm working
- As a business owner, I want to see staff availability so I can schedule appointments efficiently
- As a scheduler, I want to see who's available for specific time slots

## Tasks

### 1. Create StaffAvailability Model
**File**: `app/models/staff_availability.rb`

**Implementation Notes**:
```ruby
class StaffAvailability < ApplicationRecord
  belongs_to :business_user
  
  validates :day_of_week, presence: true, inclusion: { in: 0..6 }
  validates :start_time, presence: true, if: :is_available?
  validates :end_time, presence: true, if: :is_available?
  validate :end_time_after_start_time, if: :is_available?
  validate :no_overlapping_availability
  
  scope :for_day, ->(day) { where(day_of_week: day) }
  scope :available, -> { where(is_available: true) }
  scope :for_user, ->(user) { joins(:business_user).where(business_users: { user: user }) }
  
  enum day_of_week: {
    sunday: 0, monday: 1, tuesday: 2, wednesday: 3,
    thursday: 4, friday: 5, saturday: 6
  }
  
  def day_name
    Date::DAYNAMES[day_of_week]
  end
  
  def formatted_hours
    return "Not Available" unless is_available?
    "#{start_time.strftime('%I:%M %p')} - #{end_time.strftime('%I:%M %p')}"
  end
  
  def time_range
    return nil unless is_available?
    start_time..end_time
  end
  
  def overlaps_with?(other_availability)
    return false unless is_available? && other_availability.is_available?
    return false unless day_of_week == other_availability.day_of_week
    
    time_range.overlaps?(other_availability.time_range)
  end
  
  private
  
  def end_time_after_start_time
    return unless start_time && end_time
    
    if end_time <= start_time
      errors.add(:end_time, "must be after start time")
    end
  end
  
  def no_overlapping_availability
    return unless business_user && day_of_week && is_available?
    
    overlapping = business_user.staff_availabilities
                              .where(day_of_week: day_of_week, is_available: true)
                              .where.not(id: id)
    
    overlapping.each do |other|
      if overlaps_with?(other)
        errors.add(:base, "Availability overlaps with existing schedule")
        break
      end
    end
  end
end
```

### 2. Create TimeOffRequest Model
**File**: `app/models/time_off_request.rb`

**Implementation Notes**:
```ruby
class TimeOffRequest < ApplicationRecord
  belongs_to :business_user
  belongs_to :approved_by, class_name: 'User', optional: true
  
  validates :start_date, presence: true
  validates :end_date, presence: true
  validates :reason, presence: true
  validate :end_date_after_start_date
  validate :future_dates_only, on: :create
  
  enum status: { pending: 0, approved: 1, denied: 2 }
  enum request_type: { vacation: 0, sick_leave: 1, personal: 2, other: 3 }
  
  scope :for_date_range, ->(start_date, end_date) {
    where('start_date <= ? AND end_date >= ?', end_date, start_date)
  }
  scope :approved_requests, -> { where(status: 'approved') }
  
  def duration_in_days
    (end_date - start_date).to_i + 1
  end
  
  def overlaps_with_date?(date)
    date >= start_date && date <= end_date
  end
  
  def can_be_modified_by?(user)
    business_user.user == user || business_user.business.business_users.find_by(user: user)&.can_manage_staff?
  end
  
  private
  
  def end_date_after_start_date
    return unless start_date && end_date
    
    if end_date < start_date
      errors.add(:end_date, "must be after start date")
    end
  end
  
  def future_dates_only
    return unless start_date
    
    if start_date <= Date.current
      errors.add(:start_date, "must be in the future")
    end
  end
end
```

### 3. Staff Availability Controller
**File**: `app/controllers/admin/staff_availabilities_controller.rb`

**Implementation Notes**:
```ruby
class Admin::StaffAvailabilitiesController < Admin::BaseController
  before_action :set_business
  before_action :set_business_user
  before_action :ensure_can_edit_availability
  before_action :ensure_availability_records_exist
  
  def edit
    @availabilities = @business_user.staff_availabilities.order(:day_of_week)
    @time_off_requests = @business_user.time_off_requests.includes(:approved_by).order(:start_date)
  end
  
  def update
    if update_availabilities
      redirect_to edit_admin_staff_availability_path(@business_user), 
                  notice: 'Availability updated successfully.'
    else
      @availabilities = @business_user.staff_availabilities.order(:day_of_week)
      render :edit, status: :unprocessable_entity
    end
  end
  
  def calendar
    @business_users = @business.business_users.active.includes(:user, :staff_availabilities)
    @date = params[:date]&.to_date || Date.current
    @start_date = @date.beginning_of_week
    @end_date = @date.end_of_week
  end
  
  private
  
  def set_business
    @business = current_user.owned_business || current_user.business
  end
  
  def set_business_user
    @business_user = @business.business_users.find(params[:id] || params[:staff_availability_id])
  end
  
  def ensure_can_edit_availability
    current_business_user = current_user.business_users.find_by(business: @business)
    
    unless @business_user.user == current_user || current_business_user&.can_manage_staff?
      redirect_to admin_dashboard_path, alert: 'Not authorized to edit this availability'
    end
  end
  
  def ensure_availability_records_exist
    (0..6).each do |day|
      @business_user.staff_availabilities.find_or_create_by(day_of_week: day) do |availability|
        # Default to business hours for weekdays
        if day.in?([1, 2, 3, 4, 5])
          business_hours = @business.business_hours.find_by(day_of_week: day)
          if business_hours&.is_open?
            availability.is_available = true
            availability.start_time = business_hours.open_time
            availability.end_time = business_hours.close_time
          end
        end
      end
    end
  end
  
  def update_availabilities
    success = true
    
    availability_params.each do |day_params|
      availability = @business_user.staff_availabilities.find_by(day_of_week: day_params[:day_of_week])
      success = false unless availability&.update(day_params.except(:day_of_week))
    end
    
    success
  end
  
  def availability_params
    params.require(:staff_availabilities).map do |_, availability_params|
      availability_params.permit(:day_of_week, :is_available, :start_time, :end_time)
    end
  end
end
```

### 4. Time Off Requests Controller
**File**: `app/controllers/admin/time_off_requests_controller.rb`

**Implementation Notes**:
```ruby
class Admin::TimeOffRequestsController < Admin::BaseController
  before_action :set_business
  before_action :set_business_user, only: [:index, :new, :create]
  before_action :set_time_off_request, only: [:show, :edit, :update, :destroy, :approve, :deny]
  
  def index
    @time_off_requests = if params[:staff_id]
      @business_user.time_off_requests.includes(:approved_by)
    else
      @business.time_off_requests.includes(:business_user, :approved_by)
    end.order(:start_date)
  end
  
  def new
    @time_off_request = @business_user.time_off_requests.build
  end
  
  def create
    @time_off_request = @business_user.time_off_requests.build(time_off_request_params)
    
    if @time_off_request.save
      notify_managers_of_request
      redirect_to admin_time_off_requests_path(staff_id: @business_user.id), 
                  notice: 'Time off request submitted successfully.'
    else
      render :new, status: :unprocessable_entity
    end
  end
  
  def approve
    if can_approve_request?
      @time_off_request.update!(status: 'approved', approved_by: current_user, approved_at: Time.current)
      notify_staff_of_decision('approved')
      redirect_to admin_time_off_requests_path, notice: 'Time off request approved.'
    else
      redirect_to admin_time_off_requests_path, alert: 'Not authorized to approve requests.'
    end
  end
  
  def deny
    if can_approve_request?
      @time_off_request.update!(status: 'denied', approved_by: current_user, approved_at: Time.current)
      notify_staff_of_decision('denied')
      redirect_to admin_time_off_requests_path, notice: 'Time off request denied.'
    else
      redirect_to admin_time_off_requests_path, alert: 'Not authorized to deny requests.'
    end
  end
  
  private
  
  def set_business
    @business = current_user.owned_business || current_user.business
  end
  
  def set_business_user
    @business_user = if params[:staff_id]
      @business.business_users.find(params[:staff_id])
    else
      current_user.business_users.find_by(business: @business)
    end
  end
  
  def set_time_off_request
    @time_off_request = @business.time_off_requests.find(params[:id])
  end
  
  def can_approve_request?
    current_business_user = current_user.business_users.find_by(business: @business)
    current_business_user&.can_manage_staff?
  end
  
  def time_off_request_params
    params.require(:time_off_request).permit(:start_date, :end_date, :request_type, :reason)
  end
  
  def notify_managers_of_request
    # Implementation would send notifications to managers
    Rails.logger.info "New time off request from #{@time_off_request.business_user.user.name}"
  end
  
  def notify_staff_of_decision(decision)
    # Implementation would send notification to staff member
    Rails.logger.info "Time off request #{decision} for #{@time_off_request.business_user.user.name}"
  end
end
```

### 5. Staff Availability Form View
**File**: `app/views/admin/staff_availabilities/edit.html.erb`

**Implementation Notes**:
```erb
<div class="max-w-4xl mx-auto py-8">
  <div class="flex justify-between items-center mb-6">
    <h1 class="text-2xl font-bold text-gray-900">
      Availability for <%= @business_user.user.name %>
    </h1>
    <%= link_to "View Team Calendar", calendar_admin_staff_availabilities_path,
                class: "bg-blue-600 hover:bg-blue-700 text-white font-medium py-2 px-4 rounded-md" %>
  </div>
  
  <!-- Weekly Availability -->
  <div class="bg-white shadow rounded-lg mb-6">
    <div class="px-6 py-4 border-b border-gray-200">
      <h2 class="text-lg font-medium text-gray-900">Weekly Availability</h2>
      <p class="text-sm text-gray-600">Set your available hours for each day of the week</p>
    </div>
    
    <%= form_with url: admin_staff_availability_path(@business_user), method: :patch, local: true, 
                  class: "p-6" do |form| %>
      
      <div class="space-y-4">
        <% @availabilities.each do |availability| %>
          <div class="flex items-center justify-between py-3 border-b border-gray-100">
            <div class="flex items-center space-x-4">
              <%= form.fields_for "staff_availabilities[#{availability.day_of_week}]", availability do |day_form| %>
                <%= day_form.hidden_field :day_of_week %>
                
                <div class="w-24">
                  <span class="text-sm font-medium text-gray-900"><%= availability.day_name %></span>
                </div>
                
                <div class="flex items-center space-x-2">
                  <%= day_form.check_box :is_available, 
                                        class: "rounded border-gray-300 text-blue-600 focus:ring-blue-500",
                                        data: { 
                                          action: "change->availability#toggleDay",
                                          availability_target: "checkbox"
                                        } %>
                  <label class="text-sm text-gray-700">Available</label>
                </div>
              <% end %>
            </div>
            
            <div class="flex items-center space-x-4" data-availability-target="timeFields">
              <%= form.fields_for "staff_availabilities[#{availability.day_of_week}]", availability do |day_form| %>
                <div class="<%= 'opacity-50' unless availability.is_available? %>">
                  <%= day_form.time_field :start_time, 
                                         disabled: !availability.is_available?,
                                         class: "border-gray-300 rounded-md text-sm focus:ring-blue-500 focus:border-blue-500" %>
                </div>
                
                <span class="text-gray-500 text-sm">to</span>
                
                <div class="<%= 'opacity-50' unless availability.is_available? %>">
                  <%= day_form.time_field :end_time, 
                                         disabled: !availability.is_available?,
                                         class: "border-gray-300 rounded-md text-sm focus:ring-blue-500 focus:border-blue-500" %>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
      
      <div class="mt-6 flex justify-end">
        <%= form.submit "Save Availability", 
                        class: "bg-blue-600 hover:bg-blue-700 text-white font-medium py-2 px-4 rounded-md focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500" %>
      </div>
    <% end %>
  </div>
  
  <!-- Time Off Requests -->
  <div class="bg-white shadow rounded-lg">
    <div class="px-6 py-4 border-b border-gray-200 flex justify-between items-center">
      <div>
        <h2 class="text-lg font-medium text-gray-900">Time Off Requests</h2>
        <p class="text-sm text-gray-600">Manage upcoming time off</p>
      </div>
      <%= link_to "Request Time Off", new_admin_time_off_request_path(staff_id: @business_user.id),
                  class: "bg-green-600 hover:bg-green-700 text-white font-medium py-2 px-4 rounded-md text-sm" %>
    </div>
    
    <div class="p-6">
      <% if @time_off_requests.any? %>
        <div class="space-y-4">
          <% @time_off_requests.each do |request| %>
            <div class="border border-gray-200 rounded-lg p-4">
              <div class="flex justify-between items-start">
                <div>
                  <h3 class="text-sm font-medium text-gray-900">
                    <%= request.request_type.titleize %> - <%= request.duration_in_days %> days
                  </h3>
                  <p class="text-sm text-gray-600 mt-1">
                    <%= request.start_date.strftime("%B %d") %> - <%= request.end_date.strftime("%B %d, %Y") %>
                  </p>
                  <p class="text-sm text-gray-500 mt-2"><%= request.reason %></p>
                </div>
                <div class="text-right">
                  <span class="inline-flex px-2 py-1 text-xs font-semibold rounded-full 
                    <%= case request.status
                        when 'pending' then 'bg-yellow-100 text-yellow-800'
                        when 'approved' then 'bg-green-100 text-green-800'
                        when 'denied' then 'bg-red-100 text-red-800'
                        end %>">
                    <%= request.status.titleize %>
                  </span>
                  <% if request.approved_by %>
                    <p class="text-xs text-gray-500 mt-1">
                      by <%= request.approved_by.name %>
                    </p>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      <% else %>
        <p class="text-gray-500 text-center py-8">No time off requests</p>
      <% end %>
    </div>
  </div>
</div>

<script data-turbo-track="reload">
  // Stimulus controller for availability toggles
  class AvailabilityController extends Stimulus.Controller {
    static targets = ["checkbox", "timeFields"]
    
    toggleDay(event) {
      const isChecked = event.target.checked
      const timeFields = event.target.closest('.flex').querySelector('[data-availability-target="timeFields"]')
      const inputs = timeFields.querySelectorAll('input[type="time"]')
      
      inputs.forEach(input => {
        input.disabled = !isChecked
      })
      
      if (isChecked) {
        timeFields.classList.remove('opacity-50')
      } else {
        timeFields.classList.add('opacity-50')
      }
    }
  }
  
  Stimulus.register("availability", AvailabilityController)
</script>
```

## Acceptance Criteria
- [ ] Staff can set available hours for each day of the week
- [ ] Time validation ensures end time is after start time
- [ ] Overlapping availability slots are prevented
- [ ] Time off requests can be submitted and managed
- [ ] Managers can approve/deny time off requests
- [ ] Calendar view shows team availability at a glance

## Testing Requirements
- Model validations for availability and time off
- Overlap detection tests
- Controller tests for availability updates
- Authorization tests for time off management
- System tests for availability form interactions
