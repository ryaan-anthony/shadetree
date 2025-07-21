# Feature: Quote Conversion Tracking

## Overview
Analyze quote-to-sale conversion rates, identify patterns in customer behavior, and provide insights to improve sales performance and quote accuracy.

## User Stories
- As a business owner, I want to track my quote conversion rates so I can improve my sales process
- As a business owner, I want to see which services convert best so I can focus my marketing
- As a business owner, I want to understand why quotes are rejected so I can improve them

## Tasks

### 1. Create ConversionAnalytics Service
**File**: `app/services/conversion_analytics_service.rb`

**Implementation Notes**:
```ruby
class ConversionAnalyticsService
  def initialize(business, period = 30.days)
    @business = business
    @period = period
    @quotes = business.quotes.where(created_at: period.ago..)
  end
  
  def conversion_summary
    total_quotes = @quotes.count
    accepted_quotes = @quotes.accepted.count
    
    {
      total_quotes: total_quotes,
      accepted_quotes: accepted_quotes,
      conversion_rate: calculate_conversion_rate(total_quotes, accepted_quotes),
      average_quote_value: @quotes.accepted.average(:total_amount)&.round(2) || 0,
      total_revenue: @quotes.accepted.sum(:total_amount),
      quotes_by_status: quote_status_breakdown,
      conversion_trends: monthly_conversion_trends
    }
  end
  
  def service_conversion_analysis
    service_stats = {}
    
    @quotes.joins(:quote_line_items).group('quote_line_items.service_name').each do |service_name, quotes|
      total = quotes.count
      accepted = quotes.accepted.count
      
      service_stats[service_name] = {
        total_quotes: total,
        accepted_quotes: accepted,
        conversion_rate: calculate_conversion_rate(total, accepted),
        average_value: quotes.accepted.average(:total_amount)&.round(2) || 0,
        total_revenue: quotes.accepted.sum(:total_amount)
      }
    end
    
    service_stats.values.sort_by { |s| s[:conversion_rate] }.reverse
  end
  
  def quote_value_analysis
    value_ranges = {
      '0-500' => 0..500,
      '501-1000' => 501..1000,
      '1001-2500' => 1001..2500,
      '2501-5000' => 2501..5000,
      '5000+' => 5001..Float::INFINITY
    }
    
    value_ranges.map do |range_name, range|
      quotes_in_range = @quotes.where(total_amount: range)
      total = quotes_in_range.count
      accepted = quotes_in_range.accepted.count
      
      {
        value_range: range_name,
        total_quotes: total,
        accepted_quotes: accepted,
        conversion_rate: calculate_conversion_rate(total, accepted),
        percentage_of_total: total > 0 ? (total.to_f / @quotes.count * 100).round(1) : 0
      }
    end
  end
  
  def response_time_analysis
    time_ranges = {
      'Same Day' => 0..1,
      '1-3 Days' => 1..3,
      '4-7 Days' => 4..7,
      '8-14 Days' => 8..14,
      '15+ Days' => 15..Float::INFINITY
    }
    
    time_ranges.map do |range_name, range|
      quotes_in_range = @quotes.select do |quote|
        next false unless quote.sent_at && quote.responded_at
        days_to_respond = (quote.responded_at - quote.sent_at) / 1.day
        range.include?(days_to_respond)
      end
      
      total = quotes_in_range.count
      accepted = quotes_in_range.count { |q| q.accepted? }
      
      {
        response_time: range_name,
        total_quotes: total,
        accepted_quotes: accepted,
        conversion_rate: calculate_conversion_rate(total, accepted)
      }
    end
  end
  
  private
  
  def calculate_conversion_rate(total, accepted)
    return 0 if total.zero?
    (accepted.to_f / total * 100).round(1)
  end
  
  def quote_status_breakdown
    @quotes.group(:status).count
  end
  
  def monthly_conversion_trends
    monthly_data = []
    current_date = @period.ago.beginning_of_month
    
    while current_date <= Date.current
      month_end = [current_date.end_of_month, Date.current].min
      month_quotes = @quotes.where(created_at: current_date..month_end)
      
      total = month_quotes.count
      accepted = month_quotes.accepted.count
      
      monthly_data << {
        month: current_date.strftime('%Y-%m'),
        month_name: current_date.strftime('%B %Y'),
        total_quotes: total,
        accepted_quotes: accepted,
        conversion_rate: calculate_conversion_rate(total, accepted)
      }
      
      current_date = current_date.next_month
    end
    
    monthly_data
  end
end
```

### 2. Create ConversionTrackingController
**File**: `app/controllers/admin/conversion_tracking_controller.rb`

**Implementation Notes**:
```ruby
class Admin::ConversionTrackingController < Admin::BaseController
  before_action :ensure_can_view_analytics
  
  def index
    @period = params[:period]&.to_i&.days || 30.days
    @analytics_service = ConversionAnalyticsService.new(current_business, @period)
    
    @conversion_summary = @analytics_service.conversion_summary
    @service_analysis = @analytics_service.service_conversion_analysis
    @value_analysis = @analytics_service.quote_value_analysis
    @response_analysis = @analytics_service.response_time_analysis
  end
  
  def detailed_analysis
    @quote = current_business.quotes.find(params[:quote_id])
    @timeline = build_quote_timeline(@quote)
    @similar_quotes = find_similar_quotes(@quote)
  end
  
  private
  
  def build_quote_timeline(quote)
    events = []
    
    events << { event: 'Quote Created', date: quote.created_at, status: 'info' }
    events << { event: 'Quote Sent', date: quote.sent_at, status: 'info' } if quote.sent_at
    events << { event: 'Quote Viewed', date: quote.viewed_at, status: 'info' } if quote.viewed_at
    
    if quote.responded_at
      status = quote.accepted? ? 'success' : 'warning'
      events << { event: "Quote #{quote.status.humanize}", date: quote.responded_at, status: status }
    end
    
    events.sort_by { |e| e[:date] }
  end
  
  def find_similar_quotes(quote)
    current_business.quotes
      .where.not(id: quote.id)
      .where(total_amount: (quote.total_amount * 0.8)..(quote.total_amount * 1.2))
      .limit(5)
  end
  
  def ensure_can_view_analytics
    unless current_business_user.can_view_business_settings?
      redirect_to admin_dashboard_path, alert: 'Access denied'
    end
  end
end
```

## Acceptance Criteria
- Overall conversion rate is calculated accurately across all quotes
- Service-specific conversion rates identify best and worst performing services
- Quote value analysis shows conversion patterns by price range
- Response time analysis correlates customer response speed with conversion
- Monthly trends show conversion rate changes over time

## Estimate
- Story Points: 8
- Timeline: 1 week
- Dependencies: Quote model, QuoteLineItem model
