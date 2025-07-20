# Implementation Notes: Customer Dashboard UI with Filtering and Sorting

## Overview
This task involves creating the user interface components for the Customer Dashboard, enabling platform administrators to view, filter, and sort business customers with key metrics and health indicators.

## Controllers

### Admin::CustomersController

```ruby
# app/controllers/admin/customers_controller.rb
module Admin
  class CustomersController < AdminController
    before_action :set_customer, only: [:show, :edit, :update, :impersonate]
    
    def index
      @customers = BusinessCustomer.all
      
      # Apply filters
      @customers = apply_filters(@customers)
      
      # Apply search
      @customers = apply_search(@customers)
      
      # Apply sorting
      @customers = apply_sorting(@customers)
      
      # Pagination
      @customers = @customers.page(params[:page]).per(params[:per_page] || 20)
      
      respond_to do |format|
        format.html
        format.json { render json: @customers }
        format.csv { send_data @customers.to_csv, filename: "customers-#{Date.today}.csv" }
      end
    end
    
    def show
      @recent_activities = @customer.activity_logs.recent.limit(10)
      @subscription = @customer.subscriptions.active.first
      @metrics = @customer.customer_metrics.recent.group_by(&:metric_type)
      @trend_data = prepare_trend_data(@customer)
    end
    
    private
    
    def set_customer
      @customer = BusinessCustomer.find(params[:id])
    end
    
    def customer_params
      params.require(:business_customer).permit(
        :name, :domain, :contact_name, :contact_email, :contact_phone,
        :status, :time_zone, :notes
      )
    end
    
    def apply_filters(customers)
      customers = customers.where(status: params[:status]) if params[:status].present?
      customers = customers.where("created_at >= ?", params[:created_after]) if params[:created_after].present?
      customers = customers.where("created_at <= ?", params[:created_before]) if params[:created_before].present?
      customers = customers.where("health_score >= ?", params[:min_health]) if params[:min_health].present?
      customers = customers.where("health_score <= ?", params[:max_health]) if params[:max_health].present?
      
      if params[:subscription_plan].present?
        plan = params[:subscription_plan]
        customers = customers.joins(:subscriptions).where(subscriptions: { plan: plan, status: :active })
      end
      
      customers
    end
    
    def apply_search(customers)
      if params[:search].present?
        query = "%#{params[:search]}%"
        customers = customers.where(
          "name ILIKE :query OR domain ILIKE :query OR contact_email ILIKE :query OR contact_name ILIKE :query", 
          query: query
        )
      end
      
      customers
    end
    
    def apply_sorting(customers)
      sort_column = params[:sort] || "created_at"
      sort_direction = params[:direction] || "desc"
      
      # Safety check to prevent SQL injection
      allowed_columns = %w[name domain status created_at health_score last_activity_at]
      sort_column = "created_at" unless allowed_columns.include?(sort_column)
      sort_direction = "desc" unless %w[asc desc].include?(sort_direction)
      
      customers.order("#{sort_column} #{sort_direction}")
    end
    
    def prepare_trend_data(customer)
      {
        usage: CustomerMetric.where(business_customer: customer, metric_type: :usage)
                .where("recorded_at > ?", 90.days.ago)
                .group_by_day(:recorded_at)
                .average(:value),
        active_users: CustomerMetric.where(business_customer: customer, metric_type: :active_users)
                      .where("recorded_at > ?", 90.days.ago)
                      .group_by_day(:recorded_at)
                      .average(:value),
        revenue: CustomerMetric.where(business_customer: customer, metric_type: :revenue)
                 .where("recorded_at > ?", 90.days.ago)
                 .group_by_day(:recorded_at)
                 .sum(:value)
      }
    end
  end
end
```

## Views

### Dashboard Index

