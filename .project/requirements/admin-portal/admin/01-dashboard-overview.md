# Feature: Dashboard Overview

## Description
The main dashboard layout that serves as the primary interface for administrators, featuring customizable widgets, navigation, and a responsive design that adapts to different screen sizes and user roles.

## User Stories
- As a business owner, I want to customize my dashboard layout so I can see the most relevant information first
- As a manager, I want a clean, organized interface so I can efficiently navigate between different functions
- As an admin user, I want the dashboard to load quickly so I can start working immediately
- As a mobile user, I want the dashboard to work well on my tablet so I can manage my business on the go

## Tasks

### Task 1: Create Dashboard Controller and Routes
**Implementation Notes:**
- Create `app/controllers/admin/dashboard_controller.rb`
- Add routes for dashboard and widget management
- Implement role-based access control
- Set up layout and navigation structure

```ruby
# config/routes.rb
namespace :admin do
  root 'dashboard#index'
  resources :dashboard, only: [:index] do
    collection do
      patch :update_layout
      get :widget_data
    end
  end
end

# app/controllers/admin/dashboard_controller.rb
class Admin::DashboardController < Admin::BaseController
  before_action :authenticate_admin!
  before_action :authorize_dashboard_access!

  def index
    @dashboard_config = current_admin.dashboard_configuration || build_default_config
    @widgets = DashboardWidgetService.new(current_admin).available_widgets
  end

  def update_layout
    DashboardConfigurationService.new(current_admin)
                                 .update_layout(dashboard_params[:widget_layout])
    head :ok
  end

  def widget_data
    widget_type = params[:widget_type]
    data = DashboardDataService.new(current_admin).widget_data(widget_type)
    render json: data
  end

  private

  def dashboard_params
    params.require(:dashboard).permit(widget_layout: [])
  end

  def build_default_config
    DashboardConfiguration.create!(
      admin: current_admin,
      widget_layout: %w[metrics bookings recent_activity quick_actions]
    )
  end
end
```

### Task 2: Create Dashboard Models
**Implementation Notes:**
- Create models for dashboard configuration and widget management
- Implement widget positioning and customization
- Add validation and default configurations

```ruby
# app/models/dashboard_configuration.rb
class DashboardConfiguration < ApplicationRecord
  belongs_to :admin, class_name: 'User'
  
  validates :widget_layout, presence: true
  validates :admin_id, uniqueness: true
  
  serialize :widget_layout, Array
  serialize :widget_settings, Hash
  
  AVAILABLE_WIDGETS = %w[
    metrics
    bookings_today
    recent_bookings
    revenue_chart
    quick_actions
    recent_activity
    staff_status
    upcoming_appointments
  ].freeze
  
  validates :widget_layout, subset: { of: AVAILABLE_WIDGETS }
  
  def widget_enabled?(widget_name)
    widget_layout.include?(widget_name.to_s)
  end
  
  def widget_setting(widget_name, setting_key, default = nil)
    widget_settings.dig(widget_name.to_s, setting_key.to_s) || default
  end
end

# Migration
# rails g migration CreateDashboardConfigurations admin:references widget_layout:text widget_settings:text
class CreateDashboardConfigurations < ActiveRecord::Migration[8.0]
  def change
    create_table :dashboard_configurations do |t|
      t.references :admin, null: false, foreign_key: { to_table: :users }
      t.text :widget_layout, null: false
      t.text :widget_settings, default: '{}'
      t.timestamps
    end
    
    add_index :dashboard_configurations, :admin_id, unique: true
  end
end
```

### Task 3: Create Dashboard Layout and Views
**Implementation Notes:**
- Responsive grid layout using Tailwind CSS
- Drag-and-drop widget positioning (using Stimulus)
- Mobile-first design approach

