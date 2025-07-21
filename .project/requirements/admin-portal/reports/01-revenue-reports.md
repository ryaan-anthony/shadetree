# Feature: Revenue Reports

## Overview
Provide comprehensive revenue tracking and analysis capabilities that help business owners understand their financial performance, identify trends, and make data-driven decisions about their service business.

## User Stories
- As a business owner, I want to see my revenue trends so I can understand my business growth
- As a business owner, I want to compare revenue across different time periods
- As an accountant, I want detailed revenue breakdowns for financial reporting

## Tasks

### 1. Create RevenueReport Model
**File**: `app/models/revenue_report.rb`

**Implementation Notes**:
```ruby
class RevenueReport < ApplicationRecord
  belongs_to :business
  belongs_to :generated_by, class_name: 'User'
  
  validates :report_type, :period_start, :period_end, presence: true
  validates :report_data, presence: true
  
  enum report_type: { monthly: 0, quarterly: 1, yearly: 2, custom: 3 }
  enum status: { generating: 0, completed: 1, failed: 2 }
  
  scope :recent, -> { where(created_at: 30.days.ago..) }
  scope :completed, -> { where(status: 'completed') }
  
  def total_revenue
    report_data.dig('summary', 'total_revenue') || 0
  end
  
  def revenue_growth
    report_data.dig('summary', 'growth_rate') || 0
  end
  
  def top_services
    report_data.dig('service_breakdown') || {}
  end
end
```

### 2. Create RevenueReportService
**File**: `app/services/revenue_report_service.rb`

**Implementation Notes**:
```ruby
class RevenueReportService
  def initialize(business)
    @business = business
  end
  
  def generate_monthly_report(year = Date.current.year, month = Date.current.month)
    start_date = Date.new(year, month, 1)
    end_date = start_date.end_of_month
    
    generate_report(start_date, end_date, 'monthly')
  end
  
  def generate_quarterly_report(year = Date.current.year, quarter = current_quarter)
    start_date = Date.new(year, (quarter - 1) * 3 + 1, 1)
    end_date = start_date + 3.months - 1.day
    
    generate_report(start_date, end_date, 'quarterly')
  end
  
  def generate_custom_report(start_date, end_date)
    generate_report(start_date, end_date, 'custom')
  end
  
  private
  
  def generate_report(start_date, end_date, report_type)
    # Get base revenue data
    quotes = @business.quotes.accepted
      .where(created_at: start_date..end_date)
      .includes(:quote_line_items, :client)
    
    # Calculate summary metrics
    summary = calculate_summary_metrics(quotes, start_date, end_date)
    
    # Service breakdown
    service_breakdown = calculate_service_breakdown(quotes)
    
    # Monthly trend data
    monthly_trends = calculate_monthly_trends(start_date, end_date)
    
    # Client analysis
    client_analysis = calculate_client_metrics(quotes)
    
    # Payment status analysis
    payment_analysis = calculate_payment_metrics(quotes)
    
    {
      summary: summary,
      service_breakdown: service_breakdown,
      monthly_trends: monthly_trends,
      client_analysis: client_analysis,
      payment_analysis: payment_analysis,
      report_metadata: {
        period_start: start_date,
        period_end: end_date,
        report_type: report_type,
        generated_at: Time.current,
        quote_count: quotes.count
      }
    }
  end
  
  def calculate_summary_metrics(quotes, start_date, end_date)
    total_revenue = quotes.sum(:total_amount)
    
    # Compare with previous period
    previous_period_start = start_date - (end_date - start_date + 1.day)
    previous_period_end = start_date - 1.day
    
    previous_revenue = @business.quotes.accepted
      .where(created_at: previous_period_start..previous_period_end)
      .sum(:total_amount)
    
    growth_rate = calculate_growth_rate(total_revenue, previous_revenue)
    
    {
      total_revenue: total_revenue,
      previous_period_revenue: previous_revenue,
      growth_rate: growth_rate,
      average_quote_value: quotes.count > 0 ? (total_revenue / quotes.count).round(2) : 0,
      total_quotes: quotes.count,
      period_days: (end_date - start_date + 1).to_i,
      daily_average: total_revenue / (end_date - start_date + 1).to_i
    }
  end
  
  def calculate_service_breakdown(quotes)
    service_revenue = {}
    service_counts = {}
    
    quotes.each do |quote|
      quote.quote_line_items.each do |line_item|
        service_name = line_item.service_name
        service_revenue[service_name] ||= 0
        service_counts[service_name] ||= 0
        
        service_revenue[service_name] += line_item.total_price
        service_counts[service_name] += 1
      end
    end
    
    # Calculate percentages
    total_revenue = service_revenue.values.sum
    
    service_revenue.map do |service, revenue|
      {
        service_name: service,
        revenue: revenue,
        percentage: total_revenue > 0 ? (revenue / total_revenue * 100).round(1) : 0,
        quote_count: service_counts[service],
        average_value: service_counts[service] > 0 ? (revenue / service_counts[service]).round(2) : 0
      }
    end.sort_by { |s| s[:revenue] }.reverse
  end
  
  def calculate_monthly_trends(start_date, end_date)
    monthly_data = []
    current_date = start_date.beginning_of_month
    
    while current_date <= end_date
      month_end = [current_date.end_of_month, end_date].min
      
      month_quotes = @business.quotes.accepted
        .where(created_at: current_date..month_end)
      
      monthly_data << {
        month: current_date.strftime('%Y-%m'),
        month_name: current_date.strftime('%B %Y'),
        revenue: month_quotes.sum(:total_amount),
        quote_count: month_quotes.count,
        average_quote_value: month_quotes.count > 0 ? (month_quotes.sum(:total_amount) / month_quotes.count).round(2) : 0
      }
      
      current_date = current_date.next_month
    end
    
    monthly_data
  end
  
  def calculate_client_metrics(quotes)
    client_revenue = quotes.group(:client_id).sum(:total_amount)
    client_counts = quotes.group(:client_id).count
    
    top_clients = client_revenue.sort_by { |_, revenue| revenue }.reverse.first(10)
    
    top_clients.map do |client_id, revenue|
      client = Client.find(client_id)
      {
        client_name: client.name,
        client_email: client.email,
        total_revenue: revenue,
        quote_count: client_counts[client_id],
        average_quote_value: (revenue / client_counts[client_id]).round(2),
        first_quote_date: client.quotes.minimum(:created_at)
      }
    end
  end
  
  def calculate_payment_metrics(quotes)
    total_amount = quotes.sum(:total_amount)
    
    payment_status_breakdown = quotes.group(:payment_status).sum(:total_amount)
    
    {
      total_invoiced: total_amount,
      paid_amount: payment_status_breakdown['paid'] || 0,
      pending_amount: payment_status_breakdown['pending'] || 0,
      overdue_amount: payment_status_breakdown['overdue'] || 0,
      collection_rate: total_amount > 0 ? ((payment_status_breakdown['paid'] || 0) / total_amount * 100).round(1) : 0
    }
  end
  
  def calculate_growth_rate(current, previous)
    return 0 if previous.zero?
    ((current - previous) / previous * 100).round(1)
  end
  
  def current_quarter
    (Date.current.month - 1) / 3 + 1
  end
end
```

