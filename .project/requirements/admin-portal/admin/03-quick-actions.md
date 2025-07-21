# Feature: Quick Actions Panel

## Overview
Create a dynamic action panel that provides role-based quick access to the most common administrative tasks and business operations.

## User Stories
- As a business owner, I want quick access to common tasks so I can work efficiently
- As a staff member, I want to see only the actions I'm authorized to perform
- As a user, I want to see relevant counts and notifications on action buttons

## Tasks

### 1. Create Quick Actions Component
**File**: `app/components/quick_actions_component.rb`

**Implementation Notes**:
```ruby
class QuickActionsComponent < ViewComponent::Base
  def initialize(business_user:, business:)
    @business_user = business_user
    @business = business
    @actions_service = QuickActionsService.new(business_user)
  end
  
  private
  
  attr_reader :business_user, :business, :actions_service
  
  def available_actions
    @available_actions ||= actions_service.available_actions
  end
  
  def action_icon_class(icon_name)
    {
      'document-plus' => 'M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z',
      'calendar-plus' => 'M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z',
      'users' => 'M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197m13.5-9a2.5 2.5 0 11-5 0 2.5 2.5 0 015 0z',
      'cog' => 'M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z',
      'chart-bar' => 'M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z',
      'user-group' => 'M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z',
      'adjustments' => 'M12 6V4m0 2a2 2 0 100 4m0-4a2 2 0 110 4m-6 8a2 2 0 100-4m0 4a2 2 0 100 4m0-4v2m0-6V4m6 6v10m6-2a2 2 0 100-4m0 4a2 2 0 100 4m0-4v2m0-6V4'
    }[icon_name] || icon_name
  end
  
  def color_classes(color)
    {
      'blue' => {
        bg: 'bg-blue-500',
        hover: 'hover:bg-blue-600',
        text: 'text-white',
        count_bg: 'bg-blue-600',
        border: 'border-blue-200'
      },
      'green' => {
        bg: 'bg-green-500',
        hover: 'hover:bg-green-600',
        text: 'text-white',
        count_bg: 'bg-green-600',
        border: 'border-green-200'
      },
      'purple' => {
        bg: 'bg-purple-500',
        hover: 'hover:bg-purple-600',
        text: 'text-white',
        count_bg: 'bg-purple-600',
        border: 'border-purple-200'
      },
      'yellow' => {
        bg: 'bg-yellow-500',
        hover: 'hover:bg-yellow-600',
        text: 'text-white',
        count_bg: 'bg-yellow-600',
        border: 'border-yellow-200'
      },
      'indigo' => {
        bg: 'bg-indigo-500',
        hover: 'hover:bg-indigo-600',
        text: 'text-white',
        count_bg: 'bg-indigo-600',
        border: 'border-indigo-200'
      },
      'pink' => {
        bg: 'bg-pink-500',
        hover: 'hover:bg-pink-600',
        text: 'text-white',
        count_bg: 'bg-pink-600',
        border: 'border-pink-200'
      },
      'gray' => {
        bg: 'bg-gray-500',
        hover: 'hover:bg-gray-600',
        text: 'text-white',
        count_bg: 'bg-gray-600',
        border: 'border-gray-200'
      }
    }[color] || color_classes('gray')
  end
end
```

### 2. Create Quick Actions View Template
**File**: `app/components/quick_actions_component.html.erb`