```erb
<!-- app/views/admin/customers/index.html.erb -->
<div class="customer-dashboard">
  <header class="dashboard-header">
    <h1>Customer Dashboard</h1>
    
    <div class="dashboard-metrics">
      <div class="metric-card">
        <span class="metric-value"><%= @customers.active.count %></span>
        <span class="metric-label">Active Customers</span>
      </div>
      
      <div class="metric-card">
        <span class="metric-value"><%= @customers.trial.count %></span>
        <span class="metric-label">Trial Customers</span>
      </div>
      
      <div class="metric-card">
        <span class="metric-value"><%= @customers.at_risk.count %></span>
        <span class="metric-label">At Risk</span>
      </div>
      
      <div class="metric-card">
        <span class="metric-value"><%= number_to_currency(@customers.sum(&:mrr)) %></span>
        <span class="metric-label">Total MRR</span>
      </div>
    </div>
    
    <div class="dashboard-controls">
      <%= form_with url: admin_customers_path, method: :get, class: "dashboard-filters", data: { controller: "filters" } do |f| %>
        <!-- Search bar -->
        <div class="search-container">
          <%= f.search_field :search, placeholder: "Search customers...", value: params[:search], 
                           data: { action: "input->filters#debounceSubmit" } %>
        </div>
        
        <!-- Filter dropdowns -->
        <div class="filter-controls">
          <div class="filter-group">
            <%= f.label :status, "Status" %>
            <%= f.select :status, BusinessCustomer.statuses.keys.map { |s| [s.humanize, s] }, 
                       { include_blank: "All Statuses" }, 
                       { data: { action: "change->filters#submit" } } %>
          </div>
          
          <div class="filter-group">
            <%= f.label :subscription_plan, "Plan" %>
            <%= f.select :subscription_plan, Subscription.plans.keys.map { |p| [p.humanize, p] }, 
                       { include_blank: "All Plans" }, 
                       { data: { action: "change->filters#submit" } } %>
          </div>
          
          <div class="filter-group">
            <%= f.label :health_filter, "Health" %>
            <%= f.select :health_filter,
                       [
                         ["All", ""],
                         ["Good (80-100)", "good"],
                         ["Average (50-79)", "average"],
                         ["At Risk (<50)", "at_risk"]
                       ],
                       { selected: params[:health_filter] },
                       { data: { action: "change->filters#submit" } } %>
          </div>
          
          <div class="date-range">
            <%= f.label :date_range, "Created" %>
            <div class="date-inputs">
              <%= f.date_field :created_after, value: params[:created_after] %>
              <span class="date-separator">to</span>
              <%= f.date_field :created_before, value: params[:created_before] %>
            </div>
          </div>
          
          <%= f.submit "Apply Filters", class: "filter-submit" %>
          <%= link_to "Clear All", admin_customers_path, class: "clear-filters" %>
        </div>
        
        <!-- Export options -->
        <div class="export-options">
          <%= link_to "Export CSV", admin_customers_path(request.parameters.merge(format: :csv)), class: "export-button" %>
        </div>
      <% end %>
    </div>
  </header>
  
  <!-- Bulk actions bar -->
  <div class="bulk-actions" data-controller="bulk-actions">
    <%= form_with url: bulk_action_admin_customers_path, method: :post, data: { "bulk-actions-target": "form" } do |f| %>
      <span data-bulk-actions-target="counter">0</span> customers selected
      
      <%= f.select :action, [
        ["Select Action...", ""],
        ["Tag Selected", "tag"],
        ["Update Status", "update_status"],
        ["Send Message", "message"]
      ], {}, { data: { "bulk-actions-target": "select", action: "change->bulk-actions#toggleActionForm" } } %>
      
      <div class="hidden" data-bulk-actions-target="actionForms">
        <!-- Action specific forms will be shown/hidden here -->
        <div data-bulk-action="tag" class="bulk-action-form">
          <%= f.label :tag_name, "Tag" %>
          <%= f.text_field :tag_name, placeholder: "Enter tag name" %>
        </div>
        
        <div data-bulk-action="update_status" class="bulk-action-form">
          <%= f.label :new_status, "Status" %>
          <%= f.select :new_status, BusinessCustomer.statuses.keys.map { |s| [s.humanize, s] } %>
        </div>
        
        <div data-bulk-action="message" class="bulk-action-form">
          <%= f.label :message_subject, "Subject" %>
          <%= f.text_field :message_subject, placeholder: "Message subject" %>
          
          <%= f.label :message_body, "Message" %>
          <%= f.text_area :message_body, rows: 3, placeholder: "Message content" %>
        </div>
      </div>
      
      <%= f.submit "Apply", class: "bulk-submit", data: { "bulk-actions-target": "submit" } %>
    <% end %>
  </div>
  
  <!-- Customer list -->
  <div class="customer-list">
    <table class="customer-table">
      <thead>
        <tr>
          <th><input type="checkbox" data-controller="select-all" data-action="change->select-all#toggleAll"></th>
          <th><%= sort_link_to "Business Name", :name %></th>
          <th><%= sort_link_to "Status", :status %></th>
          <th><%= sort_link_to "Plan", "subscriptions.plan" %></th>
          <th><%= sort_link_to "Created", :created_at %></th>
          <th><%= sort_link_to "MRR", :mrr %></th>
          <th><%= sort_link_to "Health", :health_score %></th>
          <th><%= sort_link_to "Last Activity", :last_activity_at %></th>
          <th>Actions</th>
        </tr>
      </thead>
      <tbody>
        <%= render partial: "customer", collection: @customers %>
      </tbody>
    </table>
    
    <%= paginate @customers %>
  </div>
</div>
```