### 3. Create RevenueReportsController
**File**: `app/controllers/admin/revenue_reports_controller.rb`

**Implementation Notes**:
```ruby
class Admin::RevenueReportsController < Admin::BaseController
  before_action :ensure_can_view_financials
  
  def index
    @recent_reports = current_business.revenue_reports
      .completed
      .recent
      .order(created_at: :desc)
      .limit(10)
    
    @quick_stats = calculate_quick_stats
  end
  
  def show
    @report = current_business.revenue_reports.find(params[:id])
    @report_data = @report.report_data
  end
  
  def new
    @report_types = revenue_report_types
    @preset_periods = preset_periods
  end
  
  def create
    case params[:report_type]
    when 'monthly'
      generate_monthly_report
    when 'quarterly'
      generate_quarterly_report
    when 'custom'
      generate_custom_report
    else
      redirect_to new_admin_revenue_report_path, alert: 'Invalid report type'
    end
  end
  
  def download
    @report = current_business.revenue_reports.find(params[:id])
    
    respond_to do |format|
      format.pdf do
        pdf_data = RevenueReportPdfGenerator.new(@report).generate
        send_data pdf_data,
                  filename: "revenue_report_#{@report.id}.pdf",
                  type: 'application/pdf'
      end
      format.csv do
        csv_data = RevenueReportCsvGenerator.new(@report).generate
        send_data csv_data,
                  filename: "revenue_report_#{@report.id}.csv",
                  type: 'text/csv'
      end
    end
  end
  
  private
  
  def generate_monthly_report
    year = params[:year]&.to_i || Date.current.year
    month = params[:month]&.to_i || Date.current.month
    
    service = RevenueReportService.new(current_business)
    report_data = service.generate_monthly_report(year, month)
    
    report = current_business.revenue_reports.create!(
      report_type: 'monthly',
      period_start: Date.new(year, month, 1),
      period_end: Date.new(year, month, 1).end_of_month,
      report_data: report_data,
      generated_by: current_user,
      status: 'completed'
    )
    
    redirect_to admin_revenue_report_path(report), notice: 'Monthly revenue report generated'
  end
  
  def generate_quarterly_report
    year = params[:year]&.to_i || Date.current.year
    quarter = params[:quarter]&.to_i || current_quarter
    
    service = RevenueReportService.new(current_business)
    report_data = service.generate_quarterly_report(year, quarter)
    
    start_date = Date.new(year, (quarter - 1) * 3 + 1, 1)
    end_date = start_date + 3.months - 1.day
    
    report = current_business.revenue_reports.create!(
      report_type: 'quarterly',
      period_start: start_date,
      period_end: end_date,
      report_data: report_data,
      generated_by: current_user,
      status: 'completed'
    )
    
    redirect_to admin_revenue_report_path(report), notice: 'Quarterly revenue report generated'
  end
  
  def generate_custom_report
    start_date = Date.parse(params[:start_date])
    end_date = Date.parse(params[:end_date])
    
    service = RevenueReportService.new(current_business)
    report_data = service.generate_custom_report(start_date, end_date)
    
    report = current_business.revenue_reports.create!(
      report_type: 'custom',
      period_start: start_date,
      period_end: end_date,
      report_data: report_data,
      generated_by: current_user,
      status: 'completed'
    )
    
    redirect_to admin_revenue_report_path(report), notice: 'Custom revenue report generated'
  end
  
  def calculate_quick_stats
    {
      this_month: RevenueReportService.new(current_business).generate_monthly_report.dig(:summary, :total_revenue) || 0,
      last_month: RevenueReportService.new(current_business).generate_monthly_report(Date.current.year, Date.current.month - 1).dig(:summary, :total_revenue) || 0,
      ytd: calculate_ytd_revenue,
      last_year: calculate_last_year_revenue
    }
  end
  
  def calculate_ytd_revenue
    current_business.quotes.accepted
      .where(created_at: Date.current.beginning_of_year..Date.current)
      .sum(:total_amount)
  end
  
  def calculate_last_year_revenue
    last_year_start = 1.year.ago.beginning_of_year
    last_year_end = 1.year.ago.end_of_year
    
    current_business.quotes.accepted
      .where(created_at: last_year_start..last_year_end)
      .sum(:total_amount)
  end
  
  def revenue_report_types
    [
      ['Monthly Report', 'monthly'],
      ['Quarterly Report', 'quarterly'],
      ['Custom Date Range', 'custom']
    ]
  end
  
  def preset_periods
    [
      ['This Month', 'this_month'],
      ['Last Month', 'last_month'],
      ['This Quarter', 'this_quarter'],
      ['Last Quarter', 'last_quarter'],
      ['Year to Date', 'ytd'],
      ['Last Year', 'last_year']
    ]
  end
  
  def current_quarter
    (Date.current.month - 1) / 3 + 1
  end
  
  def ensure_can_view_financials
    unless current_business_user.can_view_business_settings?
      redirect_to admin_dashboard_path, alert: 'Access denied'
    end
  end
end
```

