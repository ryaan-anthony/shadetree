# Feature: Calendar Integration (Google)

## Overview
Integrate Google Calendar to provide two-way synchronization of appointments, enabling staff to see their schedules across platforms and reducing double-booking conflicts.

## User Stories
- As a business owner, I want appointments to sync with Google Calendar so my team can see their schedules
- As a staff member, I want my work appointments in my personal calendar
- As a business owner, I want to avoid double-booking by checking calendar availability

## Tasks

### 1. Create GoogleCalendarIntegration Model
**File**: `app/models/google_calendar_integration.rb`

**Implementation Notes**:
```ruby
class GoogleCalendarIntegration < ApplicationRecord
  belongs_to :business
  belongs_to :user # The staff member whose calendar is connected
  
  validates :status, presence: true
  validates :user_id, uniqueness: { scope: :business_id }
  
  enum status: { disconnected: 0, connected: 1, error: 2 }
  
  # Encrypted credentials storage
  encrypts :access_token
  encrypts :refresh_token
  
  scope :active, -> { where(status: 'connected') }
  
  def google_auth_client
    client = Google::Auth::UserRefreshCredentials.new(
      client_id: Rails.application.credentials.google[:client_id],
      client_secret: Rails.application.credentials.google[:client_secret],
      scope: ['https://www.googleapis.com/auth/calendar'],
      access_token: access_token,
      refresh_token: refresh_token
    )
    
    # Refresh token if needed
    if client.expired?
      client.refresh!
      update!(access_token: client.access_token)
    end
    
    client
  end
  
  def calendar_service
    service = Google::Apis::CalendarV3::CalendarService.new
    service.authorization = google_auth_client
    service
  end
end
```

### 2. Create GoogleCalendarService
**File**: `app/services/google_calendar_service.rb`

**Implementation Notes**:
```ruby
class GoogleCalendarService
  def initialize(integration)
    @integration = integration
    @business = integration.business
    @calendar_service = integration.calendar_service
  end
  
  def sync_appointment(appointment, action)
    case action
    when 'created'
      create_calendar_event(appointment)
    when 'updated'
      update_calendar_event(appointment)
    when 'cancelled'
      delete_calendar_event(appointment)
    end
  rescue Google::Apis::Error => e
    Rails.logger.error "Google Calendar sync failed: #{e.message}"
    @integration.update!(status: :error, error_message: e.message)
  end
  
  def check_availability(start_time, end_time)
    return true unless @integration.connected?
    
    # Query calendar for conflicts
    events = @calendar_service.list_events(
      'primary',
      time_min: start_time.iso8601,
      time_max: end_time.iso8601,
      single_events: true,
      order_by: 'startTime'
    )
    
    # Check for overlapping events
    events.items.empty?
  end
  
  private
  
  def create_calendar_event(appointment)
    event = Google::Apis::CalendarV3::Event.new(
      summary: "#{@business.name} - #{appointment.title}",
      description: build_event_description(appointment),
      start: {
        date_time: appointment.scheduled_at.iso8601,
        time_zone: @business.timezone || 'UTC'
      },
      end: {
        date_time: (appointment.scheduled_at + appointment.duration.minutes).iso8601,
        time_zone: @business.timezone || 'UTC'
      },
      attendees: build_attendees_list(appointment),
      location: appointment.location,
      source: {
        title: 'Shadetree Platform',
        url: Rails.application.routes.url_helpers.admin_appointment_url(appointment)
      }
    )
    
    result = @calendar_service.insert_event('primary', event)
    appointment.update!(google_event_id: result.id)
    
    result
  end
  
  def update_calendar_event(appointment)
    return unless appointment.google_event_id
    
    event = @calendar_service.get_event('primary', appointment.google_event_id)
    
    event.summary = "#{@business.name} - #{appointment.title}"
    event.description = build_event_description(appointment)
    event.start.date_time = appointment.scheduled_at.iso8601
    event.end.date_time = (appointment.scheduled_at + appointment.duration.minutes).iso8601
    event.attendees = build_attendees_list(appointment)
    event.location = appointment.location
    
    @calendar_service.update_event('primary', appointment.google_event_id, event)
  end
  
  def delete_calendar_event(appointment)
    return unless appointment.google_event_id
    
    @calendar_service.delete_event('primary', appointment.google_event_id)
    appointment.update!(google_event_id: nil)
  end
  
  def build_event_description(appointment)
    description = []
    description << "Client: #{appointment.client.name}"
    description << "Phone: #{appointment.client.phone}" if appointment.client.phone
    description << "Email: #{appointment.client.email}"
    description << ""
    description << "Service: #{appointment.title}"
    description << "Notes: #{appointment.notes}" if appointment.notes.present?
    description << ""
    description << "Managed by Shadetree Platform"
    
    description.join("\n")
  end
  
  def build_attendees_list(appointment)
    attendees = []
    
    # Add client if they have an email
    if appointment.client.email.present?
      attendees << { email: appointment.client.email, display_name: appointment.client.name }
    end
    
    # Add assigned staff member
    if appointment.assigned_staff&.email.present?
      attendees << { 
        email: appointment.assigned_staff.email, 
        display_name: appointment.assigned_staff.name 
      }
    end
    
    attendees
  end
end
```

### 3. Create GoogleCalendarController
**File**: `app/controllers/admin/google_calendar_controller.rb`