### Customer Partial

```erb
<!-- app/views/admin/customers/_customer.html.erb -->
<tr class="customer-row health-<%= customer.health_status %>" data-customer-id="<%= customer.id %>">
  <td>
    <input type="checkbox" name="customer_ids[]" value="<%= customer.id %>" 
           data-controller="bulk-select" data-action="change->bulk-select#toggle">
  </td>
  <td class="customer-name">
    <div class="customer-avatar">
      <%= image_tag customer.logo.present? ? customer.logo_url : "default-customer.svg", alt: customer.name %>
    </div>
    <div class="customer-info">
      <strong><%= link_to customer.name, admin_customer_path(customer) %></strong>
      <small><%= customer.domain.presence || "No domain" %></small>
    </div>
  </td>
  <td>
    <span class="status-badge status-<%= customer.status %>">
      <%= customer.status.humanize %>
    </span>
  </td>
  <td>
    <% if customer.subscriptions.active.first %>
      <%= customer.subscriptions.active.first.plan.humanize %>
    <% else %>
      <span class="no-subscription">No subscription</span>
    <% end %>
  </td>
  <td><%= l customer.created_at.to_date %></td>
  <td><%= number_to_currency(customer.mrr) %></td>
  <td>
    <div class="health-indicator">
      <div class="health-score" style="--score: <%= customer.health_score %>%">
        <span><%= customer.health_score %></span>
      </div>
      <div class="health-label <%= customer.health_status %>"><%= customer.health_status.to_s.humanize %></div>
    </div>
  </td>
  <td>
    <% if customer.last_activity_at.present? %>
      <span title="<%= l customer.last_activity_at %>">
        <%= time_ago_in_words(customer.last_activity_at) %> ago
      </span>
    <% else %>
      <span class="no-data">No activity</span>
    <% end %>
  </td>
  <td class="actions">
    <div class="dropdown">
      <button class="dropdown-toggle" data-controller="dropdown">
        Actions
      </button>
      <div class="dropdown-menu">
        <%= link_to "View Details", admin_customer_path(customer) %>
        <%= link_to "Edit", edit_admin_customer_path(customer) %>
        <%= link_to "Impersonate", impersonate_admin_customer_path(customer), method: :post, data: { confirm: "Are you sure you want to impersonate this customer?" } %>
        <% if customer.active? || customer.trial? %>
          <%= link_to "Suspend", suspend_admin_customer_path(customer), method: :post, data: { confirm: "Are you sure you want to suspend this customer?" } %>
        <% else %>
          <%= link_to "Activate", activate_admin_customer_path(customer), method: :post %>
        <% end %>
      </div>
    </div>
  </td>
</tr>
```

