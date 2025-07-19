# Implementation Task: Service History & Records

## Overview
Create a comprehensive service history tracking system that maintains customer appointment history, preferences, and service records.

## Technical Design

### Models
```ruby
class ServiceHistory < ApplicationRecord
  belongs_to :customer
  belongs_to :appointment
  belongs_to :service
  belongs_to :provider, class_name: 'User'
  
  has_many :notes
  has_many_attached :photos
  
  store :service_details, coder: JSON
  store :customer_feedback, coder: JSON
  
  scope :recent, -> { order(service_date: :desc) }
  scope :with_feedback, -> { where.not(customer_feedback: nil) }
end

class ServiceNote < ApplicationRecord
  belongs_to :service_history
  belongs_to :author, class_name: 'User'
  
  validates :content, presence: true
  validates :note_type, inclusion: { in: %w[provider customer system] }
end

class CustomerServiceMetrics < ApplicationRecord
  belongs_to :customer
  
  # Calculated metrics about customer's service history
  store :metrics, accessors: [
    :total_services,
    :favorite_services,
    :preferred_providers,
    :average_frequency
  ], coder: JSON
  
  # Update triggers on service history changes
  after_save :update_customer_segments
end
```

### Service Objects
```ruby
class ServiceHistoryService
  def self.record_service(appointment, details)
    ServiceHistory.transaction do
      # Create service record
      # Process photos
      # Record notes
      # Update metrics
    end
  end
  
  def self.add_feedback(service_history, feedback)
    # Validate and store feedback
    # Update provider ratings
    # Process review content
    # Trigger follow-ups
  end
end

class CustomerMetricsService
  def self.calculate_metrics(customer)
    # Calculate service patterns
    # Analyze preferences
    # Update segments
    # Generate insights
  end
end
```

### Background Jobs
```ruby
class ServiceMetricsCalculationJob < ApplicationJob
  def perform(customer_id)
    # Recalculate all metrics
    # Update customer profile
    # Generate recommendations
  end
end

class ServiceReminderJob < ApplicationJob
  def perform(customer_id)
    # Check service patterns
    # Generate service suggestions
    # Send reminder if needed
  end
end
```

## Views
1. Service History
   - Timeline view
   - Service details
   - Photos and notes
   - Feedback history

2. Service Insights
   - Usage patterns
   - Preferences analysis
   - Recommended services
   - Scheduling suggestions

## API Endpoints
```ruby
# GET /api/v1/customers/:id/service_history
# Optional params: limit, offset, service_type, date_range

# POST /api/v1/service_history/:id/feedback
{
  "feedback": {
    "rating": integer,
    "comments": "string",
    "would_recommend": boolean
  }
}
```

## Testing Strategy
1. Model Tests
   - History record creation
   - Metric calculations
   - Note management
   - Photo attachments

2. Service Tests
   - Service recording
   - Feedback processing
   - Metric updates
   - Pattern analysis

3. Integration Tests
   - Complete service flow
   - Feedback submission
   - API functionality
   - Metric recalculation

## Security Considerations
- Photo storage security
- Note access control
- Feedback validation
- Personal data protection
- Metric calculation security

## Estimated Hours: 20

## Dependencies
- Core Customer Models
- Appointment System
- File Storage System
