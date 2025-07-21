# Feature: Workflow Monitoring

## Overview
Provide comprehensive monitoring and analytics for workflow executions, allowing business owners to track performance, identify bottlenecks, and optimize their automated processes.

## User Stories
- As a business owner, I want to monitor workflow execution status so I can ensure automations are working
- As a business owner, I want to see workflow performance metrics so I can optimize my processes
- As a business owner, I want to be alerted when workflows fail so I can take corrective action

## Tasks

### 1. Create WorkflowMonitoringService
**File**: `app/services/workflow_monitoring_service.rb`

**Implementation Notes**:
```ruby
class WorkflowMonitoringService
  def initialize(business)
    @business = business
  end
  
  def dashboard_metrics
    {
      total_workflows: @business.workflows.count,
      active_workflows: @business.workflows.active.count,
      executions_today: executions_for_period(1.day.ago),
      executions_this_week: executions_for_period(1.week.ago),
      success_rate: calculate_success_rate,
      avg_execution_time: calculate_avg_execution_time,
      failed_executions_today: failed_executions_for_period(1.day.ago),
      top_performing_workflows: top_performing_workflows,
      bottleneck_steps: identify_bottleneck_steps
    }
  end
  
  def workflow_performance(workflow, period = 30.days)
    executions = workflow.workflow_executions.where(created_at: period.ago..)
    
    {
      total_executions: executions.count,
      success_rate: calculate_workflow_success_rate(executions),
      avg_execution_time: calculate_workflow_avg_time(executions),
      execution_trend: execution_trend_data(executions),
      step_performance: step_performance_data(workflow),
      failure_reasons: failure_analysis(executions)
    }
  end
  
  def real_time_status
    {
      running_executions: running_executions_count,
      queued_jobs: queued_workflow_jobs_count,
      recent_failures: recent_failures(limit: 5),
      system_health: calculate_system_health
    }
  end
  
  private
  
  def executions_for_period(period_start)
    @business.workflows
      .joins(:workflow_executions)
      .where('workflow_executions.created_at > ?', period_start)
      .count
  end
  
  def failed_executions_for_period(period_start)
    @business.workflows
      .joins(:workflow_executions)
      .where('workflow_executions.created_at > ? AND workflow_executions.status = ?', 
             period_start, WorkflowExecution.statuses[:failed])
      .count
  end
  
  def calculate_success_rate
    total = executions_for_period(30.days.ago)
    return 100.0 if total.zero?
    
    successful = @business.workflows
      .joins(:workflow_executions)
      .where('workflow_executions.created_at > ? AND workflow_executions.status = ?',
             30.days.ago, WorkflowExecution.statuses[:completed])
      .count
      
    (successful.to_f / total * 100).round(1)
  end
  
  def calculate_avg_execution_time
    completed_executions = @business.workflows
      .joins(:workflow_executions)
      .where('workflow_executions.status = ? AND workflow_executions.created_at > ?',
             WorkflowExecution.statuses[:completed], 30.days.ago)
    
    return 0 if completed_executions.empty?
    
    total_time = completed_executions.sum do |workflow|
      workflow.workflow_executions.completed.sum do |execution|
        execution.execution_time || 0
      end
    end
    
    (total_time / completed_executions.count).round(2)
  end
  
  def top_performing_workflows(limit = 5)
    @business.workflows.active
      .left_joins(:workflow_executions)
      .group('workflows.id')
      .order('COUNT(workflow_executions.id) DESC')
      .limit(limit)
      .includes(:workflow_executions)
      .map do |workflow|
        {
          workflow: workflow,
          execution_count: workflow.executions_count,
          success_rate: workflow.success_rate
        }
      end
  end
  
  def identify_bottleneck_steps
    # Find steps that take longest or fail most often
    step_stats = @business.workflows
      .joins(workflow_steps: :workflow_step_executions)
      .where('workflow_step_executions.created_at > ?', 7.days.ago)
      .group('workflow_steps.id', 'workflow_steps.name', 'workflow_steps.action_type')
      .select(
        'workflow_steps.id',
        'workflow_steps.name',
        'workflow_steps.action_type',
        'AVG(EXTRACT(EPOCH FROM (workflow_step_executions.completed_at - workflow_step_executions.started_at))) as avg_duration',
        'COUNT(*) as execution_count',
        'COUNT(CASE WHEN workflow_step_executions.status = 3 THEN 1 END) as failure_count'
      )
      .having('COUNT(*) > 5') # Only consider steps with significant volume
      .order('avg_duration DESC NULLS LAST')
      .limit(5)
      
    step_stats.map do |stat|
      {
        step_name: stat.name,
        action_type: stat.action_type,
        avg_duration: stat.avg_duration&.round(2),
        execution_count: stat.execution_count,
        failure_rate: (stat.failure_count.to_f / stat.execution_count * 100).round(1)
      }
    end
  end
  
  def running_executions_count
    @business.workflows
      .joins(:workflow_executions)
      .where('workflow_executions.status = ?', WorkflowExecution.statuses[:running])
      .count
  end
  
  def queued_workflow_jobs_count
    # This would depend on your job queue implementation
    # For Sidekiq:
    Sidekiq::Queue.new('workflows').size
  rescue
    0
  end
  
  def recent_failures(limit: 5)
    @business.workflows
      .joins(:workflow_executions)
      .where('workflow_executions.status = ? AND workflow_executions.failed_at > ?',
             WorkflowExecution.statuses[:failed], 24.hours.ago)
      .order('workflow_executions.failed_at DESC')
      .limit(limit)
      .includes(:workflow_executions)
      .map do |workflow|
        recent_execution = workflow.workflow_executions.failed.order(failed_at: :desc).first
        {
          workflow_name: workflow.name,
          failed_at: recent_execution.failed_at,
          error_message: recent_execution.error_message,
          execution_id: recent_execution.id
        }
      end
  end
  
  def calculate_system_health
    recent_executions = executions_for_period(1.hour.ago)
    recent_failures = failed_executions_for_period(1.hour.ago)
    
    if recent_executions.zero?
      'idle'
    elsif recent_failures.zero?
      'healthy'
    elsif (recent_failures.to_f / recent_executions) < 0.1
      'warning'
    else
      'critical'
    end
  end
end
```

