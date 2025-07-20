# Task: Implement Support Impersonation System

## Overview
Build a secure system that allows support staff to temporarily impersonate customer accounts for troubleshooting purposes while maintaining proper audit logs.

## Implementation Notes

### Create Impersonation Service

```ruby
# app/services/impersonation_service.rb
class ImpersonationService
  def self.start_session(admin_user, target_user)
    # Store original user info in the session
    impersonation_data = {
      admin_id: admin_user.id,
      admin_email: admin_user.email,
      started_at: Time.current,
      target_user_id: target_user.id,
      target_user_email: target_user.email
    }
    
    # Create audit log
    AuditLog.create!(
      actor_id: admin_user.id,
      actor_type: 'AdminUser',
      action: 'impersonation_started',
      subject_id: target_user.id,
      subject_type: 'User',
      metadata: impersonation_data
    )
    
    impersonation_data
  end
  
  def self.end_session(impersonation_data)
    # Create audit log for ending impersonation
    AuditLog.create!(
      actor_id: impersonation_data[:admin_id],
      actor_type: 'AdminUser',
      action: 'impersonation_ended',
      subject_id: impersonation_data[:target_user_id],
      subject_type: 'User',
      metadata: impersonation_data.merge(
        ended_at: Time.current,
        duration_seconds: (Time.current - impersonation_data[:started_at].to_time).to_i
      )
    )
  end
end
```

### Add Impersonation Controller

```ruby
# app/controllers/admin/impersonations_controller.rb
module Admin
  class ImpersonationsController < AdminController
    before_action :require_admin_privileges
    
    def create
      user = User.find(params[:user_id])
      customer = user.business_customer
      
      # Check permissions
      authorize! :impersonate, customer
      
      # Start impersonation
      impersonation_data = ImpersonationService.start_session(current_user, user)
      session[:impersonation] = impersonation_data
      
      # Login as the target user
      sign_in(user)
      
      redirect_to root_path, notice: "You are now impersonating #{user.email}"
    end
    
    def destroy
      return redirect_to admin_root_path, alert: "No active impersonation" unless session[:impersonation]
      
      admin = AdminUser.find(session[:impersonation][:admin_id])
      ImpersonationService.end_session(session[:impersonation])
      
      # Switch back to admin user
      sign_in(admin)
      session.delete(:impersonation)
      
      redirect_to admin_root_path, notice: "Impersonation ended"
    end
    
    private
    
    def require_admin_privileges
      unless current_user.is_a?(AdminUser) || (current_user.respond_to?(:admin?) && current_user.admin?)
        redirect_to root_path, alert: "You don't have permission to perform this action"
      end
    end
  end
end
```

### Add Impersonation Banner

```erb
<!-- app/views/layouts/_impersonation_banner.html.erb -->
<% if session[:impersonation].present? %>
  <div class="impersonation-banner">
    <div class="container">
      <div class="impersonation-notice">
        You are impersonating <%= session[:impersonation][:target_user_email] %>. 
        <%= link_to "Exit Impersonation", admin_impersonation_path, method: :delete, class: "exit-button" %>
      </div>
    </div>
  </div>
<% end %>
```

### Add to Application Layout

```erb
<!-- Add to app/views/layouts/application.html.erb -->
<body>
  <%= render 'layouts/impersonation_banner' if session[:impersonation].present? %>
  <!-- ...existing code... -->
</body>
```

### CSS for Impersonation Banner

```css
/* app/assets/stylesheets/admin/impersonation.css */
.impersonation-banner {
  background-color: #7f1d1d;
  color: white;
  padding: 0.5rem 0;
  text-align: center;
  width: 100%;
  position: sticky;
  top: 0;
  z-index: 1000;
}

.impersonation-notice {
  display: flex;
  justify-content: center;
  align-items: center;
  gap: 1rem;
}

.exit-button {
  background-color: white;
  color: #7f1d1d;
  border: none;
  padding: 0.25rem 0.5rem;
  border-radius: 0.25rem;
  font-weight: 500;
  text-decoration: none;
}

.exit-button:hover {
  background-color: #f3f4f6;
}
```

## Test Cases

```ruby
# spec/services/impersonation_service_spec.rb
require 'rails_helper'

RSpec.describe ImpersonationService do
  let(:admin) { create(:admin_user) }
  let(:user) { create(:user) }
  
  describe '.start_session' do
    it 'creates an impersonation session data structure' do
      result = ImpersonationService.start_session(admin, user)
      
      expect(result[:admin_id]).to eq(admin.id)
      expect(result[:target_user_id]).to eq(user.id)
    end
    
    it 'creates an audit log entry' do
      expect {
        ImpersonationService.start_session(admin, user)
      }.to change(AuditLog, :count).by(1)
      
      log = AuditLog.last
      expect(log.action).to eq('impersonation_started')
      expect(log.actor_id).to eq(admin.id)
      expect(log.subject_id).to eq(user.id)
    end
  end
  
  describe '.end_session' do
    let(:impersonation_data) do
      {
        admin_id: admin.id,
        admin_email: admin.email,
        started_at: 5.minutes.ago,
        target_user_id: user.id,
        target_user_email: user.email
      }
    end
    
    it 'creates an audit log entry' do
      expect {
        ImpersonationService.end_session(impersonation_data)
      }.to change(AuditLog, :count).by(1)
      
      log = AuditLog.last
      expect(log.action).to eq('impersonation_ended')
      expect(log.metadata[:duration_seconds]).to be > 0
    end
  end
end
```
