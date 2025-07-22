# Feature: Operating Hours Management

## Overview
Operating Hours Management provides business owners with flexible scheduling capabilities to define when their business is available for appointments and services at each location. This includes location-specific weekly hours, holiday schedules, and special availability periods that integrate with booking and notification systems.

## User Stories
- As a business owner, I want to set regular weekly hours for each location so customers know when each location is available
- As a business owner, I want to define location-specific holiday closures so customers can't book during those times
- As a business owner, I want to create special availability windows per location so I can accommodate unique scheduling needs
- As a business owner, I want to inherit hours from my primary location to new locations but customize them as needed

## Tasks

### 1. Location-Specific Weekly Hours Configuration
Create interface for setting standard operating hours per location with flexible time ranges.

**Implementation Notes:**
- Add OperatingHours model with location_id, day_of_week, open_time, close_time, is_closed fields
- Create operating_hours controller with location-scoped routes and CRUD operations
- Build weekly hours grid interface with location selector and time picker inputs
- Implement "closed all day" toggle for each day per location
- Add multiple time ranges per day support (split shifts) per location
- Include hours inheritance from primary location for new locations

### 2. Location-Specific Holiday and Closure Management
Implement system for defining specific dates when individual locations are closed or have modified hours.

**Implementation Notes:**
- Add BusinessClosure model with location_id, date, reason, is_full_day, modified_hours fields
- Create closures controller with location-scoped calendar interface
- Build closure form with location selector, date picker and hour modification options
- Implement recurring closure patterns (annual holidays) with location-specific overrides
- Add bulk closure import functionality for multiple locations
- Include closure conflict detection when locations share staff

### 3. Location-Specific Special Availability Windows
Provide capability to extend hours or add availability outside normal operating times per location.

**Implementation Notes:**
- Add SpecialAvailability model with location_id, date, start_time, end_time, reason fields
- Create special availability controller with location-scoped management interface
- Build availability form with location and date/time selection
- Implement availability override system for booking conflicts per location
- Add staff assignment for special availability periods at specific locations
- Include cross-location availability coordination for shared staff