### Dashboard Detail View

```erb
<!-- app/views/admin/customers/show.html.erb -->
<div class="customer-detail">
  <header class="detail-header">
    <div class="back-link">
      <%= link_to admin_customers_path do %>
        &larr; Back to Dashboard
      <% end %>
    </div>
    
    <div class="customer-overview">
      <div class="customer-avatar large">
        <%= image_tag @customer.logo.present? ? @customer.logo_url : "default-customer.svg", alt: @customer.name %>
      </div>
      
      <div class="customer-summary">
        <h1><%= @customer.name %></h1>
        <div class="customer-meta">
          <span class="status-badge status-<%= @customer.status %>">
            <%= @customer.status.humanize %>
          </span>
          
          <% if @subscription %>
            <span class="plan-badge">
              <%= @subscription.plan.humanize %>
            </span>
          <% end %>
          
          <span class="health-badge health-<%= @customer.health_status %>">
            <%= @customer.health_status.to_s.humanize %> Health
          </span>
        </div>
        
        <div class="customer-contact">
          <% if @customer.contact_email.present? %>
            <div class="contact-item">
              <i class="icon-email"></i>
              <a href="mailto:<%= @customer.contact_email %>"><%= @customer.contact_email %></a>
            </div>
          <% end %>
          
          <% if @customer.contact_phone.present? %>
            <div class="contact-item">
              <i class="icon-phone"></i>
              <a href="tel:<%= @customer.contact_phone %>"><%= @customer.contact_phone %></a>
            </div>
          <% end %>
          
          <% if @customer.domain.present? %>
            <div class="contact-item">
              <i class="icon-globe"></i>
              <a href="https://<%= @customer.domain %>" target="_blank"><%= @customer.domain %></a>
            </div>
          <% end %>
        </div>
      </div>
      
      <div class="detail-actions">
        <%= link_to "Edit Customer", edit_admin_customer_path(@customer), class: "btn btn-secondary" %>
        <%= link_to "Impersonate", impersonate_admin_customer_path(@customer), method: :post, class: "btn btn-primary", data: { confirm: "Are you sure you want to impersonate this customer?" } %>
      </div>
    </div>
  </header>
  
  <div class="detail-metrics">
    <div class="metric-card">
      <span class="metric-value"><%= number_to_currency(@customer.mrr) %></span>
      <span class="metric-label">Monthly Revenue</span>
    </div>
    
    <div class="metric-card">
      <span class="metric-value"><%= @customer.users.count %></span>
      <span class="metric-label">Total Users</span>
    </div>
    
    <div class="metric-card">
      <span class="metric-value"><%= time_ago_in_words(@customer.created_at) %></span>
      <span class="metric-label">Customer Since</span>
    </div>
    
    <div class="metric-card">
      <span class="metric-value"><%= @customer.health_score %></span>
      <span class="metric-label">Health Score</span>
    </div>
  </div>
  
  <div class="detail-tabs" data-controller="tabs">
    <div class="tab-navigation">
      <button class="tab-btn active" data-action="click->tabs#switch" data-tab-target="overview">Overview</button>
      <button class="tab-btn" data-action="click->tabs#switch" data-tab-target="activity">Activity</button>
      <button class="tab-btn" data-action="click->tabs#switch" data-tab-target="subscriptions">Subscriptions</button>
      <button class="tab-btn" data-action="click->tabs#switch" data-tab-target="users">Users</button>
      <button class="tab-btn" data-action="click->tabs#switch" data-tab-target="support">Support</button>
      <button class="tab-btn" data-action="click->tabs#switch" data-tab-target="notes">Notes</button>
    </div>
    
    <div class="tab-content">
      <div class="tab active" data-tab-id="overview">
        <div class="chart-container">
          <h3>Usage Trends (Last 90 Days)</h3>
          <%= render "admin/shared/trend_chart", data: @trend_data[:usage], 
                                               id: "usage-chart", 
                                               color: "#2563eb" %>
        </div>
        
        <div class="chart-container">
          <h3>Active Users (Last 90 Days)</h3>
          <%= render "admin/shared/trend_chart", data: @trend_data[:active_users], 
                                               id: "users-chart", 
                                               color: "#10b981" %>
        </div>
        
        <div class="chart-container">
          <h3>Revenue (Last 90 Days)</h3>
          <%= render "admin/shared/trend_chart", data: @trend_data[:revenue], 
                                               id: "revenue-chart", 
                                               color: "#8b5cf6",
                                               format: "currency" %>
        </div>
      </div>
      
      <div class="tab" data-tab-id="activity">
        <%= render "admin/shared/activity_log", activities: @recent_activities %>
      </div>
      
      <!-- Other tab contents -->
    </div>
  </div>
</div>
```

