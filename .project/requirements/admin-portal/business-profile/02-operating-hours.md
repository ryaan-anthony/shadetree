# Feature: Operating Hours Management

## Description
Flexible business hours configuration system that allows businesses to set regular operating hours, holiday schedules, special availability periods, and temporary closures with automatic customer communication.

## User Stories
- As a business owner, I want to set my regular operating hours so customers know when I'm available
- As a business owner, I want to configure holiday schedules so the system blocks unavailable dates
- As a business owner, I want to set special hours for events so customers can book during extended times
- As a business owner, I want to temporarily close my business so no bookings are accepted

## Tasks

### Task 1: Create Operating Hours Models
**Implementation Notes:**
- Create models for regular hours, holiday schedules, and special hours
- Support recurring patterns and exception handling
- Include timezone support for multi-location businesses

```ruby
# app/models/operating_hours.rb
class OperatingHours < ApplicationRecord
  belongs_to :business
  
  validates :day_of_week, presence: true, inclusion: { in: 0..6 }
  validates :open_time, :close_time, presence: true
  validate :close_time_after_open_time
  validate :no_overlapping_hours
  
  enum day_of_week: {
    sunday: 0,
    monday: 1,
    tuesday: 2,
    wednesday: 3,
    thursday: 4,
    friday: 5,
    saturday: 6
  }
  
  scope :for_day, ->(day) { where(day_of_week: day) }
  scope :active, -> { where(active: true) }
  
  def self.for_date(date)
    day = date.wday
    active.for_day(day)
  end
  
  def duration_minutes
    ((close_time - open_time) / 1.minute).to_i
  end
  
  def formatted_hours
    "#{open_time.strftime('%I:%M %p')} - #{close_time.strftime('%I:%M %p')}"
  end
  
  private
  
  def close_time_after_open_time
    return unless open_time && close_time
    
    if close_time <= open_time
      errors.add(:close_time, 'must be after open time')
    end
  end
  
  def no_overlapping_hours
    return unless business && day_of_week && open_time && close_time
    
    overlapping = business.operating_hours
                         .where(day_of_week: day_of_week)
                         .where.not(id: id)
                         .where(active: true)
                         .where(
                           '(open_time < ? AND close_time > ?) OR (open_time < ? AND close_time > ?)',
                           close_time, open_time, open_time, close_time
                         )
    
    if overlapping.exists?
      errors.add(:base, 'Operating hours cannot overlap with existing hours')
    end
  end
end

# app/models/holiday_schedule.rb
class HolidaySchedule < ApplicationRecord
  belongs_to :business
  
  validates :name, presence: true
  validates :date, presence: true, uniqueness: { scope: :business_id }
  validates :closure_type, presence: true
  
  enum closure_type: {
    full_day_closed: 0,
    partial_day: 1,
    special_hours: 2
  }
  
  scope :for_date, ->(date) { where(date: date) }
  scope :upcoming, -> { where('date >= ?', Date.current) }
  scope :active, -> { where(active: true) }
  
  def affects_date?(check_date)
    return false unless active?
    
    case recurrence_type
    when 'none'
      date == check_date
    when 'yearly'
      date.month == check_date.month && date.day == check_date.day
    else
      false
    end
  end
  
  def formatted_date
    date.strftime('%B %d, %Y')
  end
end

# app/models/special_hours.rb
class SpecialHours < ApplicationRecord
  belongs_to :business
  
  validates :name, presence: true
  validates :start_date, :end_date, presence: true
  validates :open_time, :close_time, presence: true
  validate :end_date_after_start_date
  validate :close_time_after_open_time
  
  scope :active, -> { where(active: true) }
  scope :for_date_range, ->(start_date, end_date) {
    where('start_date <= ? AND end_date >= ?', end_date, start_date)
  }
  
  def covers_date?(check_date)
    active? && check_date >= start_date && check_date <= end_date
  end
  
  def formatted_duration
    if start_date == end_date
      "#{start_date.strftime('%B %d, %Y')}"
    else
      "#{start_date.strftime('%B %d')} - #{end_date.strftime('%B %d, %Y')}"
    end
  end
  
  private
  
  def end_date_after_start_date
    return unless start_date && end_date
    
    if end_date < start_date
      errors.add(:end_date, 'must be after start date')
    end
  end
  
  def close_time_after_open_time
    return unless open_time && close_time
    
    if close_time <= open_time
      errors.add(:close_time, 'must be after open time')
    end
  end
end

# Migrations
# rails g model OperatingHours business:references day_of_week:integer open_time:time close_time:time active:boolean
class CreateOperatingHours < ActiveRecord::Migration[8.0]
  def change
    create_table :operating_hours do |t|
      t.references :business, null: false, foreign_key: true
      t.integer :day_of_week, null: false
      t.time :open_time, null: false
      t.time :close_time, null: false
      t.boolean :active, default: true
      t.timestamps
    end
    
    add_index :operating_hours, [:business_id, :day_of_week]
  end
end

# rails g model HolidaySchedule business:references name:string date:date closure_type:integer open_time:time close_time:time recurrence_type:string active:boolean
class CreateHolidaySchedules < ActiveRecord::Migration[8.0]
  def change
    create_table :holiday_schedules do |t|
      t.references :business, null: false, foreign_key: true
      t.string :name, null: false
      t.date :date, null: false
      t.integer :closure_type, default: 0
      t.time :open_time
      t.time :close_time
      t.string :recurrence_type, default: 'none'
      t.boolean :active, default: true
      t.text :description
      t.timestamps
    end
    
    add_index :holiday_schedules, [:business_id, :date]
  end
end

# rails g model SpecialHours business:references name:string start_date:date end_date:date open_time:time close_time:time active:boolean
class CreateSpecialHours < ActiveRecord::Migration[8.0]
  def change
    create_table :special_hours do |t|
      t.references :business, null: false, foreign_key: true
      t.string :name, null: false
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.time :open_time, null: false
      t.time :close_time, null: false
      t.boolean :active, default: true
      t.text :description
      t.timestamps
    end
    
    add_index :special_hours, [:business_id, :start_date, :end_date]
  end
end
```

