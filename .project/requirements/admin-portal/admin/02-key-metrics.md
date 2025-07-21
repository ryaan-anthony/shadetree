# Feature: Key Metrics Display

## Description
Real-time business metrics widget that displays critical performance indicators including revenue, bookings, conversion rates, and other KPIs relevant to service businesses. The metrics are displayed in an easy-to-scan format with visual indicators for trends.

## User Stories
- As a business owner, I want to see today's revenue so I can track daily performance
- As a manager, I want to compare current metrics to previous periods so I can identify trends
- As an admin, I want to see booking conversion rates so I can optimize our sales process
- As a business owner, I want visual indicators (up/down arrows) so I can quickly see if metrics are improving

## Tasks

### Task 1: Create Metrics Service
**Implementation Notes:**
- Create service to calculate and cache business metrics
- Implement comparison logic for period-over-period analysis
- Add caching for performance optimization

```ruby
# app/services/admin/metrics_service.rb
class Admin::MetricsService
  attr_reader :business, :date_range, :comparison_period

  def initialize(business, date_range: Date.current.beginning_of_day..Date.current.end_of_day)
    @business = business
    @date_range = date_range
    @comparison_period = calculate_comparison_period
  end

  def daily_metrics
    Rails.cache.fetch(cache_key("daily_metrics"), expires_in: 5.minutes) do
      {
        revenue: revenue_metrics,
        bookings: booking_metrics,
        customers: customer_metrics,
        conversion: conversion_metrics
      }
    end
  end

  def revenue_metrics
    current_revenue = business.bookings
                             .confirmed
                             .where(scheduled_at: date_range)
                             .sum(:total_amount)
    
    previous_revenue = business.bookings
                              .confirmed
                              .where(scheduled_at: comparison_period)
                              .sum(:total_amount)

    {
      current: current_revenue,
      previous: previous_revenue,
      change_percent: calculate_percentage_change(current_revenue, previous_revenue),
      trend: determine_trend(current_revenue, previous_revenue)
    }
  end

  def booking_metrics
    current_bookings = business.bookings
                              .where(created_at: date_range)
                              .count
    
    previous_bookings = business.bookings
                               .where(created_at: comparison_period)
                               .count

    confirmed_today = business.bookings
                             .confirmed
                             .where(scheduled_at: date_range)
                             .count

    {
      total_today: current_bookings,
      confirmed_today: confirmed_today,
      previous: previous_bookings,
      change_percent: calculate_percentage_change(current_bookings, previous_bookings),
      trend: determine_trend(current_bookings, previous_bookings)
    }
  end

  def customer_metrics
    new_customers = business.customers
                           .where(created_at: date_range)
                           .count
    
    previous_new_customers = business.customers
                                    .where(created_at: comparison_period)
                                    .count

    returning_customers = business.bookings
                                 .joins(:customer)
                                 .where(created_at: date_range)
                                 .where.not(customers: { created_at: date_range })
                                 .select(:customer_id)
                                 .distinct
                                 .count

    {
      new_today: new_customers,
      returning_today: returning_customers,
      previous_new: previous_new_customers,
      change_percent: calculate_percentage_change(new_customers, previous_new_customers),
      trend: determine_trend(new_customers, previous_new_customers)
    }
  end

  def conversion_metrics
    inquiries = business.inquiries.where(created_at: date_range).count
    bookings = business.bookings.where(created_at: date_range).count
    
    current_rate = inquiries > 0 ? (bookings.to_f / inquiries * 100).round(1) : 0
    
    previous_inquiries = business.inquiries.where(created_at: comparison_period).count
    previous_bookings = business.bookings.where(created_at: comparison_period).count
    previous_rate = previous_inquiries > 0 ? (previous_bookings.to_f / previous_inquiries * 100).round(1) : 0

    {
      current_rate: current_rate,
      previous_rate: previous_rate,
      inquiries_today: inquiries,
      bookings_today: bookings,
      change_percent: calculate_percentage_change(current_rate, previous_rate),
      trend: determine_trend(current_rate, previous_rate)
    }
  end

  private

  def calculate_comparison_period
    period_length = date_range.end - date_range.begin
    (date_range.begin - period_length - 1.day)..(date_range.begin - 1.day)
  end

  def calculate_percentage_change(current, previous)
    return 0 if previous.zero?
    ((current - previous).to_f / previous * 100).round(1)
  end

  def determine_trend(current, previous)
    return :neutral if current == previous
    current > previous ? :up : :down
  end

  def cache_key(suffix)
    "metrics:#{business.id}:#{date_range.begin.to_date}:#{suffix}"
  end
end
```

### Task 2: Create Metrics Widget View
**Implementation Notes:**
- Create responsive widget layout
- Include trend indicators and comparison data
- Add real-time update capability

