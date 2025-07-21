# Feature: Key Metrics Display

## Overview
Create focused metric components that display critical business performance indicators with visual representations and trend analysis.

## User Stories
- As a business owner, I want to see key performance indicators at a glance so I can track business health
- As a business owner, I want to see trends and comparisons to understand business growth
- As a manager, I want to drill down into specific metrics for detailed analysis

## Tasks

### 1. Create Metrics Calculator Service
**File**: `app/services/metrics_calculator_service.rb`

**Implementation Notes**:
```ruby
class MetricsCalculatorService
  def initialize(business, date_range)
    @business = business
    @date_range = date_range
    @previous_range = calculate_previous_period
  end
  
  def financial_metrics
    {
      total_revenue: total_revenue,
      pending_revenue: pending_revenue,
      average_quote_value: average_quote_value,
      revenue_trend: revenue_trend_data,
      monthly_revenue: monthly_revenue_breakdown
    }
  end
  
  def operational_metrics
    {
      quote_volume: quote_volume_metrics,
      job_performance: job_performance_metrics,
      customer_metrics: customer_acquisition_metrics,
      efficiency_metrics: efficiency_metrics
    }
  end
  
  def growth_indicators
    {
      revenue_growth: calculate_growth_rate(:revenue),
      customer_growth: calculate_growth_rate(:customers),
      quote_growth: calculate_growth_rate(:quotes),
      job_completion_rate: job_completion_rate
    }
  end
  
  def comparative_analysis
    {
      vs_previous_period: previous_period_comparison,
      vs_industry_average: industry_benchmark_comparison,
      seasonal_trends: seasonal_analysis
    }
  end
  
  private
  
  def total_revenue
    approved_quotes.sum(:total_amount)
  end
  
  def pending_revenue
    pending_quotes.sum(:total_amount)
  end
  
  def average_quote_value
    current_quotes.average(:total_amount)&.round(2) || 0
  end
  
  def revenue_trend_data
    # Generate daily revenue data for charting
    days = (@date_range.begin.to_date..@date_range.end.to_date).to_a
    
    days.map do |date|
      daily_revenue = approved_quotes.where(
        approved_at: date.beginning_of_day..date.end_of_day
      ).sum(:total_amount)
      
      {
        date: date.strftime('%m/%d'),
        revenue: daily_revenue
      }
    end
  end
  
  def monthly_revenue_breakdown
    current_quotes.approved
                  .group_by_month(:approved_at, range: @date_range)
                  .sum(:total_amount)
  end
  
  def quote_volume_metrics
    {
      total_quotes: current_quotes.count,
      pending_quotes: pending_quotes.count,
      approved_quotes: approved_quotes.count,
      rejected_quotes: rejected_quotes.count,
      approval_rate: calculate_approval_rate
    }
  end
  
  def job_performance_metrics
    jobs = current_appointments
    
    {
      total_jobs: jobs.count,
      completed_jobs: jobs.completed.count,
      scheduled_jobs: jobs.scheduled.count,
      cancelled_jobs: jobs.cancelled.count,
      completion_rate: calculate_completion_rate(jobs)
    }
  end
  
  def customer_acquisition_metrics
    {
      new_customers: new_customers_count,
      repeat_customers: repeat_customers_count,
      customer_lifetime_value: calculate_customer_ltv,
      retention_rate: calculate_retention_rate
    }
  end
  
  def efficiency_metrics
    {
      average_response_time: calculate_avg_response_time,
      quote_to_job_time: calculate_quote_to_job_time,
      staff_utilization: calculate_staff_utilization
    }
  end
  
  def calculate_growth_rate(metric)
    current_value = case metric
                   when :revenue then total_revenue
                   when :customers then new_customers_count
                   when :quotes then current_quotes.count
                   end
    
    previous_value = case metric
                    when :revenue then previous_revenue
                    when :customers then previous_customers_count
                    when :quotes then previous_quotes_count
                    end
    
    return 0 if previous_value.zero?
    
    ((current_value - previous_value).to_f / previous_value * 100).round(1)
  end
  
  def job_completion_rate
    jobs = current_appointments
    return 0 if jobs.count.zero?
    
    (jobs.completed.count.to_f / jobs.count * 100).round(1)
  end
  
  def calculate_approval_rate
    total = current_quotes.count
    return 0 if total.zero?
    
    (approved_quotes.count.to_f / total * 100).round(1)
  end
  
  def calculate_completion_rate(jobs)
    return 0 if jobs.count.zero?
    (jobs.completed.count.to_f / jobs.count * 100).round(1)
  end
  
  def new_customers_count
    current_quotes.select(:customer_email).distinct.count
  end
  
  def repeat_customers_count
    # Customers who have multiple quotes in the period
    customer_quote_counts = current_quotes.group(:customer_email).count
    customer_quote_counts.count { |_, count| count > 1 }
  end
  
  def calculate_customer_ltv
    # Simplified LTV calculation
    avg_quote_value * (repeat_customers_count + 1)
  end
  
  def calculate_retention_rate
    # Percentage of customers who return for additional services
    return 0 if new_customers_count.zero?
    (repeat_customers_count.to_f / new_customers_count * 100).round(1)
  end
  
  def calculate_avg_response_time
    # Time between quote request and quote sent (in hours)
    # This would need actual timestamp data
    24 # Placeholder
  end
  
  def calculate_quote_to_job_time
    # Average time from quote approval to job completion
    approved_with_jobs = approved_quotes.joins(:appointments)
    return 0 if approved_with_jobs.empty?
    
    # Placeholder calculation - would use actual date differences
    7 # days
  end
  
  def calculate_staff_utilization
    # Percentage of available staff time that's booked
    # This would integrate with staff availability data
    75 # Placeholder percentage
  end
  
  def previous_period_comparison
    {
      revenue: calculate_growth_rate(:revenue),
      quotes: calculate_growth_rate(:quotes),
      customers: calculate_growth_rate(:customers)
    }
  end
  
  def industry_benchmark_comparison
    # These would come from external industry data
    {
      approval_rate: { current: calculate_approval_rate, benchmark: 65 },
      response_time: { current: calculate_avg_response_time, benchmark: 12 },
      completion_rate: { current: job_completion_rate, benchmark: 85 }
    }
  end
  
  def seasonal_analysis
    # Compare current period to same period last year
    # This would require historical data
    {
      year_over_year_growth: 15.5, # Placeholder
      seasonal_trend: 'growing' # 'growing', 'declining', 'stable'
    }
  end
  
  # Helper methods for data access
  def current_quotes
    @current_quotes ||= @business.quotes.where(created_at: @date_range)
  end
  
  def approved_quotes
    @approved_quotes ||= current_quotes.approved
  end
  
  def pending_quotes
    @pending_quotes ||= current_quotes.pending
  end
  
  def rejected_quotes
    @rejected_quotes ||= current_quotes.rejected
  end
  
  def current_appointments
    @current_appointments ||= @business.appointments.where(created_at: @date_range)
  end
  
  def calculate_previous_period
    period_length = @date_range.end - @date_range.begin
    (@date_range.begin - period_length)..@date_range.begin
  end
  
  def previous_revenue
    @business.quotes.approved.where(created_at: @previous_range).sum(:total_amount)
  end
  
  def previous_customers_count
    @business.quotes.where(created_at: @previous_range).select(:customer_email).distinct.count
  end
  
  def previous_quotes_count
    @business.quotes.where(created_at: @previous_range).count
  end
end
```