**Implementation Notes**:
```erb
<div class="bg-white shadow rounded-lg">
  <div class="px-6 py-4 border-b border-gray-200">
    <h3 class="text-lg font-medium text-gray-900">Quick Actions</h3>
    <p class="text-sm text-gray-500 mt-1">Common tasks for your business</p>
  </div>
  
  <div class="p-6">
    <div class="grid grid-cols-1 gap-4">
      <% available_actions.each do |action| %>
        <% colors = color_classes(action[:color]) %>
        
        <div class="relative group">
          <%= link_to action[:url], 
                      class: "block w-full #{colors[:bg]} #{colors[:hover]} #{colors[:text]} rounded-lg p-4 transition-all duration-200 transform group-hover:scale-105 shadow-sm hover:shadow-md" do %>
            
            <div class="flex items-center justify-between">
              <div class="flex items-center">
                <!-- Action Icon -->
                <div class="flex-shrink-0">
                  <svg class="h-6 w-6 #{colors[:text]}" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="<%= action_icon_class(action[:icon]) %>" />
                  </svg>
                </div>
                
                <!-- Action Details -->
                <div class="ml-4">
                  <h4 class="text-sm font-semibold"><%= action[:title] %></h4>
                  <p class="text-xs opacity-90 mt-1"><%= action[:description] %></p>
                </div>
              </div>
              
              <!-- Count Badge (if present) -->
              <% if action[:count] && action[:count] > 0 %>
                <div class="flex-shrink-0">
                  <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{colors[:count_bg]} text-white">
                    <%= action[:count] %>
                  </span>
                </div>
              <% end %>
            </div>
            
            <!-- Progress Indicator (if applicable) -->
            <% if action[:progress] %>
              <div class="mt-3">
                <div class="bg-white bg-opacity-20 rounded-full h-2">
                  <div class="bg-white rounded-full h-2 transition-all duration-300" 
                       style="width: <%= action[:progress] %>%"></div>
                </div>
                <p class="text-xs opacity-75 mt-1"><%= action[:progress] %>% complete</p>
              </div>
            <% end %>
          <% end %>
        </div>
      <% end %>
    </div>
    
    <!-- Additional Actions Toggle -->
    <% if available_actions.count > 6 %>
      <div class="mt-6 pt-6 border-t border-gray-200">
        <button type="button" 
                class="w-full text-center text-sm text-gray-500 hover:text-gray-700 transition-colors"
                data-action="click->quick-actions#toggleAdditional">
          <span data-quick-actions-target="toggleText">Show More Actions</span>
          <svg class="w-4 h-4 inline ml-1 transform transition-transform" data-quick-actions-target="toggleIcon">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
          </svg>
        </button>
      </div>
    <% end %>
  </div>
</div>
```

### 3. Create Recent Tasks Tracker Service
**File**: `app/services/recent_tasks_service.rb`