## JavaScript

### Filtering Controller

```javascript
// app/javascript/controllers/filters_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "form" ]
  
  connect() {
    this.timeout = null
  }
  
  submit() {
    this.element.requestSubmit()
  }
  
  debounceSubmit(event) {
    if (this.timeout) {
      clearTimeout(this.timeout)
    }
    
    this.timeout = setTimeout(() => {
      this.submit()
    }, 500)
  }
}
```

### Bulk Actions Controller

```javascript
// app/javascript/controllers/bulk_actions_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "counter", "form", "select", "submit", "actionForms" ]
  
  connect() {
    this.updateCounter()
    document.addEventListener('bulk-selection-change', this.updateCounter.bind(this))
  }
  
  disconnect() {
    document.removeEventListener('bulk-selection-change', this.updateCounter.bind(this))
  }
  
  updateCounter() {
    const count = document.querySelectorAll('input[name="customer_ids[]"]:checked').length
    this.counterTarget.textContent = count
    
    if (count > 0) {
      this.formTarget.classList.add('has-selection')
      this.submitTarget.disabled = false
    } else {
      this.formTarget.classList.remove('has-selection')
      this.submitTarget.disabled = true
      this.selectTarget.value = ""
      this.hideAllActionForms()
    }
  }
  
  toggleActionForm() {
    const action = this.selectTarget.value
    this.hideAllActionForms()
    
    if (action) {
      const form = this.actionFormsTarget.querySelector(`[data-bulk-action="${action}"]`)
      if (form) {
        form.classList.remove('hidden')
      }
    }
  }
  
  hideAllActionForms() {
    const forms = this.actionFormsTarget.querySelectorAll('.bulk-action-form')
    forms.forEach(form => form.classList.add('hidden'))
  }
}
```

## Stylesheet