### Task 2: Create Business Hours Service
**Implementation Notes:**
- Service to determine if business is open at any given time
- Handle complex logic for holidays, special hours, and regular schedules
- Provide availability checking for booking system

```ruby
# app/services/admin/business_hours_service.rb
class Admin::BusinessHoursService
  attr_reader :business

  def initialize(business)
    @business = business
  end

  def open_on_date?(date)
    return false if closed_for_holiday?(date)
    
    special_hours = special_hours_for_date(date)
    return true if special_hours.present?
    
    regular_hours_for_date(date).present?
  end

  def hours_for_date(date)
    # Check for holidays first
    holiday = holiday_schedule_for_date(date)
    return holiday_hours(holiday) if holiday

    # Check for special hours
    special_hours = special_hours_for_date(date)
    return format_hours(special_hours.open_time, special_hours.close_time) if special_hours

    # Use regular operating hours
    regular_hours = regular_hours_for_date(date)
    return format_hours(regular_hours.open_time, regular_hours.close_time) if regular_hours

    'Closed'
  end

  def next_opening_time(from_datetime = Time.current)
    (0..13).each do |days_ahead|
      check_date = from_datetime.to_date + days_ahead.days
      
      if open_on_date?(check_date)
        hours = hours_for_date(check_date)
        next if hours == 'Closed'
        
        open_time = parse_opening_time(check_date, hours)
        return open_time if open_time > from_datetime
      end
    end
    
    nil # No opening found in next 2 weeks
  end

  def available_times_for_date(date, duration_minutes = 60)
    return [] unless open_on_date?(date)
    
    hours = hours_for_date(date)
    return [] if hours == 'Closed'
    
    open_time, close_time = parse_hours_range(hours)
    generate_time_slots(date, open_time, close_time, duration_minutes)
  end

  def weekly_schedule
    (0..6).map do |day_of_week|
      date = Date.current.beginning_of_week + day_of_week.days
      {
        day: Date::DAYNAMES[day_of_week],
        date: date,
        hours: hours_for_date(date),
        is_open: open_on_date?(date)
      }
    end
  end

  private

  def closed_for_holiday?(date)
    holiday = holiday_schedule_for_date(date)
    holiday&.full_day_closed?
  end

  def holiday_schedule_for_date(date)
    business.holiday_schedules.active.find { |h| h.affects_date?(date) }
  end

  def special_hours_for_date(date)
    business.special_hours.active.find { |sh| sh.covers_date?(date) }
  end

  def regular_hours_for_date(date)
    business.operating_hours.active.for_day(date.wday).first
  end

  def holiday_hours(holiday)
    case holiday.closure_type
    when 'full_day_closed'
      'Closed'
    when 'special_hours'
      format_hours(holiday.open_time, holiday.close_time)
    else
      'Closed'
    end
  end

  def format_hours(open_time, close_time)
    "#{open_time.strftime('%I:%M %p')} - #{close_time.strftime('%I:%M %p')}"
  end

  def parse_hours_range(hours_string)
    return [nil, nil] if hours_string == 'Closed'
    
    times = hours_string.split(' - ')
    [Time.parse(times[0]), Time.parse(times[1])]
  end

  def parse_opening_time(date, hours_string)
    open_time_str = hours_string.split(' - ').first
    Time.zone.parse("#{date} #{open_time_str}")
  end

  def generate_time_slots(date, open_time, close_time, duration_minutes)
    slots = []
    current_time = Time.zone.parse("#{date} #{open_time.strftime('%H:%M')}")
    end_time = Time.zone.parse("#{date} #{close_time.strftime('%H:%M')}")
    
    while current_time + duration_minutes.minutes <= end_time
      slots << current_time
      current_time += duration_minutes.minutes
    end
    
    slots
  end
end
```

### Task 3: Create Operating Hours Controller
**Implementation Notes:**
- Handle CRUD operations for all types of hours
- Support bulk updates for weekly schedules
- Include preview functionality for schedule changes

