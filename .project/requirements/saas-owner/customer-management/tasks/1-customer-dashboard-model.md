# Task: Create Customer Dashboard Models and Database Structure

## Overview
Implement the data models and database structure needed to support the customer dashboard functionality.

## Implementation Notes

### Create Customer Model Extension
Add necessary fields to the customer model to support dashboard metrics and health indicators.

```ruby
# app/models/business_customer.rb
class BusinessCustomer < ApplicationRecord
  has_many :subscriptions
  has_many :activity_logs
  has_many :support_tickets
  has_many :users
  
  enum status: { 
    active: 0, 
    trial: 1, 
    suspended: 2, 
    cancelled: 3, 
    past_due: 4 
  }
  
  # Customer health calculation
  def health_status
    return :inactive if last_activity_at < 30.days.ago
    return :at_risk if past_due? || decreasing_usage_trend?
    :good
  end
  
  def mrr
    subscriptions.active.sum(:monthly_amount)
  end
  
  def arr
    mrr * 12
  end
  
  private
  
  def decreasing_usage_trend?
    # Logic to determine if usage has been declining over past 3 months
    # This is a simplified placeholder for actual trend analysis
    previous_usage = usage_metrics.where('created_at > ?', 90.days.ago).order(created_at: :asc)
    return false if previous_usage.count < 3
    
    # Simple linear regression could be implemented here
    # For now, just check if last month is less than average of previous two
    last_month = previous_usage.last.value
    avg_previous = previous_usage.limit(previous_usage.count - 1).average(:value)
    last_month < avg_previous * 0.8
  end
end

# Generate migration:
# rails g migration AddHealthMetricsToBusinessCustomers last_activity_at:datetime health_score:float churn_risk:float status:integer
```

### Create CustomerMetric Model
```ruby
# app/models/customer_metric.rb
class CustomerMetric < ApplicationRecord
  belongs_to :business_customer
  
  # Common metrics for all customers
  validates :metric_type, presence: true
  validates :value, presence: true
  
  enum metric_type: {
    quotes_sent: 0,
    jobs_completed: 1,
    active_users: 2, 
    feature_usage: 3,
    support_tickets: 4
  }
  
  scope :recent, -> { where('created_at > ?', 30.days.ago) }
  scope :by_type, ->(type) { where(metric_type: type) }
  
  # Generate trends for dashboard
  def self.trend_for_customer(customer_id, metric_type, days=90)
    where(business_customer_id: customer_id, metric_type: metric_type)
      .where('created_at > ?', days.days.ago)
      .group("DATE_TRUNC('day', created_at)")
      .average(:value)
  end
end

# Generate migration:
# rails g model CustomerMetric business_customer:references metric_type:integer value:float recorded_at:datetime metadata:jsonb
```

### Database Indexes for Performance
```ruby
# Migration to add indexes for dashboard performance
class AddDashboardIndexes < ActiveRecord::Migration[8.0]
  def change
    # Indexes for filtering and sorting
    add_index :business_customers, :status
    add_index :business_customers, :created_at
    add_index :business_customers, :last_activity_at
    
    # Compound index for metrics queries
    add_index :customer_metrics, [:business_customer_id, :metric_type, :created_at]
  end
end
```

## Test Cases
```ruby
# spec/models/business_customer_spec.rb
require 'rails_helper'

RSpec.describe BusinessCustomer, type: :model do
  describe "associations" do
    it { should have_many(:subscriptions) }
    it { should have_many(:activity_logs) }
    it { should have_many(:users) }
  end
  
  describe "health_status" do
    let(:customer) { create(:business_customer) }
    
    it "returns :inactive for customers without recent activity" do
      customer.update(last_activity_at: 31.days.ago)
      expect(customer.health_status).to eq(:inactive)
    end
    
    it "returns :at_risk for customers with past_due status" do
      customer.update(status: :past_due, last_activity_at: 1.day.ago)
      expect(customer.health_status).to eq(:at_risk)
    end
    
    it "returns :good for active customers with recent activity" do
      customer.update(status: :active, last_activity_at: 1.day.ago)
      allow(customer).to receive(:decreasing_usage_trend?).and_return(false)
      expect(customer.health_status).to eq(:good)
    end
  end
end
```
