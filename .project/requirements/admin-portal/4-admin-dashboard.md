# Epic: Admin Dashboard

## Overview
Create a focused dashboard that provides business owners with essential metrics, activity monitoring, and quick access to common administrative tasks. Prioritize actionable insights that directly impact business operations and decision-making.

## Goals
- Display key business metrics at a glance (< 2 second load time)
- Provide quick access to most common daily tasks
- Show recent activity and important alerts
- Enable basic performance monitoring
- Support mobile access for on-the-go management

## Success Metrics
- Dashboard load time < 2 seconds
- Daily active usage > 80% of business owners
- Quick action completion rate > 95%
- Mobile usage adoption > 60%
- Time to complete common tasks reduced by 50%

## User Stories
- As a business owner, I want to see my key metrics so I can understand my business performance
- As a business owner, I want quick access to common tasks so I can work efficiently
- As a business owner, I want to see recent activity so I can stay informed about my business
- As a staff member, I want to see my relevant metrics and tasks for my role
- As a business owner, I want mobile access so I can manage my business anywhere

## Features

### MVP Phase (P0 - Critical Path)
1. [Dashboard Overview](admin/01-dashboard-overview.md) - Main dashboard layout and navigation
2. [Key Metrics Display](admin/02-key-metrics.md) - Essential business performance indicators

### Growth Phase (P1 - Early Value)
3. [Quick Actions Panel](admin/03-quick-actions.md) - One-click access to common tasks
4. [Recent Activity Feed](admin/04-recent-activity.md) - Real-time business activity monitoring

## Technical Architecture

### Core Components
```ruby
# MVP Dashboard Controller
class Admin::DashboardController < Admin::BaseController
  before_action :authenticate_user!
  before_action :set_current_business
  
  def show
    @metrics = DashboardMetrics.new(@current_business).call
    @recent_quotes = @current_business.quotes.recent.limit(5)
    @upcoming_appointments = @current_business.appointments.upcoming.limit(5)
  end
end

# Dashboard Metrics Service
class DashboardMetrics
  def initialize(business)
    @business = business
  end
  
  def call
    {
      quotes_this_month: quotes_count(:month),
      revenue_this_month: revenue_total(:month),
      appointments_this_week: appointments_count(:week),
      conversion_rate: calculate_conversion_rate
    }
  end
  
  private
  
  def quotes_count(period)
    @business.quotes.where(created_at: time_range(period)).count
  end
  
  def revenue_total(period)
    @business.quotes.accepted.where(created_at: time_range(period)).sum(:total_amount)
  end
  
  def time_range(period)
    case period
    when :week then 1.week.ago..Time.current
    when :month then 1.month.ago..Time.current
    end
  end
end
```

### Caching Strategy
```ruby
# Fragment caching for performance
class Admin::DashboardController < Admin::BaseController
  def show
    @metrics = Rails.cache.fetch("dashboard_metrics_#{@current_business.id}", expires_in: 5.minutes) do
      DashboardMetrics.new(@current_business).call
    end
    # ...existing code...
  end
end
```

## Integration Points
- Business Profile (business-scoped metrics)
- Staff Management (role-based dashboard content)
- Service & Pricing (service performance metrics)
- Quote Management (quote status and conversion tracking)
- Activity Monitoring (recent business events)

## Security Considerations
- Ensure metrics are properly scoped to current business
- Validate user permissions for dashboard data access
- Secure sensitive financial information display
- Audit dashboard access for compliance

## MVP Scope Reduction
**Removed from MVP:**
- Real-time updates with WebSockets
- Advanced analytics and trend analysis
- Customizable dashboard widgets
- Export dashboard data functionality
- Multi-business comparison views

**Simplified for MVP:**
- Server-rendered dashboard with minimal JavaScript
- Essential metrics only (quotes, revenue, appointments)
- Simple recent activity list
- Basic responsive design for mobile

## Phase Progression
- **MVP**: Essential metrics and basic layout
- **Growth**: Quick actions and enhanced activity feed
- **Scale**: Advanced analytics and customization

## Dependencies
- All other Admin Portal epics (provides data sources)
- Business Profile Management (business context)
- Quote Management System (quote metrics)

## Estimate
- MVP Features: 6 story points (0.5 weeks)
- Growth Features: 8 story points (1 week)
- Total: 14 story points (1.5 weeks)

## Technical Implementation Notes
- Use Rails fragment caching for performance optimization
- Implement progressive enhancement for mobile features
- Keep JavaScript minimal and focused on essential interactions
- Use Stimulus controllers for any required interactivity
- Design responsive layout with Tailwind CSS utilities

## Performance Requirements
- Dashboard load time < 2 seconds on 3G connection
- Metrics calculation time < 500ms
- Support concurrent users without performance degradation
- Efficient database queries with proper indexing
