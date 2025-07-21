# Feature: Job Performance Analytics

## Overview
Provide comprehensive analytics on job execution, staff performance, and operational efficiency to help business owners optimize their service delivery and resource allocation.

## User Stories
- As a business owner, I want to analyze job completion times so I can improve efficiency
- As a business owner, I want to see staff performance metrics so I can provide feedback
- As a business owner, I want to identify bottlenecks in my operations

## Tasks

### 1. Create JobAnalytics Service
**File**: `app/services/job_analytics_service.rb`

**Implementation Notes**:
```ruby
class JobAnalyticsService
  def initialize(business, period = 30.days)
    @business = business
    @period = period
    @jobs = business.jobs.where(created_at: period.ago..)
  end
  
  def performance_summary
    {
      total_jobs: @jobs.count,
      completed_jobs: @jobs.completed.count,
      completion_rate: calculate_completion_rate,
      average_duration: calculate_average_duration,
      on_time_completion: calculate_on_time_rate,
      staff_utilization: calculate_staff_utilization,
      service_efficiency: calculate_service_efficiency
    }
  end
  
  def staff_performance
    staff_stats = {}
    
    @business.users.joins(:assigned_jobs).each do |staff|
      staff_jobs = staff.assigned_jobs.where(created_at: @period.ago..)
      
      staff_stats[staff.id] = {
        name: staff.name,
        total_jobs: staff_jobs.count,
        completed_jobs: staff_jobs.completed.count,
        completion_rate: calculate_staff_completion_rate(staff_jobs),
        average_duration: calculate_staff_average_duration(staff_jobs),
        customer_rating: calculate_average_rating(staff_jobs),
        revenue_generated: calculate_staff_revenue(staff_jobs)
      }
    end
    
    staff_stats.values.sort_by { |s| s[:completion_rate] }.reverse
  end
  
  def service_efficiency_breakdown
    service_stats = {}
    
    @jobs.joins(:quote).group('quotes.service_type').each do |service_type, jobs|
      completed_jobs = jobs.completed
      
      service_stats[service_type] = {
        total_jobs: jobs.count,
        completed_jobs: completed_jobs.count,
        average_duration: calculate_service_duration(completed_jobs),
        profitability: calculate_service_profitability(jobs),
        customer_satisfaction: calculate_service_satisfaction(completed_jobs)
      }
    end
    
    service_stats
  end
  
  private
  
  def calculate_completion_rate
    return 0 if @jobs.count.zero?
    (@jobs.completed.count.to_f / @jobs.count * 100).round(1)
  end
  
  def calculate_average_duration
    completed_jobs = @jobs.completed.where.not(started_at: nil, completed_at: nil)
    return 0 if completed_jobs.empty?
    
    total_duration = completed_jobs.sum do |job|
      (job.completed_at - job.started_at) / 1.hour
    end
    
    (total_duration / completed_jobs.count).round(1)
  end
  
  def calculate_on_time_rate
    scheduled_jobs = @jobs.where.not(scheduled_date: nil).completed
    return 0 if scheduled_jobs.empty?
    
    on_time_jobs = scheduled_jobs.select do |job|
      job.completed_at <= job.scheduled_date.end_of_day
    end
    
    (on_time_jobs.count.to_f / scheduled_jobs.count * 100).round(1)
  end
  
  def calculate_staff_utilization
    total_staff = @business.users.where(business_users: { role: ['admin', 'staff'] }).count
    return 0 if total_staff.zero?
    
    active_staff = @business.users
      .joins(:assigned_jobs)
      .where(jobs: { created_at: @period.ago.. })
      .distinct
      .count
      
    (active_staff.to_f / total_staff * 100).round(1)
  end
end
```

### 2. Create JobAnalyticsController
**File**: `app/controllers/admin/job_analytics_controller.rb`

**Implementation Notes**:
```ruby
class Admin::JobAnalyticsController < Admin::BaseController
  before_action :ensure_can_view_analytics
  
  def index
    @period = params[:period]&.to_i&.days || 30.days
    @analytics_service = JobAnalyticsService.new(current_business, @period)
    @summary = @analytics_service.performance_summary
    @staff_performance = @analytics_service.staff_performance
    @service_efficiency = @analytics_service.service_efficiency_breakdown
  end
  
  def staff_detail
    @staff = current_business.users.find(params[:staff_id])
    @period = params[:period]&.to_i&.days || 30.days
    @staff_jobs = @staff.assigned_jobs
      .where(business: current_business, created_at: @period.ago..)
      .includes(:client, :quote)
    @performance_metrics = calculate_staff_metrics(@staff_jobs)
  end
  
  def export
    @analytics_service = JobAnalyticsService.new(current_business)
    
    respond_to do |format|
      format.csv do
        csv_data = generate_analytics_csv
        send_data csv_data,
                  filename: "job_analytics_#{Date.current}.csv",
                  type: 'text/csv'
      end
    end
  end
  
  private
  
  def calculate_staff_metrics(jobs)
    {
      total_jobs: jobs.count,
      completed_jobs: jobs.completed.count,
      average_duration: calculate_average_duration(jobs.completed),
      on_time_completion: calculate_on_time_completion(jobs),
      customer_ratings: jobs.where.not(customer_rating: nil).average(:customer_rating)&.round(1)
    }
  end
  
  def ensure_can_view_analytics
    unless current_business_user.can_view_business_settings?
      redirect_to admin_dashboard_path, alert: 'Access denied'
    end
  end
end
```

## Acceptance Criteria
- Job completion rates and duration analytics are calculated accurately
- Staff performance metrics include completion rates and customer ratings
- Service efficiency breakdown shows profitability by service type
- Analytics can be filtered by time period
- Data can be exported for external analysis

## Estimate
- Story Points: 8
- Timeline: 1 week
- Dependencies: Job model, User model, Quote model
