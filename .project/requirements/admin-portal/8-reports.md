# Epic: Reports & Analytics

## Overview
Provide business owners with comprehensive reporting and analytics capabilities to track revenue, job performance, outstanding payments, and quote conversion rates. Enable data-driven decision making through clear visualizations and actionable insights.

## Goals
- Enable data-driven business decision making
- Track key performance indicators and business health metrics
- Identify trends and opportunities for business growth
- Monitor quote conversion and sales pipeline effectiveness
- Provide financial reporting for accounting and tax purposes

## Success Metrics
- Report generation time < 10 seconds
- Report usage adoption > 80% of business owners
- Time to generate financial reports < 5 minutes
- Data accuracy rate = 100%
- Business insights identification > 60% of users find actionable insights

## User Stories
- As a business owner, I want to see my revenue trends so I can understand my business growth
- As a business owner, I want to track quote conversion rates so I can improve my sales process
- As a business owner, I want to see outstanding payments so I can follow up on collections
- As a business owner, I want job performance reports so I can optimize my operations
- As an accountant, I want detailed financial reports so I can prepare tax filings

## Features

### Growth Phase (P2 - Advanced Features)
1. [Revenue Reports](reports/01-revenue-reports.md) - Monthly/quarterly revenue tracking and trends
2. [Job Performance Analytics](reports/02-job-analytics.md) - Service efficiency and profitability analysis
3. [Quote Conversion Tracking](reports/03-conversion-tracking.md) - Sales pipeline and conversion rate analysis
4. [Outstanding Payments Report](reports/04-payments-report.md) - Accounts receivable and collection tracking

## Technical Architecture

### Core Models
```ruby
# Report definition and caching
class Report < ApplicationRecord
  belongs_to :business
  belongs_to :created_by, class_name: 'User'
  
  validates :name, :report_type, presence: true
  
  enum report_type: {
    revenue: 0,
    job_performance: 1,
    quote_conversion: 2,
    outstanding_payments: 3,
    custom: 4
  }
  
  enum status: { generating: 0, completed: 1, failed: 2 }
  
  # Store report parameters and results
  validates :parameters, :results, presence: true
  
  scope :recent, -> { where(created_at: 30.days.ago..) }
end

# Analytics data aggregation
class AnalyticsData < ApplicationRecord
  belongs_to :business
  
  validates :metric_type, :period_start, :period_end, presence: true
  validates :metric_type, uniqueness: { scope: [:business_id, :period_start, :period_end] }
  
  enum metric_type: {
    daily_revenue: 0,
    weekly_quotes: 1,
    monthly_conversions: 2,
    service_performance: 3
  }
  
  # JSON field for metric data
  validates :data, presence: true
end
```

### Report Generation Service
```ruby
class ReportService
  def initialize(business, report_type, parameters = {})
    @business = business
    @report_type = report_type
    @parameters = parameters
  end
  
  def generate
    case @report_type
    when 'revenue'
      generate_revenue_report
    when 'job_performance'
      generate_job_performance_report
    when 'quote_conversion'
      generate_conversion_report
    when 'outstanding_payments'
      generate_payments_report
    end
  end
  
  private
  
  def generate_revenue_report
    start_date = @parameters[:start_date]&.to_date || 6.months.ago
    end_date = @parameters[:end_date]&.to_date || Date.current
    
    # Monthly revenue aggregation
    monthly_revenue = @business.quotes.accepted
      .where(created_at: start_date..end_date)
      .group_by_month(:created_at)
      .sum(:total_amount)
    
    # Service breakdown
    service_revenue = @business.quotes.accepted
      .joins(:quote_line_items)
      .where(created_at: start_date..end_date)
      .group('quote_line_items.service_name')
      .sum('quote_line_items.total_price')
    
    # Growth metrics
    current_period = monthly_revenue.values.last(3).sum
    previous_period = monthly_revenue.values[-6..-4].sum
    growth_rate = previous_period > 0 ? ((current_period - previous_period) / previous_period * 100) : 0
    
    {
      monthly_revenue: monthly_revenue,
      service_breakdown: service_revenue,
      total_revenue: monthly_revenue.values.sum,
      growth_rate: growth_rate.round(2),
      period: { start: start_date, end: end_date }
    }
  end
  
  def generate_conversion_report
    start_date = @parameters[:start_date]&.to_date || 3.months.ago
    end_date = @parameters[:end_date]&.to_date || Date.current
    
    quotes = @business.quotes.where(created_at: start_date..end_date)
    
    total_quotes = quotes.count
    accepted_quotes = quotes.accepted.count
    conversion_rate = total_quotes > 0 ? (accepted_quotes.to_f / total_quotes * 100) : 0
    
    # Conversion by service type
    service_conversions = quotes.joins(:quote_line_items)
      .group('quote_line_items.service_name')
      .group(:status)
      .count
    
    # Monthly conversion trends
    monthly_conversions = quotes.group_by_month(:created_at)
      .group(:status)
      .count
    
    {
      total_quotes: total_quotes,
      accepted_quotes: accepted_quotes,
      conversion_rate: conversion_rate.round(2),
      service_conversions: service_conversions,
      monthly_trends: monthly_conversions,
      average_quote_value: quotes.accepted.average(:total_amount)&.round(2)
    }
  end
  
  def generate_payments_report
    # Outstanding invoices and payments
    outstanding_quotes = @business.quotes.accepted
      .where(payment_status: ['pending', 'partial'])
      .includes(:client)
    
    overdue_quotes = outstanding_quotes.where('due_date < ?', Date.current)
    
    total_outstanding = outstanding_quotes.sum(:total_amount)
    total_overdue = overdue_quotes.sum(:total_amount)
    
    # Aging analysis
    aging_buckets = {
      current: outstanding_quotes.where('due_date >= ?', Date.current).sum(:total_amount),
      '1-30_days': outstanding_quotes.where(due_date: 30.days.ago..Date.current).sum(:total_amount),
      '31-60_days': outstanding_quotes.where(due_date: 60.days.ago..30.days.ago).sum(:total_amount),
      '60+_days': outstanding_quotes.where('due_date < ?', 60.days.ago).sum(:total_amount)
    }
    
    {
      total_outstanding: total_outstanding,
      total_overdue: total_overdue,
      aging_analysis: aging_buckets,
      outstanding_by_client: outstanding_quotes.group(:client_id).sum(:total_amount),
      payment_trends: analyze_payment_trends
    }
  end
end
```