**Implementation Notes**:
```ruby
class RecentTasksService
  def initialize(business_user)
    @business_user = business_user
    @user = business_user.user
    @business = business_user.business
  end
  
  def recent_tasks(limit: 5)
    [
      recent_quotes_created(limit: 2),
      recent_jobs_scheduled(limit: 2),
      recent_customers_added(limit: 1)
    ].flatten.sort_by { |task| task[:timestamp] }.reverse.take(limit)
  end
  
  def suggested_actions
    suggestions = []
    
    # Suggest based on pending items
    suggestions << quote_followup_suggestions
    suggestions << scheduling_suggestions
    suggestions << customer_engagement_suggestions
    
    suggestions.flatten.compact.take(3)
  end
  
  def productivity_stats
    today = Date.current
    {
      today: {
        quotes_created: quotes_created_today,
        jobs_scheduled: jobs_scheduled_today,
        customers_contacted: customers_contacted_today
      },
      this_week: {
        quotes_created: quotes_created_this_week,
        jobs_completed: jobs_completed_this_week,
        revenue_generated: revenue_this_week
      }
    }
  end
  
  private
  
  def recent_quotes_created(limit:)
    @business.quotes
             .where(created_by: @user)
             .recent
             .limit(limit)
             .map do |quote|
      {
        type: 'quote_created',
        title: "Quote ##{quote.quote_number} created",
        description: "For #{quote.customer_name}",
        timestamp: quote.created_at,
        url: admin_quote_path(quote),
        status: quote.status
      }
    end
  end
  
  def recent_jobs_scheduled(limit:)
    @business.appointments
             .where(scheduled_by: @user)
             .recent
             .limit(limit)
             .map do |appointment|
      {
        type: 'job_scheduled',
        title: "Job scheduled",
        description: "#{appointment.service_name} on #{appointment.scheduled_date.strftime('%m/%d')}",
        timestamp: appointment.created_at,
        url: admin_appointment_path(appointment),
        status: appointment.status
      }
    end
  end
  
  def recent_customers_added(limit:)
    # This would track customer creation or first contact
    @business.quotes
             .where(created_by: @user)
             .joins("LEFT JOIN quotes q2 ON q2.customer_email = quotes.customer_email AND q2.created_at < quotes.created_at")
             .where("q2.id IS NULL") # First quote for this customer
             .recent
             .limit(limit)
             .map do |quote|
      {
        type: 'customer_added',
        title: "New customer added",
        description: quote.customer_name,
        timestamp: quote.created_at,
        url: admin_customer_path(quote.customer_email),
        status: 'new'
      }
    end
  end
  
  def quote_followup_suggestions
    overdue_quotes = @business.quotes.pending.where('created_at < ?', 3.days.ago)
    
    return nil if overdue_quotes.empty?
    
    {
      type: 'followup',
      title: 'Follow up on pending quotes',
      description: "#{overdue_quotes.count} quotes need attention",
      action_url: admin_quotes_path(status: 'pending'),
      priority: 'high'
    }
  end
  
  def scheduling_suggestions
    approved_quotes = @business.quotes.approved.joins("LEFT JOIN appointments ON appointments.quote_id = quotes.id").where("appointments.id IS NULL")
    
    return nil if approved_quotes.empty?
    
    {
      type: 'scheduling',
      title: 'Schedule approved jobs',
      description: "#{approved_quotes.count} jobs ready to schedule",
      action_url: admin_appointments_path(filter: 'unscheduled'),
      priority: 'medium'
    }
  end
  
  def customer_engagement_suggestions
    # Suggest following up with customers who haven't had service in a while
    inactive_customers = @business.quotes
                                 .approved
                                 .where('updated_at < ?', 6.months.ago)
                                 .group(:customer_email)
                                 .count
    
    return nil if inactive_customers.empty?
    
    {
      type: 'engagement',
      title: 'Re-engage past customers',
      description: "#{inactive_customers.count} customers to contact",
      action_url: admin_customers_path(filter: 'inactive'),
      priority: 'low'
    }
  end
  
  # Productivity metrics
  def quotes_created_today
    @business.quotes.where(created_by: @user, created_at: Date.current.all_day).count
  end
  
  def jobs_scheduled_today
    @business.appointments.where(scheduled_by: @user, created_at: Date.current.all_day).count
  end
  
  def customers_contacted_today
    # This would track communication logs
    @business.activity_logs.where(user: @user, action: 'customer_contacted', occurred_at: Date.current.all_day).count
  end
  
  def quotes_created_this_week
    @business.quotes.where(created_by: @user, created_at: Date.current.beginning_of_week..Date.current.end_of_week).count
  end
  
  def jobs_completed_this_week
    @business.appointments.completed.where(created_at: Date.current.beginning_of_week..Date.current.end_of_week).count
  end
  
  def revenue_this_week
    @business.quotes.approved.where(approved_at: Date.current.beginning_of_week..Date.current.end_of_week).sum(:total_amount)
  end
end
```

### 4. Create Shared Quick Actions Partial
**File**: `app/views/shared/_quick_actions_panel.html.erb`

