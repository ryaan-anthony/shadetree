# Implementation Task: Team Assignment Management

## Overview
Create a system for managing team-based service assignments, including team composition, roles, and collaborative service delivery.

## Technical Design

### Models
```ruby
class ServiceTeam < ApplicationRecord
  belongs_to :business
  belongs_to :team_lead, class_name: 'User'
  has_many :team_members
  has_many :team_assignments
  
  validates :team_type, inclusion: { in: %w[permanent temporary project specialty] }
  validates :status, inclusion: { in: %w[active inactive standby dissolved] }
  
  # Store team configuration
  store :team_config, accessors: [
    :capacity,
    :specialties,
    :availability_rules,
    :rotation_schedule
  ], coder: JSON
end

class TeamMember < ApplicationRecord
  belongs_to :service_team
  belongs_to :user
  
  validates :role, inclusion: { in: %w[lead assistant specialist support trainee] }
  validates :status, inclusion: { in: %w[active training backup inactive] }
  
  # Store member configuration
  store :member_config, accessors: [
    :responsibilities,
    :substitution_rules,
    :availability_override
  ], coder: JSON
end

class TeamAssignment < ApplicationRecord
  belongs_to :service_team
  belongs_to :service
  belongs_to :assigned_by, class_name: 'User'
  
  validates :assignment_type, inclusion: { in: %w[primary backup specialty temporary] }
  
  # Store assignment details
  store :assignment_config, accessors: [
    :coverage_rules,
    :rotation_schedule,
    :special_requirements
  ], coder: JSON
end
```

### Service Objects
```ruby
class TeamManagementService
  def self.create_team(business, params)
    ServiceTeam.transaction do
      # Create team
      # Assign members
      # Set up configuration
      # Initialize schedule
    end
  end
  
  def self.assign_service(team, service, params)
    TeamAssignment.transaction do
      # Validate assignment
      # Set up coverage
      # Update schedules
      # Notify members
    end
  end
end

class TeamSchedulingService
  def self.generate_schedule(team, date_range)
    # Calculate availability
    # Apply rotation rules
    # Handle exceptions
    # Create schedule
  end
  
  def self.handle_substitution(team_member, date_range)
    # Find substitutes
    # Update assignments
    # Notify affected members
    # Update schedule
  end
end
```

### Background Jobs
```ruby
class TeamScheduleGenerationJob < ApplicationJob
  def perform(team_id, date_range)
    # Generate schedules
    # Handle conflicts
    # Send notifications
    # Update calendar
  end
end

class TeamMetricsJob < ApplicationJob
  def perform(team_id)
    # Calculate performance
    # Update statistics
    # Generate reports
    # Track utilization
  end
end
```

## Views
1. Team Management
   - Team composition
   - Role assignment
   - Schedule management
   - Performance metrics

2. Service Assignment
   - Team selection
   - Coverage setup
   - Rotation planning
   - Exception handling

## API Endpoints
```ruby
# POST /api/v1/teams
{
  "team_type": "string",
  "team_lead_id": "uuid",
  "members": [{
    "user_id": "uuid",
    "role": "string"
  }]
}

# POST /api/v1/teams/:id/assignments
{
  "service_id": "uuid",
  "assignment_type": "string",
  "config": {}
}
```

## Testing Strategy
1. Model Tests
   - Team validation
   - Member management
   - Assignment handling
   - Schedule generation

2. Service Tests
   - Team creation
   - Service assignment
   - Schedule management
   - Substitution handling

3. Integration Tests
   - Complete team workflow
   - Schedule generation
   - API functionality
   - Notification system

## Security Considerations
- Team management authorization
- Assignment validation
- Schedule access control
- Rate limiting
- Audit logging
- Data privacy

## Estimated Hours: 20

## Dependencies
- Skill Management
- Assignment Rules