```css
/* app/assets/stylesheets/admin/customer_dashboard.css */
.customer-dashboard {
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
}

.dashboard-header {
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
}

.dashboard-metrics {
  display: flex;
  flex-wrap: wrap;
  gap: 1rem;
}

.metric-card {
  background-color: white;
  border-radius: 0.5rem;
  padding: 1rem;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
  display: flex;
  flex-direction: column;
  min-width: 150px;
  flex: 1;
}

.metric-value {
  font-size: 1.5rem;
  font-weight: 600;
}

.metric-label {
  color: #6b7280;
  font-size: 0.875rem;
}

.dashboard-controls {
  background-color: white;
  border-radius: 0.5rem;
  padding: 1rem;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
}

.dashboard-filters {
  display: flex;
  flex-direction: column;
  gap: 1rem;
}

.search-container {
  width: 100%;
}

.search-container input {
  width: 100%;
  padding: 0.5rem 1rem;
  border: 1px solid #e5e7eb;
  border-radius: 0.375rem;
}

.filter-controls {
  display: flex;
  flex-wrap: wrap;
  gap: 1rem;
  align-items: flex-end;
}

.filter-group {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
}

.filter-group label {
  font-size: 0.75rem;
  font-weight: 500;
  color: #6b7280;
}

.filter-group select {
  padding: 0.5rem;
  border: 1px solid #e5e7eb;
  border-radius: 0.375rem;
  background-color: white;
}

.date-range {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
}

.date-inputs {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.date-separator {
  color: #6b7280;
}

.filter-submit {
  padding: 0.5rem 1rem;
  background-color: #2563eb;
  color: white;
  border: none;
  border-radius: 0.375rem;
  font-weight: 500;
  cursor: pointer;
}

.clear-filters {
  padding: 0.5rem 1rem;
  background-color: transparent;
  color: #6b7280;
  border: 1px solid #e5e7eb;
  border-radius: 0.375rem;
  font-weight: 500;
  text-decoration: none;
}

.export-options {
  margin-left: auto;
}

.export-button {
  padding: 0.5rem 1rem;
  background-color: #10b981;
  color: white;
  border: none;
  border-radius: 0.375rem;
  font-weight: 500;
  text-decoration: none;
  display: inline-block;
}

/* Customer table styles */
.customer-table {
  width: 100%;
  border-collapse: collapse;
  background-color: white;
  border-radius: 0.5rem;
  overflow: hidden;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
}

.customer-table th {
  text-align: left;
  padding: 0.75rem 1rem;
  background-color: #f9fafb;
  border-bottom: 1px solid #e5e7eb;
  font-weight: 600;
  color: #374151;
}

.customer-row {
  border-bottom: 1px solid #e5e7eb;
}

.customer-row:last-child {
  border-bottom: none;
}

.customer-row td {
  padding: 1rem;
  vertical-align: middle;
}

.customer-name {
  display: flex;
  align-items: center;
  gap: 0.75rem;
}

.customer-avatar {
  width: 2.5rem;
  height: 2.5rem;
  border-radius: 50%;
  overflow: hidden;
  background-color: #e5e7eb;
  display: flex;
  align-items: center;
  justify-content: center;
}

.customer-avatar img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.customer-info {
  display: flex;
  flex-direction: column;
}

.customer-info strong {
  color: #111827;
}

.customer-info small {
  color: #6b7280;
  font-size: 0.75rem;
}

.status-badge {
  display: inline-block;
  padding: 0.25rem 0.5rem;
  border-radius: 9999px;
  font-size: 0.75rem;
  font-weight: 500;
  text-align: center;
}

.status-badge.status-active {
  background-color: #d1fae5;
  color: #065f46;
}

.status-badge.status-trial {
  background-color: #e0f2fe;
  color: #0369a1;
}

.status-badge.status-suspended {
  background-color: #fee2e2;
  color: #b91c1c;
}

.status-badge.status-cancelled {
  background-color: #f3f4f6;
  color: #4b5563;
}

.status-badge.status-past_due {
  background-color: #fef3c7;
  color: #92400e;
}

.health-indicator {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
}

.health-score {
  width: 100%;
  height: 0.5rem;
  background-color: #e5e7eb;
  border-radius: 9999px;
  overflow: hidden;
  position: relative;
}

.health-score::before {
  content: '';
  position: absolute;
  top: 0;
  left: 0;
  width: var(--score);
  height: 100%;
  background-color: currentColor;
}

.health-score span {
  position: absolute;
  width: 1px;
  height: 1px;
  padding: 0;
  margin: -1px;
  overflow: hidden;
  clip: rect(0, 0, 0, 0);
  white-space: nowrap;
  border-width: 0;
}

.health-label {
  font-size: 0.75rem;
  font-weight: 500;
}

.health-label.good {
  color: #10b981;
}

.health-label.at_risk {
  color: #f59e0b;
}

.health-label.inactive {
  color: #ef4444;
}

/* Pagination styles */
.pagination {
  display: flex;
  justify-content: center;
  margin-top: 1.5rem;
  gap: 0.25rem;
}

.pagination a, .pagination span {
  padding: 0.5rem 0.75rem;
  border: 1px solid #e5e7eb;
  border-radius: 0.375rem;
  color: #374151;
  text-decoration: none;
}

.pagination a:hover {
  background-color: #f9fafb;
}

.pagination .current {
  background-color: #2563eb;
  color: white;
  border-color: #2563eb;
}

/* Bulk actions styles */
.bulk-actions {
  display: flex;
  align-items: center;
  gap: 1rem;
  padding: 1rem;
  background-color: white;
  border: 1px solid #e5e7eb;
  border-radius: 0.5rem;
  margin-bottom: 1rem;
  transition: opacity 0.2s;
}

.bulk-actions:not(.has-selection) {
  opacity: 0.7;
}

.bulk-action-form {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
  margin: 0.5rem 0;
}

/* Detail view styles */
.customer-detail {
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
}

.detail-header {
  background-color: white;
  border-radius: 0.5rem;
  padding: 1.5rem;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
}

.back-link {
  margin-bottom: 1rem;
}

.back-link a {
  color: #6b7280;
  text-decoration: none;
  font-weight: 500;
}

.customer-overview {
  display: flex;
  gap: 1.5rem;
  align-items: center;
}

.customer-avatar.large {
  width: 5rem;
  height: 5rem;
}

.customer-summary h1 {
  margin: 0 0 0.5rem 0;
  font-size: 1.5rem;
}

.customer-meta {
  display: flex;
  gap: 0.5rem;
  margin-bottom: 1rem;
}

.customer-contact {
  display: flex;
  flex-wrap: wrap;
  gap: 1rem;
}

.contact-item {
  display: flex;
  align-items: center;
  gap: 0.25rem;
  color: #6b7280;
}

.contact-item a {
  color: #2563eb;
  text-decoration: none;
}

.detail-actions {
  margin-left: auto;
}

/* Tab styles */
.detail-tabs {
  background-color: white;
  border-radius: 0.5rem;
  overflow: hidden;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
}

.tab-navigation {
  display: flex;
  border-bottom: 1px solid #e5e7eb;
}

.tab-btn {
  padding: 1rem 1.5rem;
  background-color: transparent;
  border: none;
  border-bottom: 2px solid transparent;
  font-weight: 500;
  color: #6b7280;
  cursor: pointer;
}

.tab-btn.active {
  color: #2563eb;
  border-bottom-color: #2563eb;
}

.tab-content {
  padding: 1.5rem;
}

.tab {
  display: none;
}

.tab.active {
  display: block;
}

.chart-container {
  margin-bottom: 2rem;
}

.chart-container h3 {
  margin-top: 0;
  margin-bottom: 1rem;
  font-size: 1.25rem;
  color: #374151;
}
```

