# Task: Implement Activity History and Notes

## Overview
Create a system to track and display customer activity history, allow support staff to add notes to customer accounts, and maintain a comprehensive audit trail.

## Implementation Notes

### Create Activity Log Model

```ruby
# app/models/activity_log.rb
class ActivityLog < ApplicationRecord
  belongs_to :business_customer
  belongs_to :actor, polymorphic: true, optional: true
  
  validates :action, presence: true
  
  # Store additional data in JSON format
  serialize :metadata, JSON
  
  # Common activity types
  ACTIVITY_TYPES = {
    system: 'system',
    user: 'user',
    admin: 'admin',
    support: 'support'
  }
  
  # Scopes for filtering
  scope :recent, -> { order(created_at: :desc) }
  scope :by_type, ->(type) { where(activity_type: type) }
  scope :by_action, ->(action) { where(action: action) }
  
  # Helper for creating user notes
  def self.add_note(customer, actor, content)
    create!(
      business_customer: customer,
      actor: actor,
      action: 'note_added',
      activity_type: actor.is_a?(AdminUser) ? ACTIVITY_TYPES[:admin] : ACTIVITY_TYPES[:user],
      metadata: { note: content }
    )
  end
end

# Migration
# rails g model ActivityLog business_customer:references actor:references{polymorphic} \
#   action:string activity_type:string metadata:jsonb
```

### Create Customer Notes Controller

```ruby
# app/controllers/admin/customer_notes_controller.rb
module Admin
  class CustomerNotesController < AdminController
    before_action :set_customer
    
    def create
      @activity = ActivityLog.add_note(
        @customer, 
        current_user, 
        params[:content]
      )
      
      respond_to do |format|
        format.html { redirect_to admin_customer_path(@customer) }
        format.turbo_stream
      end
    end
    
    private
    
    def set_customer
      @customer = BusinessCustomer.find(params[:customer_id])
    end
  end
end
```

### Add Activity Display to Customer Detail View

```erb
<!-- app/views/admin/customers/show.html.erb (partial) -->
<div class="activity-history-section">
  <h2>Activity History</h2>
  
  <!-- Note form -->
  <div class="add-note-form">
    <%= form_with url: admin_customer_notes_path(@customer), method: :post, data: { controller: "note-form" } do |f| %>
      <div class="form-group">
        <%= f.label :content, "Add Note" %>
        <%= f.text_area :content, rows: 2, data: { action: "input->note-form#checkLength" } %>
      </div>
      <%= f.submit "Add Note", class: "btn btn-primary", data: { "note-form-target": "submit" } %>
    <% end %>
  </div>
  
  <!-- Activity list -->
  <div id="activity-list" class="activity-list">
    <%= render partial: "admin/shared/activity_log", collection: @customer.activity_logs.recent.limit(10), as: :activity %>
    
    <% if @customer.activity_logs.count > 10 %>
      <%= link_to "View All Activity", admin_customer_activities_path(@customer), class: "view-all-link" %>
    <% end %>
  </div>
</div>
```

### Add Activity Log Partial

```erb
<!-- app/views/admin/shared/_activity_log.html.erb -->
<div class="activity-item <%= activity.activity_type %>">
  <div class="activity-icon">
    <%= render "admin/shared/activity_icon", activity_type: activity.activity_type %>
  </div>
  
  <div class="activity-content">
    <div class="activity-header">
      <span class="activity-actor">
        <% if activity.actor %>
          <%= activity.actor.name || activity.actor.email %>
        <% else %>
          System
        <% end %>
      </span>
      <span class="activity-action"><%= activity_description(activity) %></span>
      <span class="activity-time"><%= time_ago_in_words(activity.created_at) %> ago</span>
    </div>
    
    <% if activity.action == 'note_added' && activity.metadata&.dig('note').present? %>
      <div class="activity-note">
        <%= simple_format(activity.metadata['note']) %>
      </div>
    <% end %>
    
    <% if activity.metadata.present? && activity.action != 'note_added' %>
      <div class="activity-details">
        <!-- Show relevant metadata -->
        <% activity.metadata.except('note').each do |key, value| %>
          <div class="metadata-item">
            <strong><%= key.to_s.humanize %>:</strong> 
            <%= value.is_a?(Hash) ? value.to_json : value.to_s %>
          </div>
        <% end %>
      </div>
    <% end %>
  </div>
</div>
```

### Add Helper Methods

```ruby
# app/helpers/activity_helper.rb
module ActivityHelper
  def activity_description(activity)
    case activity.action
    when 'note_added'
      'added a note'
    when 'customer_created'
      'created customer account'
    when 'subscription_changed'
      "changed subscription to #{activity.metadata['plan']}"
    when 'user_login'
      'logged in'
    when 'impersonation_started'
      "started impersonating #{activity.metadata['target_user_email']}"
    when 'impersonation_ended'
      "ended impersonation of #{activity.metadata['target_user_email']}"
    else
      activity.action.humanize.downcase
    end
  end
end
```

### Add CSS for Activity Logs

```css
/* app/assets/stylesheets/admin/activity_log.css */
.activity-list {
  margin-top: 1rem;
}

.activity-item {
  display: flex;
  padding: 1rem;
  border-bottom: 1px solid #e5e7eb;
}

.activity-item:last-child {
  border-bottom: none;
}

.activity-icon {
  margin-right: 1rem;
}

.activity-content {
  flex: 1;
}

.activity-header {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
  margin-bottom: 0.5rem;
  font-size: 0.875rem;
}

.activity-actor {
  font-weight: 600;
}

.activity-time {
  color: #6b7280;
}

.activity-note {
  background-color: #f9fafb;
  padding: 0.75rem;
  border-radius: 0.375rem;
  margin-top: 0.5rem;
}

.activity-item.admin {
  background-color: #eff6ff;
}

.activity-item.support {
  background-color: #f0fdf4;
}

.activity-item.system {
  background-color: #f9fafb;
}
```

## Test Cases

```ruby
# spec/models/activity_log_spec.rb
require 'rails_helper'

RSpec.describe ActivityLog, type: :model do
  let(:customer) { create(:business_customer) }
  let(:admin) { create(:admin_user) }
  
  describe 'associations' do
    it { should belong_to(:business_customer) }
    it { should belong_to(:actor).optional }
  end
  
  describe '.add_note' do
    it 'creates a note activity' do
      note_content = "Customer requested training session next week"
      
      expect {
        ActivityLog.add_note(customer, admin, note_content)
      }.to change(ActivityLog, :count).by(1)
      
      activity = ActivityLog.last
      expect(activity.action).to eq('note_added')
      expect(activity.metadata['note']).to eq(note_content)
      expect(activity.actor).to eq(admin)
    end
  end
end
```
