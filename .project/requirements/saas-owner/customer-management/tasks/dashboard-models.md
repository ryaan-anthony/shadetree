# Implementation Notes: Business Customer Data Models with Health Indicators

## Overview
This task involves creating the core data models to support the Customer Dashboard feature, with a focus on storing customer information, health indicators, and related metrics.

## Models to Create/Modify

### BusinessCustomer Model

```ruby
# app/models/business_customer.rb
class BusinessCustomer < ApplicationRecord
  # Associations
  has_many :users, dependent: :destroy
  has_many :subscriptions, dependent: :destroy
  has_many :activity_logs, dependent: :destroy
  has_many :customer_metrics, dependent: :destroy
  has_many :support_tickets, dependent: :destroy
  
  # Validations
  validates :name, presence: true
  validates :domain, uniqueness: { allow_blank: true }
  validates :status, presence: true
  
  # Enums
  enum status: {
    active: 0,
    trial: 1,
    suspended: 2,
    cancelled: 3,
    past_due: 4
  }
  
  # Scopes
  scope :active_accounts, -> { where(status: [:active, :trial]) }
  scope :at_risk, -> { where("health_score < ?", 50) }
  scope :recently_created, -> { where("created_at > ?", 30.days.ago) }
  
  # Health calculation
  def health_status
    return :inactive if last_activity_at && last_activity_at < 30.days.ago
    return :at_risk if past_due? || decreasing_usage_trend? || health_score < 50
    :good
  end
  
  def mrr
    subscriptions.active.sum(:monthly_amount)
  end
  
  def arr
    mrr * 12
  end
  
  def update_health_score
    # Scoring algorithm based on multiple factors:
    # - Subscription status (40%)
    # - Usage frequency (30%)
    # - Support ticket count (15%)
    # - Payment history (15%)
    
    subscription_score = subscription_health_factor
    usage_score = usage_health_factor
    support_score = support_health_factor
    payment_score = payment_health_factor
    
    self.health_score = (
      (subscription_score * 0.4) +
      (usage_score * 0.3) +
      (support_score * 0.15) +
      (payment_score * 0.15)
    ).round
    
    save
  end
  
  private
  
  def subscription_health_factor
    return 0 if cancelled?
    return 30 if past_due?
    return 70 if trial?
    100 # active
  end
  
  def usage_health_factor
    return 0 if last_activity_at.nil? || last_activity_at < 60.days.ago
    return 30 if last_activity_at < 30.days.ago
    return 70 if decreasing_usage_trend?
    100
  end
  
  def support_health_factor
    open_tickets = support_tickets.open.count
    return 100 if open_tickets == 0
    return 70 if open_tickets < 3
    return 40 if open_tickets < 5
    0
  end
  
  def payment_health_factor
    return 0 if subscriptions.failed_payment.exists?
    return 50 if subscriptions.past_due.exists?
    100
  end
  
  def decreasing_usage_trend?
    recent_metrics = customer_metrics.usage.
                      where('created_at > ?', 90.days.ago).
                      order(created_at: :asc)
    
    return false if recent_metrics.count < 3
    
    # Simple trend analysis - three consecutive decreasing months
    values = recent_metrics.last(3).pluck(:value)
    values[0] > values[1] && values[1] > values[2]
  end
end
```

### CustomerMetric Model

```ruby
# app/models/customer_metric.rb
class CustomerMetric < ApplicationRecord
  # Associations
  belongs_to :business_customer
  
  # Validations
  validates :metric_type, presence: true
  validates :value, presence: true
  validates :recorded_at, presence: true
  
  # Enums
  enum metric_type: {
    usage: 0,
    active_users: 1,
    feature_usage: 2,
    quotes_sent: 3,
    jobs_completed: 4,
    support_tickets: 5,
    revenue: 6
  }
  
  # Scopes
  scope :recent, -> { where('recorded_at > ?', 30.days.ago) }
  scope :by_type, ->(type) { where(metric_type: type) }
  scope :trending, -> { 
    select("date_trunc('day', recorded_at) as date, metric_type, avg(value) as avg_value")
    .group("date_trunc('day', recorded_at), metric_type")
    .order("date")
  }
  
  # Calculate trend percentage change
  def self.trend_for_customer(customer_id, metric_type, days=30)
    metrics = where(business_customer_id: customer_id, metric_type: metric_type)
             .where('recorded_at > ?', days.days.ago)
             .order(recorded_at: :asc)
    
    return 0 if metrics.count < 2
    
    first = metrics.first.value
    last = metrics.last.value
    
    return 0 if first == 0
    
    ((last - first) / first.to_f) * 100
  end
end
```

## Database Migrations

### Create BusinessCustomer Table

```ruby
# db/migrate/[timestamp]_create_business_customers.rb
class CreateBusinessCustomers < ActiveRecord::Migration[8.0]
  def change
    create_table :business_customers do |t|
      t.string :name, null: false
      t.string :domain
      t.string :contact_name
      t.string :contact_email
      t.string :contact_phone
      t.integer :status, default: 1 # Default to trial
      t.string :time_zone, default: "UTC"
      t.datetime :last_activity_at
      t.float :health_score, default: 100
      t.text :notes
      
      t.timestamps
    end
    
    add_index :business_customers, :domain, unique: true
    add_index :business_customers, :status
    add_index :business_customers, :health_score
    add_index :business_customers, :last_activity_at
  end
end
```

### Create CustomerMetric Table