### 4. Create Revenue Report PDF Generator
**File**: `app/services/revenue_report_pdf_generator.rb`

**Implementation Notes**:
```ruby
class RevenueReportPdfGenerator
  def initialize(report)
    @report = report
    @data = report.report_data
    @business = report.business
  end
  
  def generate
    pdf = Prawn::Document.new
    
    # Header
    add_header(pdf)
    
    # Summary section
    add_summary_section(pdf)
    
    # Service breakdown
    add_service_breakdown(pdf)
    
    # Monthly trends chart
    add_trends_section(pdf)
    
    # Client analysis
    add_client_analysis(pdf)
    
    # Footer
    add_footer(pdf)
    
    pdf.render
  end
  
  private
  
  def add_header(pdf)
    pdf.text @business.name, size: 24, style: :bold
    pdf.text "Revenue Report", size: 20, style: :bold
    pdf.text "Period: #{@report.period_start.strftime('%B %d, %Y')} - #{@report.period_end.strftime('%B %d, %Y')}"
    pdf.text "Generated: #{@report.created_at.strftime('%B %d, %Y at %I:%M %p')}"
    pdf.move_down 20
  end
  
  def add_summary_section(pdf)
    summary = @data['summary']
    
    pdf.text "Summary", size: 16, style: :bold
    pdf.move_down 10
    
    summary_data = [
      ['Total Revenue', format_currency(summary['total_revenue'])],
      ['Total Quotes', summary['total_quotes'].to_s],
      ['Average Quote Value', format_currency(summary['average_quote_value'])],
      ['Growth Rate', "#{summary['growth_rate']}%"],
      ['Daily Average', format_currency(summary['daily_average'])]
    ]
    
    pdf.table(summary_data, width: pdf.bounds.width) do
      row(0..4).style(borders: [:bottom])
      column(0).style(font_style: :bold)
    end
    
    pdf.move_down 20
  end
  
  def add_service_breakdown(pdf)
    services = @data['service_breakdown']
    return if services.empty?
    
    pdf.text "Service Breakdown", size: 16, style: :bold
    pdf.move_down 10
    
    service_data = [['Service', 'Revenue', 'Percentage', 'Quotes']]
    
    services.first(10).each do |service|
      service_data << [
        service['service_name'],
        format_currency(service['revenue']),
        "#{service['percentage']}%",
        service['quote_count'].to_s
      ]
    end
    
    pdf.table(service_data, header: true, width: pdf.bounds.width) do
      row(0).style(font_style: :bold, background_color: 'f0f0f0')
    end
    
    pdf.move_down 20
  end
  
  def add_trends_section(pdf)
    trends = @data['monthly_trends']
    return if trends.empty?
    
    pdf.text "Monthly Trends", size: 16, style: :bold
    pdf.move_down 10
    
    trend_data = [['Month', 'Revenue', 'Quotes', 'Avg Quote Value']]
    
    trends.each do |month_data|
      trend_data << [
        month_data['month_name'],
        format_currency(month_data['revenue']),
        month_data['quote_count'].to_s,
        format_currency(month_data['average_quote_value'])
      ]
    end
    
    pdf.table(trend_data, header: true, width: pdf.bounds.width) do
      row(0).style(font_style: :bold, background_color: 'f0f0f0')
    end
    
    pdf.move_down 20
  end
  
  def add_client_analysis(pdf)
    clients = @data['client_analysis']
    return if clients.empty?
    
    pdf.text "Top Clients", size: 16, style: :bold
    pdf.move_down 10
    
    client_data = [['Client', 'Revenue', 'Quotes', 'Avg Value']]
    
    clients.first(10).each do |client|
      client_data << [
        client['client_name'],
        format_currency(client['total_revenue']),
        client['quote_count'].to_s,
        format_currency(client['average_quote_value'])
      ]
    end
    
    pdf.table(client_data, header: true, width: pdf.bounds.width) do
      row(0).style(font_style: :bold, background_color: 'f0f0f0')
    end
  end
  
  def add_footer(pdf)
    pdf.move_down 30
    pdf.text "Generated by Shadetree Platform", size: 8, style: :italic, align: :center
  end
  
  def format_currency(amount)
    "$#{sprintf('%.2f', amount)}"
  end
end
```

