class Admin::DashboardController < Admin::BaseController
  def index
    @metrics = calculate_dashboard_metrics
    @recent_quotes = recent_quotes_data
    @service_performance = service_performance_data
  end

  private

  def calculate_dashboard_metrics
    # TODO: Replace with actual database queries
    {
      total_revenue: {
        value: 47250,
        change: 12.5,
        trend: :up
      },
      active_quotes: {
        value: 24,
        change: 8,
        trend: :up,
        period: "this week"
      },
      conversion_rate: {
        value: 68,
        change: 5,
        trend: :up,
        suffix: "%"
      },
      avg_quote_value: {
        value: 425,
        change: -2.1,
        trend: :down
      }
    }
  end

  def recent_quotes_data
    # TODO: Replace with actual Quote model queries
    [
      { id: 1, customer: "Smith Residence", service: "Lawn Maintenance", value: 250, status: "pending" },
      { id: 2, customer: "Johnson Property", service: "Tree Trimming", value: 450, status: "approved" },
      { id: 3, customer: "Davis Home", service: "Landscaping", value: 1200, status: "in_progress" }
    ]
  end

  def service_performance_data
    # TODO: Replace with actual service analytics
    [
      { name: "Lawn Maintenance", quotes: 45, conversion: 72, revenue: 15750 },
      { name: "Tree Trimming", quotes: 23, conversion: 65, revenue: 8950 },
      { name: "Landscaping", quotes: 18, conversion: 78, revenue: 12450 },
      { name: "Hedge Trimming", quotes: 12, conversion: 58, revenue: 3200 }
    ]
  end
end