**Implementation Notes**:
```ruby
class Admin::GoogleCalendarController < Admin::BaseController
  before_action :ensure_can_manage_integrations
  
  def show
    @integration = current_business.google_calendar_integrations
      .find_by(user: current_user)
    @available_staff = current_business.users
      .where(business_users: { role: ['admin', 'staff'] })
  end
  
  def connect
    # Google OAuth2 flow
    auth_client = build_auth_client
    
    authorization_uri = auth_client.authorization_uri(
      scope: ['https://www.googleapis.com/auth/calendar'],
      access_type: 'offline',
      approval_prompt: 'force',
      state: "#{current_business.id}:#{current_user.id}"
    )
    
    redirect_to authorization_uri.to_s, allow_other_host: true
  end
  
  def callback
    auth_code = params[:code]
    state_parts = params[:state].split(':')
    business_id = state_parts[0]
    user_id = state_parts[1]
    
    unless business_id == current_business.id.to_s
      redirect_to admin_integrations_path, alert: 'Invalid state parameter'
      return
    end
    
    auth_client = build_auth_client
    auth_client.code = auth_code
    
    begin
      auth_client.fetch_access_token!
      
      integration = current_business.google_calendar_integrations
        .find_or_initialize_by(user_id: user_id)
      
      integration.update!(
        access_token: auth_client.access_token,
        refresh_token: auth_client.refresh_token,
        expires_at: Time.at(auth_client.expires_at),
        status: :connected
      )
      
      redirect_to admin_google_calendar_path, notice: 'Google Calendar connected successfully'
    rescue => e
      Rails.logger.error "Google Calendar OAuth failed: #{e.message}"
      redirect_to admin_integrations_path, alert: 'Failed to connect Google Calendar'
    end
  end
  
  def disconnect
    integration = current_business.google_calendar_integrations
      .find_by(user: current_user)
    
    integration&.update!(status: :disconnected)
    
    redirect_to admin_integrations_path, notice: 'Google Calendar disconnected'
  end
  
  def sync_appointments
    integration = current_business.google_calendar_integrations
      .find_by(user: current_user)
    
    if integration&.connected?
      GoogleCalendarSyncJob.perform_later(integration.id)
      redirect_to admin_google_calendar_path, notice: 'Calendar sync started'
    else
      redirect_to admin_google_calendar_path, alert: 'Calendar not connected'
    end
  end
  
  private
  
  def build_auth_client
    Google::Auth::UserRefreshCredentials.new(
      client_id: Rails.application.credentials.google[:client_id],
      client_secret: Rails.application.credentials.google[:client_secret],
      redirect_uri: google_calendar_callback_url
    )
  end
  
  def ensure_can_manage_integrations
    unless current_business_user.can_manage_services?
      redirect_to admin_dashboard_path, alert: 'Access denied'
    end
  end
end
```

### 4. Create Calendar Sync Job
**File**: `app/jobs/google_calendar_sync_job.rb`

**Implementation Notes**:
```ruby
class GoogleCalendarSyncJob < ApplicationJob
  queue_as :integrations
  
  def perform(integration_id)
    integration = GoogleCalendarIntegration.find(integration_id)
    return unless integration.connected?
    
    service = GoogleCalendarService.new(integration)
    business = integration.business
    
    # Sync recent appointments (last 30 days and next 90 days)
    appointments = business.appointments
      .where(assigned_staff: integration.user)
      .where(scheduled_at: 30.days.ago..90.days.from_now)
      .where.not(status: 'cancelled')
    
    appointments.each do |appointment|
      begin
        if appointment.google_event_id.present?
          service.sync_appointment(appointment, 'updated')
        else
          service.sync_appointment(appointment, 'created')
        end
        
        sleep(0.1) # Rate limiting
      rescue => e
        Rails.logger.error "Failed to sync appointment #{appointment.id}: #{e.message}"
      end
    end
    
  rescue => e
    integration.update!(status: :error, error_message: e.message)
    Rails.logger.error "Google Calendar sync failed: #{e.message}"
  end
end
```

### 5. Create Database Migration
**File**: `db/migrate/xxx_create_google_calendar_integrations.rb`

**Implementation Notes**:
```ruby
class CreateGoogleCalendarIntegrations < ActiveRecord::Migration[8.0]
  def change
    create_table :google_calendar_integrations do |t|
      t.references :business, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :access_token
      t.string :refresh_token
      t.datetime :expires_at
      t.integer :status, default: 0
      t.text :error_message
      
      t.timestamps
    end
    
    add_index :google_calendar_integrations, [:business_id, :user_id], unique: true
    add_index :google_calendar_integrations, :status
  end
end

# Add Google event tracking to appointments
class AddGoogleEventIdToAppointments < ActiveRecord::Migration[8.0]
  def change
    add_column :appointments, :google_event_id, :string
    add_index :appointments, :google_event_id
  end
end
```

## Acceptance Criteria
- Staff members can connect their individual Google Calendars
- Appointments sync to Google Calendar with proper details and attendees
- Calendar availability is checked before scheduling appointments
- Two-way sync updates appointments when changed in Google Calendar
- Multiple staff members can have separate calendar integrations
- Sync errors are handled gracefully with user notification

## Estimate
- Story Points: 10
- Timeline: 1 week
- Dependencies: Google Calendar API credentials, OAuth2 setup
