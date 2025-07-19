# Implementation Task: Business Dashboard

## Overview
Create the primary business dashboard interface that provides quick access to key business functions and metrics.

## Technical Design

### Models
```ruby
class DashboardWidget < ApplicationRecord
  belongs_to :business
  belongs_to :user, optional: true
  
  validates :position, presence: true
  validates :widget_type, presence: true
  
  store :settings, coder: JSON
  store :cache_data, coder: JSON
  
  scope :visible, -> { where(visible: true) }
  scope :ordered, -> { order(position: :asc) }
end

class DashboardLayout < ApplicationRecord
  belongs_to :business
  belongs_to :user, optional: true
  
  store :layout_config, coder: JSON
  
  after_save :invalidate_layout_cache
end
```

### Service Objects
```ruby
class DashboardService
  def self.load_dashboard(business, user)
    # Load personalized layout
    # Fetch widget data
    # Apply user preferences
    # Calculate metrics
  end
  
  def self.update_layout(business, user, layout_params)
    # Update widget positions
    # Save user preferences
    # Refresh cached data
  end
end

class WidgetDataService
  def self.refresh_widget(widget)
    # Fetch updated data
    # Update cache
    # Handle errors
  end
end
```

### Controllers
```ruby
class Business::DashboardController < BusinessController
  def show
    @dashboard_data = DashboardService.load_dashboard(@business, current_user)
  end
  
  def update_layout
    result = DashboardService.update_layout(@business, current_user, layout_params)
    # Handle result
  end
end
```

### Background Jobs
```ruby
class RefreshDashboardDataJob < ApplicationJob
  def perform(business_id)
    # Refresh all widget data
    # Update metrics
    # Handle stale data
  end
end

class DashboardMetricsJob < ApplicationJob
  def perform(business_id)
    # Calculate business metrics
    # Update trending data
    # Generate alerts
  end
end
```

## Views
1. Main Dashboard
   - Widget grid
   - Quick actions
   - Recent activity
   - Key metrics

2. Widget Components
   - Appointments widget
   - Revenue widget
   - Staff activity widget
   - Alerts widget

## API Endpoints
```ruby
# GET /api/v1/business/dashboard
# Returns dashboard data with widgets

# PATCH /api/v1/business/dashboard/layout
{
  "layout": {
    "widgets": [
      {"id": "uuid", "position": 1},
      {"id": "uuid", "position": 2}
    ]
  }
}
```

## Testing Strategy
1. Model Tests
   - Widget configuration
   - Layout persistence
   - Cache behavior

2. Service Tests
   - Dashboard loading
   - Layout updates
   - Data refresh

3. Integration Tests
   - Complete dashboard flow
   - Real-time updates
   - Widget interactions

## Security Considerations
- Widget data access control
- Layout validation
- Rate limiting dashboard API
- Cache security
- Data freshness validation

## Estimated Hours: 24

## Dependencies
- Core Models implementation
- Real-time update system
- Metrics calculation engine