### Analytics Dashboard Service
```ruby
class AnalyticsDashboard
  def initialize(business)
    @business = business
  end
  
  def summary_metrics
    {
      revenue_this_month: revenue_for_period(1.month.ago..Date.current),
      revenue_last_month: revenue_for_period(2.months.ago..1.month.ago),
      quotes_this_month: quotes_for_period(1.month.ago..Date.current),
      conversion_rate: calculate_conversion_rate,
      outstanding_amount: calculate_outstanding_payments,
      top_services: top_performing_services
    }
  end
  
  def revenue_trends(months = 12)
    start_date = months.months.ago
    
    @business.quotes.accepted
      .where(created_at: start_date..Date.current)
      .group_by_month(:created_at)
      .sum(:total_amount)
  end
  
  private
  
  def revenue_for_period(period)
    @business.quotes.accepted
      .where(created_at: period)
      .sum(:total_amount)
  end
  
  def quotes_for_period(period)
    @business.quotes
      .where(created_at: period)
      .count
  end
  
  def calculate_conversion_rate
    last_month_quotes = @business.quotes.where(created_at: 1.month.ago..Date.current)
    total = last_month_quotes.count
    accepted = last_month_quotes.accepted.count
    
    total > 0 ? (accepted.to_f / total * 100).round(2) : 0
  end
end
```

## Integration Points
- Quote Management (source data for conversion and revenue reports)
- Payment Processing (payment status and outstanding amounts)
- Service & Pricing (service performance analysis)
- Admin Dashboard (summary metrics display)
- Data Export (report output formats)

## Security Considerations
- Ensure business scoping for all report data
- Validate date ranges and report parameters
- Audit report generation and access
- Secure sensitive financial information
- Implement proper access controls for different user roles

## Growth Phase Scope (P2 Priority)
**Included in Growth Phase:**
- 4 core report types (revenue, job performance, conversion, payments)
- Monthly/quarterly time period analysis
- Basic trend visualization with charts
- Export functionality for accounting purposes

**Future Enhancements:**
- Advanced analytics with predictive insights
- Custom report builder with drag-and-drop
- Automated report scheduling and delivery
- Integration with accounting software APIs

## Technical Implementation Notes
```ruby
# Background job for report generation
class ReportGenerationJob < ApplicationJob
  queue_as :reports
  
  def perform(report_id)
    report = Report.find(report_id)
    report.update!(status: :generating)
    
    begin
      service = ReportService.new(report.business, report.report_type, report.parameters)
      results = service.generate
      
      report.update!(
        status: :completed,
        results: results,
        completed_at: Time.current
      )
    rescue => e
      report.update!(
        status: :failed,
        error_message: e.message
      )
    end
  end
end

# Controller for report management
class Admin::ReportsController < Admin::BaseController
  def show
    @report_type = params[:type] || 'revenue'
    @parameters = report_params
    
    # Check for cached report
    @report = current_business.reports
      .where(report_type: @report_type, parameters: @parameters)
      .where('created_at > ?', 1.hour.ago)
      .completed
      .first
    
    unless @report
      @report = current_business.reports.create!(
        report_type: @report_type,
        parameters: @parameters,
        created_by: current_user,
        status: :generating
      )
      
      ReportGenerationJob.perform_later(@report.id)
    end
  end
end
```

## Chart Visualization
```erb
<!-- Revenue trend chart using Chart.js -->
<div class="report-section">
  <h3>Revenue Trends</h3>
  <canvas id="revenue-chart" width="400" height="200"></canvas>
</div>

<script>
document.addEventListener('DOMContentLoaded', function() {
  const ctx = document.getElementById('revenue-chart').getContext('2d');
  const chart = new Chart(ctx, {
    type: 'line',
    data: {
      labels: <%= @report.results['monthly_revenue'].keys.to_json.html_safe %>,
      datasets: [{
        label: 'Monthly Revenue',
        data: <%= @report.results['monthly_revenue'].values.to_json.html_safe %>,
        borderColor: '#3B82F6',
        backgroundColor: '#3B82F6',
        tension: 0.1
      }]
    },
    options: {
      responsive: true,
      scales: {
        y: {
          beginAtZero: true,
          ticks: {
            callback: function(value) {
              return '$' + value.toLocaleString();
            }
          }
        }
      }
    }
  });
});
</script>
```

## Dependencies
- Quote Management System (data source)
- Payment Processing (payment status data)
- Chart.js or similar visualization library
- Background Job Processing (Sidekiq)

## Estimate
- All Features: 18 story points (2 weeks)
- Note: This is a Growth Phase epic, not included in MVP