### 2. Create WorkflowMonitoringController
**File**: `app/controllers/admin/workflow_monitoring_controller.rb`

**Implementation Notes**:
```ruby
class Admin::WorkflowMonitoringController < Admin::BaseController
  before_action :ensure_can_view_workflows
  
  def index
    @monitoring_service = WorkflowMonitoringService.new(current_business)
    @metrics = @monitoring_service.dashboard_metrics
    @real_time_status = @monitoring_service.real_time_status
  end
  
  def workflow_details
    @workflow = current_business.workflows.find(params[:workflow_id])
    @monitoring_service = WorkflowMonitoringService.new(current_business)
    @performance = @monitoring_service.workflow_performance(@workflow)
    @recent_executions = @workflow.workflow_executions
      .includes(:source, :workflow_step_executions)
      .order(created_at: :desc)
      .limit(20)
  end
  
  def execution_details
    @execution = current_business.workflows
      .joins(:workflow_executions)
      .find_by!(workflow_executions: { id: params[:execution_id] })
      .workflow_executions
      .find(params[:execution_id])
    
    @step_executions = @execution.workflow_step_executions
      .includes(:workflow_step)
      .order(:created_at)
  end
  
  def retry_execution
    @execution = current_business.workflows
      .joins(:workflow_executions)
      .find_by!(workflow_executions: { id: params[:execution_id] })
      .workflow_executions
      .find(params[:execution_id])
    
    if @execution.failed?
      # Create new execution based on the failed one
      new_execution = @execution.workflow.workflow_executions.create!(
        source: @execution.source,
        triggered_by: current_user,
        status: :running
      )
      
      WorkflowExecutionJob.perform_later(new_execution.id)
      
      redirect_to workflow_monitoring_execution_details_path(new_execution.id),
                  notice: 'Workflow execution retried successfully'
    else
      redirect_back(fallback_location: admin_workflow_monitoring_path,
                    alert: 'Can only retry failed executions')
    end
  end
  
  def cancel_execution
    @execution = current_business.workflows
      .joins(:workflow_executions)
      .find_by!(workflow_executions: { id: params[:execution_id] })
      .workflow_executions
      .find(params[:execution_id])
    
    if @execution.running?
      @execution.update!(status: :cancelled)
      redirect_back(fallback_location: admin_workflow_monitoring_path,
                    notice: 'Workflow execution cancelled')
    else
      redirect_back(fallback_location: admin_workflow_monitoring_path,
                    alert: 'Can only cancel running executions')
    end
  end
  
  def export_metrics
    @monitoring_service = WorkflowMonitoringService.new(current_business)
    metrics = @monitoring_service.dashboard_metrics
    
    respond_to do |format|
      format.csv do
        csv_data = generate_metrics_csv(metrics)
        send_data csv_data, 
                  filename: "workflow_metrics_#{Date.current}.csv",
                  type: 'text/csv'
      end
      format.json do
        render json: metrics
      end
    end
  end
  
  private
  
  def generate_metrics_csv(metrics)
    require 'csv'
    
    CSV.generate(headers: true) do |csv|
      csv << ['Metric', 'Value', 'Generated At']
      
      metrics.each do |key, value|
        next if value.is_a?(Array) || value.is_a?(Hash)
        csv << [key.to_s.humanize, value, Time.current]
      end
    end
  end
  
  def ensure_can_view_workflows
    unless current_business_user.can_view_business_settings?
      redirect_to admin_dashboard_path, alert: 'Access denied'
    end
  end
end
```

