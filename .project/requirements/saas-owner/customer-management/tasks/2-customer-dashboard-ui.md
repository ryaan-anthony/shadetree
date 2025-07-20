# Task: Implement Customer Dashboard UI Components

## Overview
Create the front-end components necessary for the customer dashboard interface, including customer cards/rows, filtering controls, and search functionality.

## Implementation Notes

### Create Dashboard Controller and Views

```ruby
# app/controllers/admin/customers_controller.rb
module Admin
  class CustomersController < AdminController
    before_action :set_customer, only: [:show, :edit, :update, :impersonate]
    
    def index
      @customers = BusinessCustomer.all
      
      # Apply filters
      @customers = @customers.where(status: params[:status]) if params[:status].present?
      @customers = @customers.where("created_at >= ?", params[:created_after]) if params[:created_after].present?
      @customers = @customers.where("created_at <= ?", params[:created_before]) if params[:created_before].present?
      
      # Apply search
      if params[:search].present?
        @customers = @customers.where("name ILIKE :query OR email ILIKE :query OR domain ILIKE :query", 
                                    query: "%#{params[:search]}%")
      end
      
      # Apply sorting
      sort_column = params[:sort] || "created_at"
      sort_direction = params[:direction] || "desc"
      @customers = @customers.order("#{sort_column} #{sort_direction}")
      
      # Pagination
      @customers = @customers.page(params[:page]).per(params[:per_page] || 20)
      
      respond_to do |format|
        format.html
        format.json { render json: @customers }
        format.csv { send_data @customers.to_csv, filename: "customers-#{Date.today}.csv" }
      end
    end
    
    def show
      @recent_activities = @customer.activity_logs.order(created_at: :desc).limit(10)
      @subscription = @customer.subscriptions.active.first
      @metrics = @customer.customer_metrics.group_by(&:metric_type)
    end
    
    # Other controller methods...
    
    private
    
    def set_customer
      @customer = BusinessCustomer.find(params[:id])
    end
  end
end
```

### Create Dashboard View Template

```erb
<!-- app/views/admin/customers/index.html.erb -->
<div class="customer-dashboard">
  <header class="dashboard-header">
    <h1>Customer Dashboard</h1>
    
    <div class="dashboard-controls">
      <%= form_with url: admin_customers_path, method: :get, class: "dashboard-filters", data: { controller: "filters" } do |f| %>
        <!-- Search bar -->
        <div class="search-container">
          <%= f.search_field :search, placeholder: "Search customers...", value: params[:search], 
                            data: { action: "input->filters#debounceSubmit" } %>
        </div>
        
        <!-- Filter dropdowns -->
        <div class="filter-controls">
          <%= f.select :status, BusinessCustomer.statuses.keys.map { |s| [s.humanize, s] }, 
                      { include_blank: "All Statuses" }, 
                      { data: { action: "change->filters#submit" } } %>
                      
          <%= f.select :plan, Subscription.plans.keys.map { |p| [p.humanize, p] }, 
                      { include_blank: "All Plans" }, 
                      { data: { action: "change->filters#submit" } } %>
                      
          <div class="date-range">
            <%= f.date_field :created_after, value: params[:created_after] %>
            <span>to</span>
            <%= f.date_field :created_before, value: params[:created_before] %>
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
        ["Update Plan", "update_plan"],
        ["Send Message", "message"]
      ], {}, { data: { "bulk-actions-target": "select", action: "change->bulk-actions#toggleActionForm" } } %>
      
      <div class="hidden" data-bulk-actions-target="actionForms">
        <!-- Action specific forms will be shown/hidden here -->
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

### Create Customer Partial

```erb
<!-- app/views/admin/customers/_customer.html.erb -->
<tr class="customer-row <%= customer.health_status %>" data-customer-id="<%= customer.id %>">
  <td>
    <input type="checkbox" name="customer_ids[]" value="<%= customer.id %>" 
           data-controller="bulk-select" data-action="change->bulk-select#toggle">
  </td>
  <td class="customer-name">
    <div class="customer-avatar">
      <%= image_tag customer.logo.present? ? customer.logo : "default-customer.png", alt: customer.name %>
    </div>
    <div class="customer-info">
      <strong><%= link_to customer.name, admin_customer_path(customer) %></strong>
      <small><%= customer.domain %></small>
    </div>
  </td>
  <td>
    <span class="status-badge <%= customer.status %>">
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
    <div class="health-indicator <%= customer.health_status %>" 
         title="<%= customer.health_status.to_s.humanize %>">
      <%= render "health_icon", status: customer.health_status %>
    </div>
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

