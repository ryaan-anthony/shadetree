# Task: Implement Basic Search Functionality

## Overview
Implement basic search functionality for customers including global search and results display.

## Implementation Notes

### Add Search Controller Endpoints

```ruby
# app/controllers/admin/searches_controller.rb
module Admin
  class SearchesController < AdminController
    def customers
      @query = params[:q]
      
      if @query.present?
        @customers = BusinessCustomer.search(@query, page: params[:page], per_page: 20)
      else
        @customers = BusinessCustomer.page(params[:page]).per(20)
      end
      
      respond_to do |format|
        format.html
        format.json
        format.turbo_stream
      end
    end
  end
end
```

### Add Search Scope to Business Customer Model

```ruby
# app/models/business_customer.rb
class BusinessCustomer < ApplicationRecord
  # Add search functionality
  include PgSearch::Model
  
  pg_search_scope :search_text,
                  against: [:name, :domain, :contact_email],
                  associated_against: {
                    users: [:email, :name],
                    subscription: [:plan]
                  },
                  using: {
                    tsearch: { prefix: true, any_word: true },
                    trigram: {}
                  }
  
  def self.search(query, options = {})
    page = options[:page] || 1
    per_page = options[:per_page] || 20
    
    results = search_text(query)
    results.page(page).per(per_page)
  end
end
```

### Add Search Form to Layout

```erb
<!-- app/views/admin/shared/_search_form.html.erb -->
<div class="global-search" data-controller="search">
  <%= form_with url: admin_customer_search_path, method: :get, data: { action: "submit->search#search" } do |f| %>
    <div class="search-input-wrapper">
      <%= f.search_field :q, 
                       placeholder: "Search customers...", 
                       value: params[:q],
                       data: { 
                         "search-target": "input",
                         action: "input->search#typeahead focus->search#showResults blur->search#hideResultsDelayed"
                       } %>
                       
      <button type="submit" class="search-button">
        <svg><!-- Search icon --></svg>
      </button>
      
      <% if params[:q].present? %>
        <%= link_to admin_customers_path, class: "clear-search" do %>
          <svg><!-- X icon --></svg>
        <% end %>
      <% end %>
    </div>
    
    <div class="search-results-dropdown" data-search-target="results">
      <!-- Results will be inserted here via Turbo -->
    </div>
  <% end %>
</div>
```

### Create Search Results Partial

```erb
<!-- app/views/admin/searches/customers.turbo_stream.erb -->
<%= turbo_stream.replace "search_results" do %>
  <div id="search_results">
    <% if @customers.any? %>
      <ul class="search-results-list">
        <% @customers.each do |customer| %>
          <li class="search-result-item">
            <%= link_to admin_customer_path(customer), class: "search-result-link" do %>
              <div class="customer-info">
                <strong><%= highlight(customer.name, @query) %></strong>
                <% if customer.domain.present? %>
                  <span class="customer-domain"><%= highlight(customer.domain, @query) %></span>
                <% end %>
              </div>
              <div class="customer-meta">
                <span class="status-badge <%= customer.status %>"><%= customer.status.humanize %></span>
                <% if customer.subscription.present? %>
                  <span class="plan-badge"><%= customer.subscription.plan.humanize %></span>
                <% end %>
              </div>
            <% end %>
          </li>
        <% end %>
      </ul>
      
      <% if @customers.total_count > @customers.size %>
        <div class="see-all-results">
          <%= link_to "See all #{@customers.total_count} results", admin_customer_search_path(q: @query) %>
        </div>
      <% end %>
    <% else %>
      <div class="no-results">
        <p>No customers found matching "<%= @query %>"</p>
      </div>
    <% end %>
  </div>
<% end %>
```

### Add Search Stimulus Controller

```javascript
// app/javascript/controllers/search_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "results"]
  
  connect() {
    this.timeout = null
    this.clickedOutside = this.clickedOutside.bind(this)
    document.addEventListener("click", this.clickedOutside)
  }
  
  disconnect() {
    document.removeEventListener("click", this.clickedOutside)
  }
  
  typeahead() {
    clearTimeout(this.timeout)
    
    const query = this.inputTarget.value.trim()
    
    if (query.length < 2) {
      this.hideResults()
      return
    }
    
    this.timeout = setTimeout(() => {
      this.fetchResults(query)
    }, 300)
  }
  
  fetchResults(query) {
    const url = `${this.element.action}?q=${encodeURIComponent(query)}`
    
    fetch(url, {
      headers: {
        "Accept": "text/vnd.turbo-stream.html",
        "X-Requested-With": "XMLHttpRequest"
      }
    })
    .then(response => response.text())
    .then(html => {
      this.resultsTarget.innerHTML = html
      this.showResults()
    })
  }
  
  search(event) {
    if (this.inputTarget.value.trim().length < 2) {
      event.preventDefault()
      return false
    }
  }
  
  showResults() {
    this.resultsTarget.classList.add("visible")
  }
  
  hideResults() {
    this.resultsTarget.classList.remove("visible")
  }
  
  hideResultsDelayed() {
    setTimeout(() => {
      this.hideResults()
    }, 200)
  }
  
  clickedOutside(event) {
    if (!this.element.contains(event.target)) {
      this.hideResults()
    }
  }
}
```

### Add necessary gems and configurations

```ruby
# Gemfile
gem 'pg_search'
gem 'kaminari'

# Run:
# bundle install
# rails generate kaminari:config
```

## Test Cases

```ruby
# spec/features/admin/customer_search_spec.rb
require 'rails_helper'

RSpec.describe "Customer Search", type: :feature do
  let(:admin) { create(:admin_user) }
  
  before do
    sign_in admin
    create(:business_customer, name: "Acme Corporation")
    create(:business_customer, name: "Beta Industries")
    create(:business_customer, name: "Acme Startup", domain: "acmestartup.com")
  end
  
  scenario "admin searches for a customer by name" do
    visit admin_customers_path
    
    fill_in "q", with: "Acme"
    
    # Wait for debounce
    sleep 0.4
    
    within ".search-results-dropdown" do
      expect(page).to have_content("Acme Corporation")
      expect(page).to have_content("Acme Startup")
      expect(page).not_to have_content("Beta Industries")
    end
  end
  
  scenario "admin clicks on search result" do
    visit admin_customers_path
    
    fill_in "q", with: "Acme"
    sleep 0.4
    
    within ".search-results-dropdown" do
      click_link "Acme Corporation"
    end
    
    expect(page).to have_current_path(admin_customer_path(BusinessCustomer.find_by(name: "Acme Corporation")))
  end
  
  scenario "admin sees 'no results' message for non-matching search" do
    visit admin_customers_path
    
    fill_in "q", with: "NonExistentCompany"
    sleep 0.4
    
    within ".search-results-dropdown" do
      expect(page).to have_content('No customers found matching "NonExistentCompany"')
    end
  end
end
```