**Implementation Notes**:
```erb
<div class="space-y-6">
  <!-- Primary Quick Actions -->
  <%= render QuickActionsComponent.new(
        business_user: current_user.business_users.find_by(business: @business),
        business: @business
      ) %>
  
  <!-- Recent Activity Summary -->
  <div class="bg-white shadow rounded-lg">
    <div class="px-6 py-4 border-b border-gray-200">
      <h3 class="text-lg font-medium text-gray-900">Your Recent Activity</h3>
    </div>
    
    <div class="p-6">
      <% recent_tasks = RecentTasksService.new(current_user.business_users.find_by(business: @business)).recent_tasks %>
      
      <% if recent_tasks.any? %>
        <div class="space-y-3">
          <% recent_tasks.each do |task| %>
            <div class="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
              <div class="flex items-center">
                <div class="flex-shrink-0">
                  <% case task[:type] %>
                  <% when 'quote_created' %>
                    <div class="w-8 h-8 bg-blue-100 rounded-full flex items-center justify-center">
                      <svg class="w-4 h-4 text-blue-600" fill="currentColor" viewBox="0 0 20 20">
                        <path d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/>
                      </svg>
                    </div>
                  <% when 'job_scheduled' %>
                    <div class="w-8 h-8 bg-green-100 rounded-full flex items-center justify-center">
                      <svg class="w-4 h-4 text-green-600" fill="currentColor" viewBox="0 0 20 20">
                        <path d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"/>
                      </svg>
                    </div>
                  <% when 'customer_added' %>
                    <div class="w-8 h-8 bg-purple-100 rounded-full flex items-center justify-center">
                      <svg class="w-4 h-4 text-purple-600" fill="currentColor" viewBox="0 0 20 20">
                        <path d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197m13.5-9a2.5 2.5 0 11-5 0 2.5 2.5 0 015 0z"/>
                      </svg>
                    </div>
                  <% end %>
                </div>
                <div class="ml-3">
                  <p class="text-sm font-medium text-gray-900"><%= task[:title] %></p>
                  <p class="text-xs text-gray-500"><%= task[:description] %></p>
                </div>
              </div>
              <div class="text-right">
                <p class="text-xs text-gray-500">
                  <%= time_ago_in_words(task[:timestamp]) %> ago
                </p>
                <% if task[:url] %>
                  <%= link_to "View", task[:url], class: "text-xs text-blue-600 hover:text-blue-800" %>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      <% else %>
        <div class="text-center py-6">
          <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"/>
          </svg>
          <p class="text-sm text-gray-500 mt-2">No recent activity</p>
          <p class="text-xs text-gray-400">Start by creating a quote or scheduling a job</p>
        </div>
      <% end %>
    </div>
  </div>
  
  <!-- Productivity Stats -->
  <div class="bg-white shadow rounded-lg">
    <div class="px-6 py-4 border-b border-gray-200">
      <h3 class="text-lg font-medium text-gray-900">Today's Progress</h3>
    </div>
    
    <div class="p-6">
      <% productivity = RecentTasksService.new(current_user.business_users.find_by(business: @business)).productivity_stats %>
      
      <div class="grid grid-cols-3 gap-4 text-center">
        <div>
          <p class="text-2xl font-bold text-blue-600"><%= productivity[:today][:quotes_created] %></p>
          <p class="text-xs text-gray-500">Quotes Created</p>
        </div>
        <div>
          <p class="text-2xl font-bold text-green-600"><%= productivity[:today][:jobs_scheduled] %></p>
          <p class="text-xs text-gray-500">Jobs Scheduled</p>
        </div>
        <div>
          <p class="text-2xl font-bold text-purple-600"><%= productivity[:today][:customers_contacted] %></p>
          <p class="text-xs text-gray-500">Customers Contacted</p>
        </div>
      </div>
    </div>
  </div>
</div>

<script data-turbo-track="reload">
  // Stimulus controller for Quick Actions interactivity
  class QuickActionsController extends Stimulus.Controller {
    static targets = ["toggleText", "toggleIcon", "additionalActions"]
    
    toggleAdditional() {
      const isShowing = this.toggleTextTarget.textContent.includes("Show More");
      
      if (isShowing) {
        this.toggleTextTarget.textContent = "Show Fewer Actions";
        this.toggleIconTarget.style.transform = "rotate(180deg)";
        // Show additional actions logic would go here
      } else {
        this.toggleTextTarget.textContent = "Show More Actions";
        this.toggleIconTarget.style.transform = "rotate(0deg)";
        // Hide additional actions logic would go here
      }
    }
  }
  
  Stimulus.register("quick-actions", QuickActionsController);
</script>
```

## Acceptance Criteria
- [ ] Displays role-appropriate actions based on user permissions
- [ ] Shows relevant count badges for actions requiring attention
- [ ] Provides quick access to most common business operations
- [ ] Recent activity tracking works correctly
- [ ] Productivity stats display accurately
- [ ] Action buttons have proper hover effects and transitions
- [ ] Panel is responsive across different screen sizes
- [ ] Suggested actions appear based on business state

## Testing Requirements
- Component tests for quick actions rendering
- Service tests for recent tasks tracking
- Authorization tests for role-based action visibility
- Integration tests for action count accuracy
- JavaScript tests for interactive elements