### Add Stimulus Controller for Filtering

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

### Add CSS for Dashboard

```css
/* app/assets/stylesheets/admin/customer_dashboard.css */
.customer-dashboard {
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
}

.dashboard-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.dashboard-controls {
  display: flex;
  gap: 1rem;
  flex-wrap: wrap;
}

.customer-table {
  width: 100%;
  border-collapse: collapse;
}

.customer-table th {
  text-align: left;
  padding: 0.75rem 1rem;
  background-color: #f9fafb;
  border-bottom: 1px solid #e5e7eb;
}

.customer-row {
  border-bottom: 1px solid #e5e7eb;
}

.customer-row td {
  padding: 1rem;
  vertical-align: middle;
}

.customer-row:hover {
  background-color: #f9fafb;
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
}

.customer-avatar img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.status-badge {
  display: inline-block;
  padding: 0.25rem 0.5rem;
  border-radius: 9999px;
  font-size: 0.75rem;
  font-weight: 500;
}

.status-badge.active {
  background-color: #d1fae5;
  color: #065f46;
}

.status-badge.trial {
  background-color: #e0f2fe;
  color: #0369a1;
}

.status-badge.suspended {
  background-color: #fee2e2;
  color: #b91c1c;
}

.status-badge.cancelled {
  background-color: #f3f4f6;
  color: #4b5563;
}

.status-badge.past_due {
  background-color: #fef3c7;
  color: #92400e;
}

.health-indicator {
  width: 1rem;
  height: 1rem;
  border-radius: 50%;
}

.health-indicator.good {
  background-color: #10b981;
}

.health-indicator.at_risk {
  background-color: #f59e0b;
}

.health-indicator.inactive {
  background-color: #ef4444;
}

.dropdown {
  position: relative;
}

.dropdown-menu {
  display: none;
  position: absolute;
  right: 0;
  top: 100%;
  background-color: white;
  border: 1px solid #e5e7eb;
  border-radius: 0.375rem;
  box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.1);
  padding: 0.5rem 0;
  z-index: 10;
}

.dropdown-menu a {
  display: block;
  padding: 0.5rem 1rem;
  color: #374151;
  text-decoration: none;
}

.dropdown-menu a:hover {
  background-color: #f9fafb;
}

.dropdown.show .dropdown-menu {
  display: block;
}

/* Bulk actions styles */
.bulk-actions {
  display: flex;
  align-items: center;
  gap: 1rem;
  padding: 1rem;
  background-color: #f9fafb;
  border: 1px solid #e5e7eb;
  border-radius: 0.375rem;
}

/* Pagination styles */
.pagination {
  display: flex;
  justify-content: center;
  margin-top: 2rem;
  gap: 0.25rem;
}

.pagination a, .pagination span {
  padding: 0.5rem 0.75rem;
  border: 1px solid #e5e7eb;
  border-radius: 0.25rem;
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
```

## Test Cases

```ruby
# spec/features/admin/customer_dashboard_spec.rb
require 'rails_helper'

RSpec.describe "Admin Customer Dashboard", type: :feature do
  let(:admin) { create(:admin_user) }
  
  before do
    sign_in admin
    create_list(:business_customer, 25) # Create 25 test customers
    
    # Create customers with different statuses
    create(:business_customer, name: "Active Corp", status: :active)
    create(:business_customer, name: "Trial Inc", status: :trial)
    create(:business_customer, name: "Suspended Ltd", status: :suspended)
  end
  
  scenario "admin views customer dashboard" do
    visit admin_customers_path
    
    expect(page).to have_content("Customer Dashboard")
    expect(page).to have_css(".customer-row", count: 20) # Default pagination
    expect(page).to have_content("Active Corp")
  end
  
  scenario "admin filters customers by status" do
    visit admin_customers_path
    
    select "Trial", from: "status"
    click_button "Apply Filters"
    
    expect(page).to have_content("Trial Inc")
    expect(page).not_to have_content("Active Corp")
    expect(page).not_to have_content("Suspended Ltd")
  end
  
  scenario "admin searches for a customer" do
    visit admin_customers_path
    
    fill_in "search", with: "Active Corp"
    
    # Wait for debounce
    sleep 0.6
    
    expect(page).to have_content("Active Corp")
    expect(page).not_to have_content("Trial Inc")
    expect(page).not_to have_content("Suspended Ltd")
  end
  
  scenario "admin can export customer data" do
    visit admin_customers_path
    
    click_link "Export CSV"
    
    # Test that the CSV download starts
    expect(page.response_headers["Content-Type"]).to eq("text/csv")
  end
end
```