```erb
<!-- app/views/admin/dashboard/widgets/_metrics.html.erb -->
<div 
  class="col-span-1 md:col-span-2 lg:col-span-4 bg-white rounded-lg shadow p-6"
  data-widget="metrics"
  data-widget-refresh="true"
>
  <div class="flex items-center justify-between mb-6">
    <h3 class="text-lg font-medium text-gray-900">Today's Metrics</h3>
    <div class="text-sm text-gray-500">
      vs. yesterday
    </div>
  </div>

  <% 
    metrics = Admin::MetricsService.new(current_admin.business).daily_metrics
    revenue = metrics[:revenue]
    bookings = metrics[:bookings]
    customers = metrics[:customers]
    conversion = metrics[:conversion]
  %>

  <div class="grid grid-cols-2 lg:grid-cols-4 gap-6">
    <!-- Revenue Metric -->
    <div class="text-center">
      <div class="text-2xl font-bold text-gray-900" data-widget-value="revenue">
        <%= number_to_currency(revenue[:current]) %>
      </div>
      <div class="text-sm text-gray-600 mb-2">Revenue</div>
      <div class="flex items-center justify-center text-sm">
        <% if revenue[:trend] == :up %>
          <i class="fas fa-arrow-up text-green-500 mr-1"></i>
          <span class="text-green-600">+<%= revenue[:change_percent] %>%</span>
        <% elsif revenue[:trend] == :down %>
          <i class="fas fa-arrow-down text-red-500 mr-1"></i>
          <span class="text-red-600"><%= revenue[:change_percent] %>%</span>
        <% else %>
          <i class="fas fa-minus text-gray-400 mr-1"></i>
          <span class="text-gray-500">No change</span>
        <% end %>
      </div>
    </div>

    <!-- Bookings Metric -->
    <div class="text-center">
      <div class="text-2xl font-bold text-gray-900" data-widget-value="bookings">
        <%= bookings[:total_today] %>
      </div>
      <div class="text-sm text-gray-600 mb-2">Bookings</div>
      <div class="flex items-center justify-center text-sm">
        <% if bookings[:trend] == :up %>
          <i class="fas fa-arrow-up text-green-500 mr-1"></i>
          <span class="text-green-600">+<%= bookings[:change_percent] %>%</span>
        <% elsif bookings[:trend] == :down %>
          <i class="fas fa-arrow-down text-red-500 mr-1"></i>
          <span class="text-red-600"><%= bookings[:change_percent] %>%</span>
        <% else %>
          <i class="fas fa-minus text-gray-400 mr-1"></i>
          <span class="text-gray-500">No change</span>
        <% end %>
      </div>
    </div>

    <!-- New Customers Metric -->
    <div class="text-center">
      <div class="text-2xl font-bold text-gray-900" data-widget-value="new_customers">
        <%= customers[:new_today] %>
      </div>
      <div class="text-sm text-gray-600 mb-2">New Customers</div>
      <div class="flex items-center justify-center text-sm">
        <% if customers[:trend] == :up %>
          <i class="fas fa-arrow-up text-green-500 mr-1"></i>
          <span class="text-green-600">+<%= customers[:change_percent] %>%</span>
        <% elsif customers[:trend] == :down %>
          <i class="fas fa-arrow-down text-red-500 mr-1"></i>
          <span class="text-red-600"><%= customers[:change_percent] %>%</span>
        <% else %>
          <i class="fas fa-minus text-gray-400 mr-1"></i>
          <span class="text-gray-500">No change</span>
        <% end %>
      </div>
    </div>

    <!-- Conversion Rate Metric -->
    <div class="text-center">
      <div class="text-2xl font-bold text-gray-900" data-widget-value="conversion_rate">
        <%= conversion[:current_rate] %>%
      </div>
      <div class="text-sm text-gray-600 mb-2">Conversion</div>
      <div class="flex items-center justify-center text-sm">
        <% if conversion[:trend] == :up %>
          <i class="fas fa-arrow-up text-green-500 mr-1"></i>
          <span class="text-green-600">+<%= conversion[:change_percent] %>%</span>
        <% elsif conversion[:trend] == :down %>
          <i class="fas fa-arrow-down text-red-500 mr-1"></i>
          <span class="text-red-600"><%= conversion[:change_percent] %>%</span>
        <% else %>
          <i class="fas fa-minus text-gray-400 mr-1"></i>
          <span class="text-gray-500">No change</span>
        <% end %>
      </div>
    </div>
  </div>

  <!-- Additional Details -->
  <div class="mt-6 pt-6 border-t border-gray-200">
    <div class="grid grid-cols-2 lg:grid-cols-4 gap-4 text-sm">
      <div class="text-center">
        <div class="font-medium text-gray-900"><%= bookings[:confirmed_today] %></div>
        <div class="text-gray-600">Confirmed</div>
      </div>
      <div class="text-center">
        <div class="font-medium text-gray-900"><%= customers[:returning_today] %></div>
        <div class="text-gray-600">Returning</div>
      </div>
      <div class="text-center">
        <div class="font-medium text-gray-900"><%= conversion[:inquiries_today] %></div>
        <div class="text-gray-600">Inquiries</div>
      </div>
      <div class="text-center">
        <div class="font-medium text-gray-900" data-widget-value="avg_booking_value">
          <%= number_to_currency(revenue[:current] / [bookings[:confirmed_today], 1].max) %>
        </div>
        <div class="text-gray-600">Avg. Value</div>
      </div>
    </div>
  </div>
</div>
```

