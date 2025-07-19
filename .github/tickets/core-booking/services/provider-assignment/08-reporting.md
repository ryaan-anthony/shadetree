# Implementation Task: Provider Assignment Reporting

## Overview
Create a comprehensive reporting system that provides insights into provider assignments, utilization, and performance metrics.

## Technical Design

### Models
```ruby
class AssignmentReport < ApplicationRecord
  belongs_to :business
  belongs_to :generated_by, class_name: 'User'
  has_one_attached :report_file
  
  validates :report_type, inclusion: { in: %w[utilization performance assignment efficiency] }
  validates :format, inclusion: { in: %w[pdf excel csv json] }
  
  # Store report configuration
  store :report_config, accessors: [
    :date_range,
    :metrics,
    :grouping,
    :filters
  ], coder: JSON
end

class ReportSchedule < ApplicationRecord
  belongs_to :business
  belongs_to :created_by, class_name: 'User'
  
  validates :frequency, inclusion: { in: %w[daily weekly monthly custom] }
  validates :format, inclusion: { in: %w[pdf excel csv json] }
  
  # Store schedule configuration
  store :schedule_config, accessors: [
    :recipients,
    :delivery_method,
    :report_params,
    :last_run
  ], coder: JSON
end

class MetricSnapshot < ApplicationRecord
  belongs_to :business
  
  validates :snapshot_type, inclusion: { in: %w[daily weekly monthly] }
  
  # Store metric data
  store :metrics, accessors: [
    :assignment_stats,
    :utilization_rates,
    :efficiency_scores,
    :trend_data
  ], coder: JSON
end
```

### Service Objects
```ruby
class ReportGenerationService
  def self.generate_report(business, params)
    AssignmentReport.transaction do
      # Gather data
      # Calculate metrics
      # Format report
      # Store results
    end
  end
  
  def self.schedule_report(business, schedule_params)
    # Create schedule
    # Validate params
    # Set up delivery
    # Return schedule
  end
end

class MetricSnapshotService
  def self.take_snapshot(business, snapshot_type)
    # Calculate metrics
    # Store snapshot
    # Update trends
    # Clean old data
  end
  
  def self.analyze_trends(business, metric_type)
    # Load snapshots
    # Calculate trends
    # Generate insights
    # Return analysis
  end
end
```

### Background Jobs
```ruby
class ReportGenerationJob < ApplicationJob
  def perform(report_id)
    # Generate report
    # Format output
    # Handle delivery
    # Update status
  end
end

class MetricSnapshotJob < ApplicationJob
  def perform(business_id, snapshot_type)
    # Take snapshot
    # Update dashboards
    # Generate alerts
    # Clean old data
  end
end
```

## Views
1. Report Configuration
   - Report builder
   - Schedule management
   - Delivery settings
   - Template management

2. Report Dashboard
   - Recent reports
   - Scheduled reports
   - Quick insights
   - Custom queries

## API Endpoints
```ruby
# POST /api/v1/reports
{
  "report_type": "string",
  "config": {
    "date_range": {},
    "metrics": ["string"],
    "format": "string"
  }
}

# GET /api/v1/metrics/snapshots
{
  "snapshot_type": "string",
  "metric_types": ["string"],
  "date_range": {}
}
```

## Testing Strategy
1. Model Tests
   - Report configuration
   - Schedule management
   - Metric snapshots
   - Data validation

2. Service Tests
   - Report generation
   - Metric calculation
   - Trend analysis
   - Delivery handling

3. Integration Tests
   - Complete reporting flow
   - Schedule execution
   - API functionality
   - Data integrity

## Security Considerations
- Report access control
- Data aggregation privacy
- Schedule authorization
- Rate limiting
- Audit logging
- Data retention

## Estimated Hours: 16

## Dependencies
- All Provider Assignment features
- Document Generation System