## Helper Methods

```ruby
# app/helpers/admin/customers_helper.rb
module Admin
  module CustomersHelper
    def sort_link_to(name, column)
      direction = (params[:sort] == column && params[:direction] == "asc") ? "desc" : "asc"
      
      link_to admin_customers_path(
        request.params.merge(sort: column, direction: direction)
      ), class: "sort-link" do
        raw("#{name} #{sort_indicator(column)}")
      end
    end
    
    def sort_indicator(column)
      return "" unless params[:sort] == column
      
      direction = params[:direction] == "asc" ? "up" : "down"
      tag.span(class: "sort-#{direction}") do
        direction == "up" ? "↑" : "↓"
      end
    end
  end
end
```

## Tests

### Controller Test

```ruby
# spec/controllers/admin/customers_controller_spec.rb
require 'rails_helper'

RSpec.describe Admin::CustomersController, type: :controller do
  let(:admin) { create(:admin_user) }
  
  before do
    sign_in admin
  end
  
  describe "GET #index" do
    before do
      create_list(:business_customer, 3, status: :active)
      create(:business_customer, status: :trial)
      create(:business_customer, status: :suspended)
    end
    
    it "returns http success" do
      get :index
      expect(response).to have_http_status(:success)
    end
    
    it "assigns all customers by default" do
      get :index
      expect(assigns(:customers).count).to eq(5)
    end
    
    it "filters customers by status" do
      get :index, params: { status: :active }
      expect(assigns(:customers).count).to eq(3)
      expect(assigns(:customers).all?(&:active?)).to be_truthy
    end
    
    it "applies search filter" do
      customer = create(:business_customer, name: "Unique Customer Name")
      get :index, params: { search: "unique" }
      expect(assigns(:customers).count).to eq(1)
      expect(assigns(:customers).first).to eq(customer)
    end
    
    it "applies sorting" do
      get :index, params: { sort: "name", direction: "asc" }
      expect(assigns(:customers).to_a).to eq(BusinessCustomer.order(name: :asc).to_a)
    end
    
    it "responds to CSV format" do
      get :index, format: :csv
      expect(response.content_type).to eq("text/csv")
      expect(response.headers["Content-Disposition"]).to include("customers-#{Date.today}.csv")
    end
  end
  
  describe "GET #show" do
    let(:customer) { create(:business_customer) }
    
    before do
      create_list(:activity_log, 5, business_customer: customer)
    end
    
    it "returns http success" do
      get :show, params: { id: customer.id }
      expect(response).to have_http_status(:success)
    end
    
    it "assigns customer and related data" do
      get :show, params: { id: customer.id }
      expect(assigns(:customer)).to eq(customer)
      expect(assigns(:recent_activities).count).to eq(5)
    end
  end
end
```