```ruby
# app/controllers/admin/operating_hours_controller.rb
class Admin::OperatingHoursController < Admin::BaseController
  before_action :authenticate_admin!
  before_action :authorize_business_management!

  def index
    @business_hours_service = Admin::BusinessHoursService.new(current_admin.business)
    @weekly_schedule = @business_hours_service.weekly_schedule
    @operating_hours = current_admin.business.operating_hours.includes(:business)
    @holiday_schedules = current_admin.business.holiday_schedules.upcoming.limit(10)
    @special_hours = current_admin.business.special_hours.active.limit(10)
  end

  def edit_weekly
    @operating_hours = load_weekly_hours
  end

  def update_weekly
    ActiveRecord::Base.transaction do
      params[:operating_hours].each do |day, hours_params|
        day_num = Date::DAYNAMES.index(day.capitalize)
        next unless day_num
        
        operating_hour = current_admin.business.operating_hours
                                              .find_or_initialize_by(day_of_week: day_num)
        
        if hours_params[:active] == '1'
          operating_hour.assign_attributes(
            open_time: hours_params[:open_time],
            close_time: hours_params[:close_time],
            active: true
          )
        else
          operating_hour.active = false
        end
        
        operating_hour.save!
      end
      
      track_hours_update
      redirect_to admin_operating_hours_path, notice: 'Operating hours updated successfully'
    end
  rescue ActiveRecord::RecordInvalid => e
    @operating_hours = load_weekly_hours
    flash.now[:error] = "Error updating hours: #{e.message}"
    render :edit_weekly, status: :unprocessable_entity
  end

  def holidays
    @holiday_schedules = current_admin.business.holiday_schedules.order(:date)
    @holiday_schedule = HolidaySchedule.new
  end

  def create_holiday
    @holiday_schedule = current_admin.business.holiday_schedules.build(holiday_params)
    
    if @holiday_schedule.save
      track_holiday_creation
      redirect_to admin_operating_hours_holidays_path, notice: 'Holiday schedule created'
    else
      @holiday_schedules = current_admin.business.holiday_schedules.order(:date)
      render :holidays, status: :unprocessable_entity
    end
  end

  def special_hours
    @special_hours = current_admin.business.special_hours.order(:start_date)
    @special_hour = SpecialHours.new
  end

  def create_special_hours
    @special_hour = current_admin.business.special_hours.build(special_hours_params)
    
    if @special_hour.save
      track_special_hours_creation
      redirect_to admin_operating_hours_special_hours_path, notice: 'Special hours created'
    else
      @special_hours = current_admin.business.special_hours.order(:start_date)
      render :special_hours, status: :unprocessable_entity
    end
  end

  private

  def load_weekly_hours
    hours = {}
    (0..6).each do |day_num|
      day_name = Date::DAYNAMES[day_num].downcase
      operating_hour = current_admin.business.operating_hours.find_by(day_of_week: day_num)
      
      hours[day_name] = operating_hour || current_admin.business.operating_hours.build(
        day_of_week: day_num,
        open_time: Time.parse('9:00 AM'),
        close_time: Time.parse('5:00 PM'),
        active: false
      )
    end
    hours
  end

  def holiday_params
    params.require(:holiday_schedule).permit(:name, :date, :closure_type, :open_time, :close_time, :description, :recurrence_type)
  end

  def special_hours_params
    params.require(:special_hours).permit(:name, :start_date, :end_date, :open_time, :close_time, :description)
  end

  def track_hours_update
    Admin::ActivityTrackingService.new(current_admin.business)
                                  .track_business_setting_changed(
                                    'operating_hours',
                                    current_admin
                                  )
  end

  def track_holiday_creation
    Admin::ActivityTrackingService.new(current_admin.business)
                                  .track_system_event(
                                    'holiday_schedule_created',
                                    "Holiday schedule created: #{@holiday_schedule.name}",
                                    priority: 'normal'
                                  )
  end

  def track_special_hours_creation
    Admin::ActivityTrackingService.new(current_admin.business)
                                  .track_system_event(
                                    'special_hours_created',
                                    "Special hours created: #{@special_hour.name}",
                                    priority: 'normal'
                                  )
  end
end
```

### Task 4: Add Routes for Operating Hours
**Implementation Notes:**
- Add nested routes for hours management
- Include special actions for bulk updates

```ruby
# Add to config/routes.rb
namespace :admin do
  # ...existing routes...
  resources :operating_hours, only: [:index] do
    collection do
      get :edit_weekly
      patch :update_weekly
      get :holidays
      post :create_holiday, path: 'holidays'
      get :special_hours
      post :create_special_hours, path: 'special_hours'
    end
  end
end
```

## Acceptance Criteria
- [ ] Business owners can set different hours for each day of the week
- [ ] Holiday schedules automatically block unavailable dates
- [ ] Special hours override regular schedules during specified periods
- [ ] Time validation prevents invalid hour configurations
- [ ] Changes reflect immediately in customer booking interface
- [ ] Weekly schedule overview shows all current settings

## Testing Requirements
- Unit tests for all time calculation logic
- Integration tests for schedule override precedence
- Validation tests for time range conflicts
- Service tests for availability checking
- Time zone handling verification