```erb
<!-- app/views/admin/dashboard/index.html.erb -->
<div class="min-h-screen bg-gray-50" data-controller="dashboard">
  <!-- Header -->
  <div class="bg-white shadow-sm border-b border-gray-200">
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
      <div class="flex justify-between items-center py-4">
        <div>
          <h1 class="text-2xl font-bold text-gray-900">Dashboard</h1>
          <p class="text-sm text-gray-600">Welcome back, <%= current_admin.name %></p>
        </div>
        <div class="flex items-center space-x-4">
          <button 
            data-action="click->dashboard#toggleCustomize"
            class="btn btn-secondary"
          >
            <i class="fas fa-cog mr-2"></i>
            Customize
          </button>
          <div class="text-sm text-gray-500">
            Last updated: <span data-dashboard-target="lastUpdated"></span>
          </div>
        </div>
      </div>
    </div>
  </div>

  <!-- Dashboard Content -->
  <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
    <div 
      class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6"
      data-dashboard-target="widgetGrid"
      data-sortable="true"
    >
      <% @dashboard_config.widget_layout.each do |widget_name| %>
        <%= render "admin/dashboard/widgets/#{widget_name}", 
                   config: @dashboard_config,
                   admin: current_admin %>
      <% end %>
    </div>
  </div>

  <!-- Customize Panel -->
  <div 
    class="fixed inset-y-0 right-0 w-80 bg-white shadow-xl transform translate-x-full transition-transform duration-300"
    data-dashboard-target="customizePanel"
  >
    <div class="p-6">
      <h3 class="text-lg font-medium mb-4">Customize Dashboard</h3>
      <div class="space-y-4">
        <% DashboardConfiguration::AVAILABLE_WIDGETS.each do |widget| %>
          <label class="flex items-center">
            <input 
              type="checkbox" 
              value="<%= widget %>"
              data-action="change->dashboard#toggleWidget"
              <%= 'checked' if @dashboard_config.widget_enabled?(widget) %>
              class="mr-3"
            >
            <span class="capitalize"><%= widget.humanize %></span>
          </label>
        <% end %>
      </div>
      <div class="mt-6">
        <button 
          data-action="click->dashboard#saveLayout"
          class="btn btn-primary w-full"
        >
          Save Changes
        </button>
      </div>
    </div>
  </div>
</div>
```

### Task 4: Create Dashboard Stimulus Controller
**Implementation Notes:**
- Widget reordering functionality
- Real-time updates
- Customization panel management

```javascript
// app/javascript/controllers/dashboard_controller.js
import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
  static targets = ["widgetGrid", "customizePanel", "lastUpdated"]

  connect() {
    this.initializeSortable()
    this.updateTimestamp()
    this.startAutoRefresh()
  }

  disconnect() {
    if (this.refreshInterval) {
      clearInterval(this.refreshInterval)
    }
  }

  initializeSortable() {
    this.sortable = Sortable.create(this.widgetGridTarget, {
      animation: 150,
      ghostClass: "opacity-50",
      onEnd: (evt) => {
        this.saveWidgetOrder()
      }
    })
  }

  toggleCustomize() {
    this.customizePanelTarget.classList.toggle("translate-x-full")
  }

  toggleWidget(event) {
    const widget = event.target.value
    const enabled = event.target.checked
    
    // Add or remove widget from grid
    if (enabled) {
      this.addWidget(widget)
    } else {
      this.removeWidget(widget)
    }
  }

  saveLayout() {
    const widgetOrder = Array.from(this.widgetGridTarget.children)
                             .map(el => el.dataset.widget)
    
    fetch('/admin/dashboard', {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      },
      body: JSON.stringify({
        dashboard: { widget_layout: widgetOrder }
      })
    })
    .then(() => {
      this.toggleCustomize()
      this.showSuccess("Dashboard layout saved")
    })
  }

  startAutoRefresh() {
    this.refreshInterval = setInterval(() => {
      this.refreshWidgets()
      this.updateTimestamp()
    }, 30000) // Refresh every 30 seconds
  }

  refreshWidgets() {
    const widgets = this.widgetGridTarget.querySelectorAll('[data-widget-refresh]')
    widgets.forEach(widget => {
      const widgetType = widget.dataset.widget
      fetch(`/admin/dashboard/widget_data?widget_type=${widgetType}`)
        .then(response => response.json())
        .then(data => {
          this.updateWidgetData(widget, data)
        })
    })
  }

  updateTimestamp() {
    this.lastUpdatedTarget.textContent = new Date().toLocaleTimeString()
  }

  updateWidgetData(widget, data) {
    // Update specific widget content based on data
    const valueElements = widget.querySelectorAll('[data-widget-value]')
    valueElements.forEach(el => {
      const key = el.dataset.widgetValue
      if (data[key] !== undefined) {
        el.textContent = data[key]
      }
    })
  }

  showSuccess(message) {
    // Simple success notification
    const notification = document.createElement('div')
    notification.className = 'fixed top-4 right-4 bg-green-500 text-white px-4 py-2 rounded shadow'
    notification.textContent = message
    document.body.appendChild(notification)
    
    setTimeout(() => {
      notification.remove()
    }, 3000)
  }
}
```

## Acceptance Criteria
- [ ] Dashboard loads within 2 seconds with all widgets
- [ ] Responsive design works on mobile, tablet, and desktop
- [ ] Users can customize widget layout and save preferences
- [ ] Real-time updates work without manual refresh
- [ ] Role-based access control prevents unauthorized access
- [ ] Drag-and-drop widget reordering functions correctly

## Testing Requirements
- Unit tests for dashboard controller and models
- Integration tests for widget customization
- Performance tests for dashboard load times
- Mobile responsiveness testing
- Security testing for access controls