```ruby
# db/migrate/[timestamp]_create_customer_metrics.rb
class CreateCustomerMetrics < ActiveRecord::Migration[8.0]
  def change
    create_table :customer_metrics do |t|
      t.references :business_customer, null: false, foreign_key: true
      t.integer :metric_type, null: false
      t.float :value, null: false
      t.datetime :recorded_at, null: false
      t.jsonb :metadata, default: {}
      
      t.timestamps
    end
    
    add_index :customer_metrics, [:business_customer_id, :metric_type, :recorded_at]
  end
end
```

## Services

### CustomerHealthService

```ruby
# app/services/customer_health_service.rb
class CustomerHealthService
  def self.update_all_health_scores
    BusinessCustomer.find_each do |customer|
      customer.update_health_score
    end
  end
  
  def self.update_health_score(customer_id)
    customer = BusinessCustomer.find_by(id: customer_id)
    customer&.update_health_score
  end
  
  def self.identify_at_risk_customers
    BusinessCustomer.active_accounts.at_risk
  end
  
  def self.schedule_daily_health_updates
    # Called from a scheduler or initializer
    HealthScoreUpdateJob.set(cron: "0 1 * * *").perform_later # Daily at 1 AM
  end
end
```

### Health Score Update Job

```ruby
# app/jobs/health_score_update_job.rb
class HealthScoreUpdateJob < ApplicationJob
  queue_as :default
  
  def perform
    CustomerHealthService.update_all_health_scores
    
    # Send notifications for newly identified at-risk customers
    at_risk = BusinessCustomer.active_accounts.at_risk
    
    if at_risk.any?
      AdminMailer.at_risk_customers_report(at_risk).deliver_later
    end
  end
end
```

## Tests

### Business Customer Model Test

```ruby
# spec/models/business_customer_spec.rb
require 'rails_helper'

RSpec.describe BusinessCustomer, type: :model do
  describe "associations" do
    it { should have_many(:users) }
    it { should have_many(:subscriptions) }
    it { should have_many(:activity_logs) }
    it { should have_many(:customer_metrics) }
  end
  
  describe "validations" do
    it { should validate_presence_of(:name) }
    it { should validate_uniqueness_of(:domain).allow_blank }
  end
  
  describe "#health_status" do
    let(:customer) { create(:business_customer) }
    
    it "returns :inactive for customers without recent activity" do
      customer.update(last_activity_at: 31.days.ago)
      expect(customer.health_status).to eq(:inactive)
    end
    
    it "returns :at_risk for customers with low health score" do
      customer.update(health_score: 40, last_activity_at: 1.day.ago)
      expect(customer.health_status).to eq(:at_risk)
    end
    
    it "returns :good for healthy active customers" do
      customer.update(status: :active, health_score: 90, last_activity_at: 1.day.ago)
      allow(customer).to receive(:decreasing_usage_trend?).and_return(false)
      expect(customer.health_status).to eq(:good)
    end
  end
  
  describe "#update_health_score" do
    let(:customer) { create(:business_customer) }
    
    it "calculates health score based on multiple factors" do
      allow(customer).to receive(:subscription_health_factor).and_return(100)
      allow(customer).to receive(:usage_health_factor).and_return(80)
      allow(customer).to receive(:support_health_factor).and_return(70)
      allow(customer).to receive(:payment_health_factor).and_return(90)
      
      customer.update_health_score
      
      # (100 * 0.4) + (80 * 0.3) + (70 * 0.15) + (90 * 0.15) = 40 + 24 + 10.5 + 13.5 = 88
      expect(customer.health_score).to eq(88)
    end
  end
end
```

### CustomerMetric Model Test

```ruby
# spec/models/customer_metric_spec.rb
require 'rails_helper'

RSpec.describe CustomerMetric, type: :model do
  describe "associations" do
    it { should belong_to(:business_customer) }
  end
  
  describe "validations" do
    it { should validate_presence_of(:metric_type) }
    it { should validate_presence_of(:value) }
    it { should validate_presence_of(:recorded_at) }
  end
  
  describe ".trend_for_customer" do
    let(:customer) { create(:business_customer) }
    
    before do
      create(:customer_metric, business_customer: customer, metric_type: :active_users, value: 10, recorded_at: 30.days.ago)
      create(:customer_metric, business_customer: customer, metric_type: :active_users, value: 15, recorded_at: 15.days.ago)
      create(:customer_metric, business_customer: customer, metric_type: :active_users, value: 20, recorded_at: 1.day.ago)
    end
    
    it "calculates percentage trend correctly" do
      # From 10 to 20 = 100% increase
      trend = CustomerMetric.trend_for_customer(customer.id, :active_users)
      expect(trend).to eq(100.0)
    end
    
    it "returns 0 if there's only one data point" do
      other_customer = create(:business_customer)
      create(:customer_metric, business_customer: other_customer, metric_type: :active_users, value: 5, recorded_at: 1.day.ago)
      
      trend = CustomerMetric.trend_for_customer(other_customer.id, :active_users)
      expect(trend).to eq(0)
    end
  end
end
```

## Integration with Other Features

- The business customer model will be the core model used across many other features.
- Health indicators will be used in the Customer Dashboard UI.
- The CustomerMetric model will support usage tracking and reporting features.
- The CustomerHealthService will be integrated with notification systems for at-risk customers.

## Considerations

### Performance
- Add appropriate indexes for frequent query patterns.
- Consider partitioning the customer_metrics table if it grows very large.
- Implement caching for health score calculations, especially for dashboard views.

### Security
- Ensure proper multi-tenant isolation when accessing customer data.
- Add appropriate authorization checks in controllers that use these models.

### Maintainability
- Use consistent naming conventions for metrics across the system.
- Document the health score calculation methodology for future reference.
- Consider making the health score factors configurable if requirements change frequently.