### 5. Create Database Migration
**File**: `db/migrate/xxx_create_revenue_reports.rb`

**Implementation Notes**:
```ruby
class CreateRevenueReports < ActiveRecord::Migration[8.0]
  def change
    create_table :revenue_reports do |t|
      t.references :business, null: false, foreign_key: true
      t.references :generated_by, null: false, foreign_key: { to_table: :users }
      t.integer :report_type, null: false
      t.date :period_start, null: false
      t.date :period_end, null: false
      t.json :report_data, null: false
      t.integer :status, default: 0
      t.text :error_message
      
      t.timestamps
    end
    
    add_index :revenue_reports, [:business_id, :report_type]
    add_index :revenue_reports, [:business_id, :period_start, :period_end]
    add_index :revenue_reports, [:business_id, :created_at]
  end
end
```

## Acceptance Criteria
- Monthly, quarterly, and custom date range revenue reports can be generated
- Reports include revenue trends, service breakdowns, and client analysis
- Reports can be exported as PDF and CSV formats
- Growth rate calculations compare with previous periods
- Service performance is ranked by revenue contribution
- Top clients are identified with their contribution metrics

## Estimate
- Story Points: 13
- Timeline: 1.5 weeks
- Dependencies: Quote model, Client model, PDF generation library (Prawn)