### System Test

```ruby
# spec/system/admin/customer_dashboard_spec.rb
require 'rails_helper'

RSpec.describe "Admin Customer Dashboard", type: :system do
  let(:admin) { create(:admin_user) }
  
  before do
    sign_in admin
    create_list(:business_customer, 25) # Create 25 test customers
    
    # Create customers with different statuses
    create(:business_customer, name: "Active Corp", status: :active)
    create(:business_customer, name: "Trial Inc", status: :trial)
    create(:business_customer, name: "Suspended Ltd", status: :suspended)
    
    visit admin_customers_path
  end
  
  scenario "admin views customer dashboard" do
    expect(page).to have_content("Customer Dashboard")
    expect(page).to have_css(".customer-row", count: 20) # Default pagination
    expect(page).to have_content("Active Corp")
  end
  
  scenario "admin filters customers by status" do
    select "Trial", from: "status"
    click_button "Apply Filters"
    
    expect(page).to have_content("Trial Inc")
    expect(page).not_to have_content("Active Corp")
    expect(page).not_to have_content("Suspended Ltd")
  end
  
  scenario "admin searches for a customer" do
    fill_in "search", with: "Active Corp"
    
    # Wait for debounce
    sleep 0.6
    
    expect(page).to have_content("Active Corp")
    expect(page).not_to have_content("Trial Inc")
    expect(page).not_to have_content("Suspended Ltd")
  end
  
  scenario "admin can sort customers" do
    click_link "Business Name"
    
    # First click sorts ascending
    customers = all(".customer-info strong").map(&:text)
    expect(customers).to eq(customers.sort)
    
    # Second click sorts descending
    click_link "Business Name"
    customers = all(".customer-info strong").map(&:text)
    expect(customers).to eq(customers.sort.reverse)
  end
  
  scenario "admin can view customer details" do
    first(".customer-info strong a").click
    
    expect(page).to have_content("Customer Since")
    expect(page).to have_content("Health Score")
    expect(page).to have_button("Overview")
    expect(page).to have_button("Activity")
  end
end
```

## Integration with Other Features

- The dashboard UI integrates with the Customer Models created in task CM-1.1.1
- The UI provides links to customer impersonation (task CM-1.3.1)
- Activity history display integrates with the Activity Tracking system (task CM-1.4.1)
- Search functionality will be extended by advanced search features (task CM-1.5.1)

## Considerations

### Performance
- Implement pagination for customer list to avoid loading too many records at once
- Add database indexes for columns used in sorting and filtering
- Use eager loading to avoid N+1 queries when displaying customer associations
- Consider implementing infinite scrolling for very large customer lists

### Accessibility
- Ensure all UI components have proper ARIA attributes and keyboard navigation
- Maintain sufficient color contrast for status indicators and health scores
- Provide alternative text for icons and visualization elements
- Support keyboard navigation through filters and bulk actions

### Maintainability
- Use consistent CSS class naming convention
- Extract reusable components into partials
- Implement view caching for portions of the dashboard that don't change frequently
- Document complex UI behaviors and interactions