### 2. Create Metrics Display Component
**File**: `app/components/metrics_display_component.rb`

**Implementation Notes**:
```ruby
class MetricsDisplayComponent < ViewComponent::Base
  def initialize(business:, date_range:, metric_type: :overview)
    @business = business
    @date_range = date_range
    @metric_type = metric_type
    @calculator = MetricsCalculatorService.new(business, date_range)
  end
  
  private
  
  attr_reader :business, :date_range, :metric_type, :calculator
  
  def metrics_data
    @metrics_data ||= case metric_type
                     when :financial
                       calculator.financial_metrics
                     when :operational
                       calculator.operational_metrics
                     when :growth
                       calculator.growth_indicators
                     else
                       calculator.financial_metrics.merge(calculator.operational_metrics)
                     end
  end
  
  def format_currency(amount)
    number_to_currency(amount)
  end
  
  def format_percentage(value)
    "#{value}%"
  end
  
  def trend_indicator(value)
    return 'neutral' if value.zero?
    value > 0 ? 'positive' : 'negative'
  end
  
  def trend_color_class(value)
    case trend_indicator(value)
    when 'positive'
      'text-green-600'
    when 'negative'
      'text-red-600'
    else
      'text-gray-600'
    end
  end
  
  def trend_icon(value)
    case trend_indicator(value)
    when 'positive'
      '↗️'
    when 'negative'
      '↘️'
    else
      '➡️'
    end
  end
end
```