### Task 3: Add Metrics API Endpoint
**Implementation Notes:**
- Add API endpoint to the dashboard controller
- Implement real-time data fetching
- Include error handling and caching

```ruby
# Add to app/controllers/admin/dashboard_controller.rb

def widget_data
  widget_type = params[:widget_type]
  
  case widget_type
  when 'metrics'
    metrics_data = Admin::MetricsService.new(current_admin.business).daily_metrics
    render json: {
      revenue: metrics_data[:revenue][:current],
      bookings: metrics_data[:bookings][:total_today],
      new_customers: metrics_data[:customers][:new_today],
      conversion_rate: metrics_data[:conversion][:current_rate],
      avg_booking_value: metrics_data[:revenue][:current] / [metrics_data[:bookings][:confirmed_today], 1].max
    }
  else
    render json: { error: 'Unknown widget type' }, status: :unprocessable_entity
  end
rescue StandardError => e
  Rails.logger.error "Dashboard widget error: #{e.message}"
  render json: { error: 'Unable to fetch widget data' }, status: :internal_server_error
end
```

### Task 4: Create Background Job for Metrics Updates
**Implementation Notes:**
- Create job to update metrics cache
- Schedule regular updates for real-time data
- Implement broadcast updates using ActionCable

```ruby
# app/jobs/admin/update_metrics_job.rb
class Admin::UpdateMetricsJob < ApplicationJob
  queue_as :default

  def perform(business_id)
    business = Business.find(business_id)
    metrics_service = Admin::MetricsService.new(business)
    
    # Update metrics cache
    updated_metrics = metrics_service.daily_metrics
    
    # Broadcast to dashboard users
    ActionCable.server.broadcast(
      "dashboard_#{business_id}",
      {
        widget: 'metrics',
        data: {
          revenue: updated_metrics[:revenue][:current],
          bookings: updated_metrics[:bookings][:total_today],
          new_customers: updated_metrics[:customers][:new_today],
          conversion_rate: updated_metrics[:conversion][:current_rate]
        }
      }
    )
  end
end

# Add to config/schedule.rb (if using whenever gem)
every 5.minutes do
  runner "Business.find_each { |business| Admin::UpdateMetricsJob.perform_later(business.id) }"
end
```

### Task 5: Add Stimulus Controller for Real-time Updates
**Implementation Notes:**
- Extend dashboard controller for metrics-specific functionality
- Handle real-time updates via ActionCable
- Add smooth animations for metric changes

```javascript
// Add to app/javascript/controllers/dashboard_controller.js

// ...existing code...

connect() {
  this.initializeSortable()
  this.updateTimestamp()
  this.startAutoRefresh()
  this.subscribeToUpdates()
}

subscribeToUpdates() {
  if (this.data.has('businessId')) {
    const businessId = this.data.get('businessId')
    this.subscription = App.cable.subscriptions.create(
      { channel: "DashboardChannel", business_id: businessId },
      {
        received: (data) => {
          this.handleRealtimeUpdate(data)
        }
      }
    )
  }
}

handleRealtimeUpdate(data) {
  if (data.widget === 'metrics') {
    this.updateMetricsWidget(data.data)
  }
}

updateMetricsWidget(data) {
  const metricsWidget = this.widgetGridTarget.querySelector('[data-widget="metrics"]')
  if (!metricsWidget) return

  Object.entries(data).forEach(([key, value]) => {
    const element = metricsWidget.querySelector(`[data-widget-value="${key}"]`)
    if (element) {
      this.animateValueChange(element, value)
    }
  })
}

animateValueChange(element, newValue) {
  // Add highlight animation
  element.classList.add('bg-blue-100', 'transition-colors', 'duration-500')
  
  // Format value based on element type
  if (element.dataset.widgetValue === 'revenue' || element.dataset.widgetValue === 'avg_booking_value') {
    element.textContent = this.formatCurrency(newValue)
  } else if (element.dataset.widgetValue === 'conversion_rate') {
    element.textContent = `${newValue}%`
  } else {
    element.textContent = newValue
  }
  
  // Remove highlight after animation
  setTimeout(() => {
    element.classList.remove('bg-blue-100')
  }, 500)
}

formatCurrency(amount) {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD'
  }).format(amount)
}

disconnect() {
  if (this.refreshInterval) {
    clearInterval(this.refreshInterval)
  }
  if (this.subscription) {
    this.subscription.unsubscribe()
  }
}

// ...existing code...
```

## Acceptance Criteria
- [ ] Metrics display accurate real-time data
- [ ] Trend indicators show correct up/down/neutral states
- [ ] Percentage changes calculate correctly
- [ ] Widget updates automatically every 5 minutes
- [ ] Performance impact is minimal (cached data)
- [ ] Mobile layout displays metrics clearly
- [ ] Error states are handled gracefully

## Testing Requirements
- Unit tests for MetricsService calculations
- Integration tests for API endpoints
- Performance tests for metrics generation
- Real-time update functionality testing
- Mobile responsiveness testing
