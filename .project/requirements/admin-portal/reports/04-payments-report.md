# Feature: Outstanding Payments Report

## Overview
Track accounts receivable, identify overdue payments, and provide tools for collection management to improve cash flow and reduce bad debt.

## User Stories
- As a business owner, I want to see outstanding payments so I can follow up on collections
- As a business owner, I want to identify overdue accounts so I can prioritize collection efforts
- As an accountant, I want aging reports for financial analysis and planning

## Tasks

### 1. Create PaymentsAnalytics Service
**File**: `app/services/payments_analytics_service.rb`

**Implementation Notes**:
```ruby
class PaymentsAnalyticsService
  def initialize(business)
    @business = business
  end
  
  def outstanding_summary
    outstanding_quotes = @business.quotes.accepted
      .where(payment_status: ['pending', 'partial'])
    
    {
      total_outstanding: outstanding_quotes.sum(:total_amount),
      total_invoices: outstanding_quotes.count,
      overdue_amount: calculate_overdue_amount(outstanding_quotes),
      overdue_count: count_overdue_invoices(outstanding_quotes),
      aging_analysis: aging_analysis(outstanding_quotes),
      collection_metrics: collection_metrics
    }
  end
  
  def client_payment_analysis
    client_stats = {}
    
    @business.clients.joins(:quotes).where(quotes: { status: 'accepted' }).each do |client|
      client_quotes = client.quotes.accepted
      outstanding = client_quotes.where(payment_status: ['pending', 'partial'])
      
      client_stats[client.id] = {
        client_name: client.name,
        client_email: client.email,
        total_invoiced: client_quotes.sum(:total_amount),
        total_paid: client_quotes.where(payment_status: 'paid').sum(:total_amount),
        outstanding_amount: outstanding.sum(:total_amount),
        overdue_amount: calculate_client_overdue(outstanding),
        payment_history: client_payment_history(client),
        risk_score: calculate_risk_score(client)
      }
    end
    
    client_stats.values
      .select { |c| c[:outstanding_amount] > 0 }
      .sort_by { |c| c[:overdue_amount] }
      .reverse
  end
  
  def payment_trends
    months_data = []
    12.times do |i|
      month_start = i.months.ago.beginning_of_month
      month_end = i.months.ago.end_of_month
      
      month_quotes = @business.quotes.accepted
        .where(created_at: month_start..month_end)
      
      months_data << {
        month: month_start.strftime('%Y-%m'),
        month_name: month_start.strftime('%B %Y'),
        invoiced: month_quotes.sum(:total_amount),
        collected: month_quotes.where(payment_status: 'paid').sum(:total_amount),
        outstanding: month_quotes.where(payment_status: ['pending', 'partial']).sum(:total_amount)
      }
    end
    
    months_data.reverse
  end
  
  private
  
  def calculate_overdue_amount(quotes)
    quotes.select { |quote| quote.due_date && quote.due_date < Date.current }
          .sum(&:total_amount)
  end
  
  def count_overdue_invoices(quotes)
    quotes.count { |quote| quote.due_date && quote.due_date < Date.current }
  end
  
  def aging_analysis(quotes)
    buckets = {
      'Current' => 0,
      '1-30 days' => 0,
      '31-60 days' => 0,
      '61-90 days' => 0,
      '90+ days' => 0
    }
    
    quotes.each do |quote|
      next unless quote.due_date
      
      days_overdue = (Date.current - quote.due_date).to_i
      
      case days_overdue
      when -Float::INFINITY..0
        buckets['Current'] += quote.total_amount
      when 1..30
        buckets['1-30 days'] += quote.total_amount
      when 31..60
        buckets['31-60 days'] += quote.total_amount
      when 61..90
        buckets['61-90 days'] += quote.total_amount
      else
        buckets['90+ days'] += quote.total_amount
      end
    end
    
    buckets
  end
  
  def collection_metrics
    last_30_days = @business.quotes.accepted
      .where(payment_received_at: 30.days.ago..Date.current)
    
    {
      collections_last_30_days: last_30_days.sum(:total_amount),
      average_collection_time: calculate_average_collection_time,
      collection_success_rate: calculate_collection_success_rate
    }
  end
  
  def calculate_average_collection_time
    paid_quotes = @business.quotes.accepted
      .where(payment_status: 'paid')
      .where.not(payment_received_at: nil)
      .where('payment_received_at > ?', 6.months.ago)
    
    return 0 if paid_quotes.empty?
    
    total_days = paid_quotes.sum do |quote|
      (quote.payment_received_at.to_date - quote.created_at.to_date).to_i
    end
    
    (total_days / paid_quotes.count).round(1)
  end
  
  def calculate_collection_success_rate
    quotes_6_months = @business.quotes.accepted
      .where('created_at < ?', 3.months.ago)
    
    return 0 if quotes_6_months.empty?
    
    paid_quotes = quotes_6_months.where(payment_status: 'paid').count
    (paid_quotes.to_f / quotes_6_months.count * 100).round(1)
  end
  
  def calculate_risk_score(client)
    score = 0
    
    # Payment history factor
    overdue_count = client.quotes.accepted
      .where('due_date < ?', Date.current)
      .where(payment_status: ['pending', 'partial'])
      .count
    
    score += overdue_count * 20
    
    # Amount factor
    outstanding = client.quotes.accepted
      .where(payment_status: ['pending', 'partial'])
      .sum(:total_amount)
    
    score += 10 if outstanding > 1000
    score += 20 if outstanding > 5000
    
    [score, 100].min
  end
end
```