### 3. Create Metrics Display View Template
**File**: `app/components/metrics_display_component.html.erb`

**Implementation Notes**:
```erb
<div class="bg-white shadow rounded-lg p-6">
  <div class="border-b border-gray-200 pb-4 mb-6">
    <h3 class="text-lg font-medium text-gray-900">
      <%= metric_type.to_s.titleize %> Metrics
    </h3>
    <p class="text-sm text-gray-500 mt-1">
      <%= date_range.begin.strftime('%B %d') %> - <%= date_range.end.strftime('%B %d, %Y') %>
    </p>
  </div>
  
  <% if metric_type == :financial || metric_type == :overview %>
    <!-- Financial Metrics Section -->
    <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mb-6">
      <!-- Total Revenue -->
      <div class="bg-gradient-to-r from-green-50 to-green-100 rounded-lg p-4">
        <div class="flex items-center justify-between">
          <div>
            <p class="text-sm font-medium text-green-600">Total Revenue</p>
            <p class="text-2xl font-bold text-green-900">
              <%= format_currency(metrics_data[:total_revenue]) %>
            </p>
          </div>
          <div class="text-right">
            <span class="text-sm <%= trend_color_class(calculator.growth_indicators[:revenue_growth]) %>">
              <%= trend_icon(calculator.growth_indicators[:revenue_growth]) %>
              <%= format_percentage(calculator.growth_indicators[:revenue_growth]) %>
            </span>
          </div>
        </div>
      </div>
      
      <!-- Pending Revenue -->
      <div class="bg-gradient-to-r from-yellow-50 to-yellow-100 rounded-lg p-4">
        <div class="flex items-center justify-between">
          <div>
            <p class="text-sm font-medium text-yellow-600">Pending Revenue</p>
            <p class="text-2xl font-bold text-yellow-900">
              <%= format_currency(metrics_data[:pending_revenue]) %>
            </p>
          </div>
          <div class="text-right">
            <p class="text-xs text-yellow-600">
              <%= calculator.operational_metrics[:quote_volume][:pending_quotes] %> quotes
            </p>
          </div>
        </div>
      </div>
    </div>
    
    <!-- Revenue Trend Chart -->
    <% if metrics_data[:revenue_trend] %>
      <div class="mb-6">
        <h4 class="text-sm font-medium text-gray-900 mb-3">Revenue Trend</h4>
        <div class="bg-gray-50 rounded-lg p-4">
          <canvas id="revenue-trend-chart" width="400" height="150"></canvas>
        </div>
      </div>
    <% end %>
  <% end %>
  
  <% if metric_type == :operational || metric_type == :overview %>
    <!-- Operational Metrics Section -->
    <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
      <!-- Quote Approval Rate -->
      <div class="text-center">
        <div class="bg-blue-100 rounded-full p-3 w-16 h-16 mx-auto mb-2 flex items-center justify-center">
          <svg class="w-8 h-8 text-blue-600" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd"/>
          </svg>
        </div>
        <p class="text-2xl font-bold text-gray-900">
          <%= format_percentage(metrics_data[:quote_volume][:approval_rate]) %>
        </p>
        <p class="text-sm text-gray-500">Quote Approval Rate</p>
      </div>
      
      <!-- Job Completion Rate -->
      <div class="text-center">
        <div class="bg-purple-100 rounded-full p-3 w-16 h-16 mx-auto mb-2 flex items-center justify-center">
          <svg class="w-8 h-8 text-purple-600" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"/>
          </svg>
        </div>
        <p class="text-2xl font-bold text-gray-900">
          <%= format_percentage(metrics_data[:job_performance][:completion_rate]) %>
        </p>
        <p class="text-sm text-gray-500">Job Completion Rate</p>
      </div>
      
      <!-- Customer Retention -->
      <div class="text-center">
        <div class="bg-indigo-100 rounded-full p-3 w-16 h-16 mx-auto mb-2 flex items-center justify-center">
          <svg class="w-8 h-8 text-indigo-600" fill="currentColor" viewBox="0 0 20 20">
            <path d="M9 6a3 3 0 11-6 0 3 3 0 016 0zM17 6a3 3 0 11-6 0 3 3 0 016 0zM12.93 17c.046-.327.07-.66.07-1a6.97 6.97 0 00-1.5-4.33A5 5 0 0119 16v1h-6.07zM6 11a5 5 0 015 5v1H1v-1a5 5 0 015-5z"/>
          </svg>
        </div>
        <p class="text-2xl font-bold text-gray-900">
          <%= format_percentage(metrics_data[:customer_metrics][:retention_rate]) %>
        </p>
        <p class="text-sm text-gray-500">Customer Retention</p>
      </div>
    </div>
  <% end %>
  
  <% if metric_type == :growth %>
    <!-- Growth Indicators -->
    <div class="space-y-4">
      <% calculator.growth_indicators.each do |metric, value| %>
        <div class="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
          <span class="text-sm font-medium text-gray-900 capitalize">
            <%= metric.to_s.humanize %>
          </span>
          <span class="text-sm font-bold <%= trend_color_class(value) %>">
            <%= trend_icon(value) %> <%= format_percentage(value) %>
          </span>
        </div>
      <% end %>
    </div>
  <% end %>
  
  <!-- Industry Comparison -->
  <div class="mt-6 pt-6 border-t border-gray-200">
    <h4 class="text-sm font-medium text-gray-900 mb-3">Industry Comparison</h4>
    <div class="space-y-3">
      <% calculator.comparative_analysis[:vs_industry_average].each do |metric, data| %>
        <div class="flex items-center justify-between">
          <span class="text-sm text-gray-600 capitalize"><%= metric.to_s.humanize %></span>
          <div class="flex items-center space-x-2">
            <span class="text-sm font-medium text-gray-900">
              <%= data[:current] %><%= metric.to_s.include?('rate') ? '%' : '' %>
            </span>
            <span class="text-xs text-gray-500">vs</span>
            <span class="text-sm text-gray-500">
              <%= data[:benchmark] %><%= metric.to_s.include?('rate') ? '%' : '' %>
            </span>
          </div>
        </div>
      <% end %>
    </div>
  </div>
</div>

<script data-turbo-track="reload">
  // Initialize revenue trend chart if data exists
  <% if metrics_data[:revenue_trend] %>
    document.addEventListener('DOMContentLoaded', function() {
      const canvas = document.getElementById('revenue-trend-chart');
      if (canvas) {
        const ctx = canvas.getContext('2d');
        const data = <%= metrics_data[:revenue_trend].to_json.html_safe %>;
        
        // Simple line chart implementation
        drawRevenueChart(ctx, data);
      }
    });
    
    function drawRevenueChart(ctx, data) {
      const width = ctx.canvas.width;
      const height = ctx.canvas.height;
      const padding = 40;
      
      // Clear canvas
      ctx.clearRect(0, 0, width, height);
      
      // Set up chart area
      const chartWidth = width - 2 * padding;
      const chartHeight = height - 2 * padding;
      
      // Find min/max values
      const values = data.map(d => d.revenue);
      const maxValue = Math.max(...values);
      const minValue = Math.min(...values);
      
      // Draw axes
      ctx.strokeStyle = '#e5e7eb';
      ctx.lineWidth = 1;
      
      // Y-axis
      ctx.beginPath();
      ctx.moveTo(padding, padding);
      ctx.lineTo(padding, height - padding);
      ctx.stroke();
      
      // X-axis
      ctx.beginPath();
      ctx.moveTo(padding, height - padding);
      ctx.lineTo(width - padding, height - padding);
      ctx.stroke();
      
      // Draw data line
      ctx.strokeStyle = '#10b981';
      ctx.lineWidth = 2;
      ctx.beginPath();
      
      data.forEach((point, index) => {
        const x = padding + (index / (data.length - 1)) * chartWidth;
        const y = height - padding - ((point.revenue - minValue) / (maxValue - minValue)) * chartHeight;
        
        if (index === 0) {
          ctx.moveTo(x, y);
        } else {
          ctx.lineTo(x, y);
        }
      });
      
      ctx.stroke();
      
      // Draw data points
      ctx.fillStyle = '#10b981';
      data.forEach((point, index) => {
        const x = padding + (index / (data.length - 1)) * chartWidth;
        const y = height - padding - ((point.revenue - minValue) / (maxValue - minValue)) * chartHeight;
        
        ctx.beginPath();
        ctx.arc(x, y, 3, 0, 2 * Math.PI);
        ctx.fill();
      });
    }
  <% end %>
</script>
```