### 3. Create Monitoring Dashboard View
**File**: `app/views/admin/workflow_monitoring/index.html.erb`

**Implementation Notes**:
```erb
<div class="max-w-6xl mx-auto">
  <div class="flex justify-between items-center mb-6">
    <h1 class="text-2xl font-bold text-gray-900">Workflow Monitoring</h1>
    <div class="flex space-x-3">
      <%= link_to "Export Metrics", 
          export_metrics_admin_workflow_monitoring_path(format: :csv),
          class: "bg-gray-100 hover:bg-gray-200 text-gray-700 px-4 py-2 rounded-md font-medium" %>
      <button onclick="refreshDashboard()" 
              class="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-md font-medium">
        Refresh
      </button>
    </div>
  </div>

  <!-- System Health Status -->
  <div class="mb-6">
    <div class="bg-white shadow rounded-lg p-6">
      <div class="flex items-center justify-between">
        <h2 class="text-lg font-medium text-gray-900">System Health</h2>
        <div class="flex items-center space-x-4">
          <div class="flex items-center">
            <div class="w-3 h-3 rounded-full <%= health_indicator_class(@real_time_status[:system_health]) %> mr-2"></div>
            <span class="text-sm font-medium"><%= @real_time_status[:system_health].humanize %></span>
          </div>
          <span class="text-xs text-gray-500">Last updated: <%= Time.current.strftime('%H:%M:%S') %></span>
        </div>
      </div>
      
      <div class="mt-4 grid grid-cols-1 md:grid-cols-3 gap-4">
        <div class="text-center">
          <p class="text-2xl font-bold text-blue-600"><%= @real_time_status[:running_executions] %></p>
          <p class="text-sm text-gray-500">Running Now</p>
        </div>
        <div class="text-center">
          <p class="text-2xl font-bold text-yellow-600"><%= @real_time_status[:queued_jobs] %></p>
          <p class="text-sm text-gray-500">Queued</p>
        </div>
        <div class="text-center">
          <p class="text-2xl font-bold text-red-600"><%= @real_time_status[:recent_failures].count %></p>
          <p class="text-sm text-gray-500">Recent Failures</p>
        </div>
      </div>
    </div>
  </div>

  <!-- Key Metrics Grid -->
  <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
    <div class="bg-white overflow-hidden shadow rounded-lg">
      <div class="p-5">
        <div class="flex items-center">
          <div class="flex-shrink-0">
            <i data-feather="activity" class="h-8 w-8 text-blue-600"></i>
          </div>
          <div class="ml-5 w-0 flex-1">
            <dl>
              <dt class="text-sm font-medium text-gray-500 truncate">Active Workflows</dt>
              <dd class="text-3xl font-bold text-gray-900"><%= @metrics[:active_workflows] %></dd>
            </dl>
          </div>
        </div>
      </div>
      <div class="bg-gray-50 px-5 py-3">
        <div class="text-sm">
          <span class="text-gray-600">of <%= @metrics[:total_workflows] %> total</span>
        </div>
      </div>
    </div>

    <div class="bg-white overflow-hidden shadow rounded-lg">
      <div class="p-5">
        <div class="flex items-center">
          <div class="flex-shrink-0">
            <i data-feather="trending-up" class="h-8 w-8 text-green-600"></i>
          </div>
          <div class="ml-5 w-0 flex-1">
            <dl>
              <dt class="text-sm font-medium text-gray-500 truncate">Success Rate</dt>
              <dd class="text-3xl font-bold text-gray-900"><%= @metrics[:success_rate] %>%</dd>
            </dl>
          </div>
        </div>
      </div>
      <div class="bg-gray-50 px-5 py-3">
        <div class="text-sm">
          <span class="text-gray-600">Last 30 days</span>
        </div>
      </div>
    </div>

    <div class="bg-white overflow-hidden shadow rounded-lg">
      <div class="p-5">
        <div class="flex items-center">
          <div class="flex-shrink-0">
            <i data-feather="clock" class="h-8 w-8 text-purple-600"></i>
          </div>
          <div class="ml-5 w-0 flex-1">
            <dl>
              <dt class="text-sm font-medium text-gray-500 truncate">Avg. Execution</dt>
              <dd class="text-3xl font-bold text-gray-900"><%= @metrics[:avg_execution_time] %>s</dd>
            </dl>
          </div>
        </div>
      </div>
      <div class="bg-gray-50 px-5 py-3">
        <div class="text-sm">
          <span class="text-gray-600">Per workflow</span>
        </div>
      </div>
    </div>

    <div class="bg-white overflow-hidden shadow rounded-lg">
      <div class="p-5">
        <div class="flex items-center">
          <div class="flex-shrink-0">
            <i data-feather="zap" class="h-8 w-8 text-orange-600"></i>
          </div>
          <div class="ml-5 w-0 flex-1">
            <dl>
              <dt class="text-sm font-medium text-gray-500 truncate">Today</dt>
              <dd class="text-3xl font-bold text-gray-900"><%= @metrics[:executions_today] %></dd>
            </dl>
          </div>
        </div>
      </div>
      <div class="bg-gray-50 px-5 py-3">
        <div class="text-sm">
          <span class="text-gray-600"><%= @metrics[:executions_this_week] %> this week</span>
        </div>
      </div>
    </div>
  </div>

  <!-- Top Performing Workflows -->
  <div class="grid grid-cols-1 lg:grid-cols-2 gap-8 mb-8">
    <div class="bg-white shadow rounded-lg">
      <div class="px-6 py-4 border-b border-gray-200">
        <h3 class="text-lg font-medium text-gray-900">Top Performing Workflows</h3>
      </div>
      <div class="p-6">
        <% if @metrics[:top_performing_workflows].any? %>
          <div class="space-y-4">
            <% @metrics[:top_performing_workflows].each do |workflow_data| %>
              <div class="flex justify-between items-center p-3 bg-gray-50 rounded">
                <div>
                  <h4 class="font-medium text-gray-900"><%= workflow_data[:workflow].name %></h4>
                  <p class="text-sm text-gray-500"><%= workflow_data[:execution_count] %> executions</p>
                </div>
                <div class="text-right">
                  <span class="text-lg font-bold text-green-600"><%= workflow_data[:success_rate] %>%</span>
                  <p class="text-xs text-gray-500">success rate</p>
                </div>
              </div>
            <% end %>
          </div>
        <% else %>
          <p class="text-gray-500 text-center py-8">No workflow executions yet</p>
        <% end %>
      </div>
    </div>

    <!-- Performance Bottlenecks -->
    <div class="bg-white shadow rounded-lg">
      <div class="px-6 py-4 border-b border-gray-200">
        <h3 class="text-lg font-medium text-gray-900">Performance Bottlenecks</h3>
      </div>
      <div class="p-6">
        <% if @metrics[:bottleneck_steps].any? %>
          <div class="space-y-4">
            <% @metrics[:bottleneck_steps].each do |step| %>
              <div class="flex justify-between items-center p-3 bg-yellow-50 rounded">
                <div>
                  <h4 class="font-medium text-gray-900"><%= step[:step_name] %></h4>
                  <p class="text-sm text-gray-500"><%= step[:action_type].humanize %></p>
                </div>
                <div class="text-right">
                  <span class="text-lg font-bold text-yellow-600"><%= step[:avg_duration] %>s</span>
                  <p class="text-xs text-gray-500"><%= step[:failure_rate] %>% failure rate</p>
                </div>
              </div>
            <% end %>
          </div>
        <% else %>
          <p class="text-gray-500 text-center py-8">No bottlenecks identified</p>
        <% end %>
      </div>
    </div>
  </div>

  <!-- Recent Failures -->
  <% if @real_time_status[:recent_failures].any? %>
    <div class="bg-white shadow rounded-lg">
      <div class="px-6 py-4 border-b border-gray-200">
        <h3 class="text-lg font-medium text-gray-900">Recent Failures</h3>
      </div>
      <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Workflow
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Failed At
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Error
              </th>
              <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                Actions
              </th>
            </tr>
          </thead>
          <tbody class="bg-white divide-y divide-gray-200">
            <% @real_time_status[:recent_failures].each do |failure| %>
              <tr>
                <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                  <%= failure[:workflow_name] %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  <%= time_ago_in_words(failure[:failed_at]) %> ago
                </td>
                <td class="px-6 py-4 text-sm text-gray-900">
                  <span class="truncate max-w-xs"><%= failure[:error_message] %></span>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                  <%= link_to "View Details", 
                      workflow_monitoring_execution_details_path(failure[:execution_id]),
                      class: "text-blue-600 hover:text-blue-900" %>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
  <% end %>
</div>

<script>
  feather.replace();
  
  function refreshDashboard() {
    window.location.reload();
  }
  
  // Auto-refresh every 30 seconds
  setInterval(refreshDashboard, 30000);
</script>

<% content_for :helpers do %>
  <%
    def health_indicator_class(health)
      case health
      when 'healthy' then 'bg-green-500'
      when 'warning' then 'bg-yellow-500'
      when 'critical' then 'bg-red-500'
      else 'bg-gray-500'
      end
    end
  %>
<% end %>
```

## Acceptance Criteria
- Real-time monitoring dashboard shows workflow execution status
- Performance metrics include success rates and execution times
- Failed workflows can be identified and retried
- Bottleneck analysis helps identify optimization opportunities
- Monitoring data can be exported for external analysis
- Dashboard auto-refreshes to show current status

## Estimate
- Story Points: 10
- Timeline: 1 week
- Dependencies: Workflow execution system, background job monitoring