### 2. Create OutstandingPaymentsController
**File**: `app/controllers/admin/outstanding_payments_controller.rb`

**Implementation Notes**:
```ruby
class Admin::OutstandingPaymentsController < Admin::BaseController
  before_action :ensure_can_view_financials
  
  def index
    @analytics_service = PaymentsAnalyticsService.new(current_business)
    @summary = @analytics_service.outstanding_summary
    @client_analysis = @analytics_service.client_payment_analysis
    @payment_trends = @analytics_service.payment_trends
  end
  
  def client_detail
    @client = current_business.clients.find(params[:client_id])
    @outstanding_quotes = @client.quotes.accepted
      .where(payment_status: ['pending', 'partial'])
      .order(:due_date)
    @payment_history = @client.quotes.accepted
      .where(payment_status: 'paid')
      .order(payment_received_at: :desc)
      .limit(10)
  end
  
  def send_reminder
    @quote = current_business.quotes.find(params[:quote_id])
    
    if @quote.payment_status.in?(['pending', 'partial'])
      PaymentReminderMailer.send_reminder(@quote).deliver_later
      @quote.update!(last_reminder_sent_at: Time.current)
      
      redirect_back(fallback_location: admin_outstanding_payments_path,
                    notice: 'Payment reminder sent successfully')
    else
      redirect_back(fallback_location: admin_outstanding_payments_path,
                    alert: 'Cannot send reminder for paid invoice')
    end
  end
  
  def mark_as_paid
    @quote = current_business.quotes.find(params[:quote_id])
    
    @quote.update!(
      payment_status: 'paid',
      payment_received_at: Time.current,
      payment_method: params[:payment_method] || 'manual'
    )
    
    redirect_back(fallback_location: admin_outstanding_payments_path,
                  notice: 'Payment marked as received')
  end
  
  def export_aging_report
    @analytics_service = PaymentsAnalyticsService.new(current_business)
    
    respond_to do |format|
      format.csv do
        csv_data = generate_aging_csv
        send_data csv_data,
                  filename: "aging_report_#{Date.current}.csv",
                  type: 'text/csv'
      end
      format.pdf do
        pdf_data = generate_aging_pdf
        send_data pdf_data,
                  filename: "aging_report_#{Date.current}.pdf",
                  type: 'application/pdf'
      end
    end
  end
  
  private
  
  def generate_aging_csv
    require 'csv'
    
    CSV.generate(headers: true) do |csv|
      csv << ['Client Name', 'Invoice #', 'Invoice Date', 'Due Date', 'Amount', 'Days Overdue', 'Status']
      
      current_business.quotes.accepted
        .where(payment_status: ['pending', 'partial'])
        .includes(:client)
        .order(:due_date)
        .each do |quote|
          days_overdue = quote.due_date ? (Date.current - quote.due_date).to_i : 0
          
          csv << [
            quote.client.name,
            quote.id,
            quote.created_at.strftime('%Y-%m-%d'),
            quote.due_date&.strftime('%Y-%m-%d') || 'N/A',
            quote.total_amount,
            days_overdue > 0 ? days_overdue : 0,
            quote.payment_status.humanize
          ]
        end
    end
  end
  
  def ensure_can_view_financials
    unless current_business_user.can_view_business_settings?
      redirect_to admin_dashboard_path, alert: 'Access denied'
    end
  end
end
```

## Acceptance Criteria
- Outstanding payments are accurately calculated and categorized
- Aging analysis shows payment distribution across time buckets
- Client payment analysis identifies high-risk accounts
- Payment reminders can be sent to overdue clients
- Aging reports can be exported in CSV and PDF formats
- Collection metrics track payment performance over time

## Estimate
- Story Points: 10
- Timeline: 1 week
- Dependencies: Quote model, Client model, payment tracking system