### 4. Create Shared Metrics Partial
**File**: `app/views/shared/_key_metrics_display.html.erb`

**Implementation Notes**:
```erb
<div class="bg-white shadow rounded-lg">
  <div class="px-6 py-4 border-b border-gray-200">
    <h3 class="text-lg font-medium text-gray-900">Key Performance Indicators</h3>
  </div>
  
  <div class="p-6">
    <!-- Metric Tabs -->
    <div class="border-b border-gray-200 mb-6">
      <nav class="-mb-px flex space-x-8">
        <button class="metric-tab border-b-2 border-blue-500 py-2 px-1 text-sm font-medium text-blue-600" data-tab="financial">
          Financial
        </button>
        <button class="metric-tab border-b-2 border-transparent py-2 px-1 text-sm font-medium text-gray-500 hover:text-gray-700 hover:border-gray-300" data-tab="operational">
          Operational
        </button>
        <button class="metric-tab border-b-2 border-transparent py-2 px-1 text-sm font-medium text-gray-500 hover:text-gray-700 hover:border-gray-300" data-tab="growth">
          Growth
        </button>
      </nav>
    </div>
    
    <!-- Financial Metrics Tab -->
    <div id="financial-metrics" class="metric-content">
      <%= render MetricsDisplayComponent.new(
            business: current_user.business,
            date_range: @date_range,
            metric_type: :financial
          ) %>
    </div>
    
    <!-- Operational Metrics Tab -->
    <div id="operational-metrics" class="metric-content hidden">
      <%= render MetricsDisplayComponent.new(
            business: current_user.business,
            date_range: @date_range,
            metric_type: :operational
          ) %>
    </div>
    
    <!-- Growth Metrics Tab -->
    <div id="growth-metrics" class="metric-content hidden">
      <%= render MetricsDisplayComponent.new(
            business: current_user.business,
            date_range: @date_range,
            metric_type: :growth
          ) %>
    </div>
  </div>
</div>

<script data-turbo-track="reload">
  // Tab switching functionality
  document.addEventListener('DOMContentLoaded', function() {
    const tabs = document.querySelectorAll('.metric-tab');
    const contents = document.querySelectorAll('.metric-content');
    
    tabs.forEach(tab => {
      tab.addEventListener('click', function() {
        const targetTab = this.dataset.tab;
        
        // Update tab appearance
        tabs.forEach(t => {
          t.classList.remove('border-blue-500', 'text-blue-600');
          t.classList.add('border-transparent', 'text-gray-500');
        });
        this.classList.remove('border-transparent', 'text-gray-500');
        this.classList.add('border-blue-500', 'text-blue-600');
        
        // Show/hide content
        contents.forEach(content => {
          content.classList.add('hidden');
        });
        document.getElementById(`${targetTab}-metrics`).classList.remove('hidden');
      });
    });
  });
</script>
```

## Acceptance Criteria
- [ ] Displays accurate financial metrics with trend indicators
- [ ] Shows operational performance metrics with visual representations
- [ ] Provides growth indicators with period-over-period comparisons
- [ ] Includes industry benchmark comparisons where applicable
- [ ] Charts and graphs render correctly across different screen sizes
- [ ] Tab navigation works smoothly between different metric categories
- [ ] Metrics update when date range is changed
- [ ] All calculations are accurate and performant

## Testing Requirements
- Service tests for all metric calculations
- Component tests for metrics display
- Controller tests for data assembly
- JavaScript tests for chart rendering
- Performance tests for metric calculation speed
