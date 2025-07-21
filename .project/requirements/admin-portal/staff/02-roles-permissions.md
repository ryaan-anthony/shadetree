# Feature: Role & Permission Management

## Overview
Implement a role-based access control system that allows business owners to assign different permission levels to staff members.

## User Stories
- As a business owner, I want to assign roles to staff so they have appropriate access levels
- As a business owner, I want to control what features staff can access based on their role
- As a staff member, I want to see only the features I'm authorized to use

## Tasks

### 1. Extend BusinessUser Model with Permissions
**File**: `app/models/business_user.rb` (extending existing)

**Implementation Notes**:
```ruby
class BusinessUser < ApplicationRecord
  # ...existing code...
  
  # Role-based permission methods
  def can_manage_quotes?
    manager? || admin? || owner?
  end
  
  def can_view_all_quotes?
    manager? || admin? || owner?
  end
  
  def can_manage_appointments?
    manager? || admin? || owner?
  end
  
  def can_view_customer_data?
    manager? || admin? || owner?
  end
  
  def can_process_payments?
    admin? || owner?
  end
  
  def can_view_reports?
    manager? || admin? || owner?
  end
  
  def can_manage_services?
    admin? || owner?
  end
  
  def can_export_data?
    admin? || owner?
  end
  
  def permission_summary
    {
      quotes: {
        view_own: true,
        view_all: can_view_all_quotes?,
        manage: can_manage_quotes?
      },
      appointments: {
        view_own: true,
        view_all: can_manage_appointments?,
        manage: can_manage_appointments?
      },
      customers: {
        view: can_view_customer_data?,
        edit: can_manage_quotes?
      },
      payments: {
        view: can_view_reports?,
        process: can_process_payments?
      },
      business: {
        view_reports: can_view_reports?,
        manage_services: can_manage_services?,
        manage_staff: can_manage_staff?,
        manage_settings: can_manage_business_settings?,
        export_data: can_export_data?
      }
    }
  end
end
```

### 2. Create Authorization Service
**File**: `app/services/authorization_service.rb`

**Implementation Notes**:
```ruby
class AuthorizationService
  def initialize(user, business)
    @user = user
    @business = business
    @business_user = user.business_users.find_by(business: business)
  end
  
  def authorized_for?(action, resource = nil)
    return false unless @business_user&.is_active?
    
    case action
    when :view_quotes
      @business_user.can_view_all_quotes? || owns_resource?(resource)
    when :manage_quotes
      @business_user.can_manage_quotes?
    when :view_appointments
      @business_user.can_manage_appointments? || owns_resource?(resource)
    when :manage_appointments
      @business_user.can_manage_appointments?
    when :view_customers
      @business_user.can_view_customer_data?
    when :process_payments
      @business_user.can_process_payments?
    when :view_reports
      @business_user.can_view_reports?
    when :manage_services
      @business_user.can_manage_services?
    when :manage_staff
      @business_user.can_manage_staff?
    when :manage_business_settings
      @business_user.can_manage_business_settings?
    when :export_data
      @business_user.can_export_data?
    else
      false
    end
  end
  
  def accessible_quotes
    if @business_user.can_view_all_quotes?
      @business.quotes
    else
      @business.quotes.where(assigned_to: @user)
    end
  end
  
  def accessible_appointments
    if @business_user.can_manage_appointments?
      @business.appointments
    else
      @business.appointments.where(assigned_to: @user)
    end
  end
  
  private
  
  def owns_resource?(resource)
    return false unless resource
    
    case resource.class.name
    when 'Quote'
      resource.assigned_to == @user || resource.created_by == @user
    when 'Appointment'
      resource.assigned_to == @user
    else
      false
    end
  end
end
```

### 3. Create Authorization Helper
**File**: `app/helpers/authorization_helper.rb`

**Implementation Notes**:
```ruby
module AuthorizationHelper
  def current_business_user
    return @current_business_user if defined?(@current_business_user)
    
    @current_business_user = current_user&.business_users&.find_by(business: current_business)
  end
  
  def authorized_for?(action, resource = nil)
    return false unless current_user && current_business
    
    @authorization_service ||= AuthorizationService.new(current_user, current_business)
    @authorization_service.authorized_for?(action, resource)
  end
  
  def role_badge_class(role)
    case role.to_s
    when 'owner'
      'bg-purple-100 text-purple-800'
    when 'admin'
      'bg-red-100 text-red-800'
    when 'manager'
      'bg-blue-100 text-blue-800'
    when 'staff'
      'bg-green-100 text-green-800'
    else
      'bg-gray-100 text-gray-800'
    end
  end
  
  def permission_description(role)
    case role.to_s
    when 'owner'
      'Full access to all business features and settings'
    when 'admin'
      'Manage business settings, staff, and all operations'
    when 'manager'
      'View reports, manage quotes and appointments'
    when 'staff'
      'Basic access to assigned quotes and appointments'
    else
      'Limited access'
    end
  end
end
```

### 4. Role Management Controller
**File**: `app/controllers/admin/roles_controller.rb`

**Implementation Notes**:
```ruby
class Admin::RolesController < Admin::BaseController
  before_action :set_business
  before_action :ensure_can_manage_staff
  before_action :set_business_user, only: [:show, :edit, :update]
  
  def index
    @business_users = @business.business_users.active.includes(:user)
    @role_permissions = role_permissions_matrix
  end
  
  def edit
  end
  
  def update
    old_role = @business_user.role
    
    if @business_user.update(role_params)
      # Log role change
      log_role_change(old_role, @business_user.role)
      
      redirect_to admin_roles_path, 
                  notice: "#{@business_user.user.name}'s role updated to #{@business_user.role.titleize}"
    else
      render :edit, status: :unprocessable_entity
    end
  end
  
  def permissions_matrix
    @role_permissions = role_permissions_matrix
    render partial: 'permissions_matrix'
  end
  
  private
  
  def set_business
    @business = current_user.owned_business || current_user.business
  end
  
  def ensure_can_manage_staff
    business_user = current_user.business_users.find_by(business: @business)
    redirect_to admin_dashboard_path unless business_user&.can_manage_staff?
  end
  
  def set_business_user
    @business_user = @business.business_users.find(params[:id])
  end
  
  def role_params
    params.require(:business_user).permit(:role)
  end
  
  def log_role_change(old_role, new_role)
    Rails.logger.info "Role changed for user #{@business_user.user.email} in business #{@business.name}: #{old_role} -> #{new_role}"
  end
  
  def role_permissions_matrix
    {
      staff: {
        quotes: { view_own: true, view_all: false, manage: false },
        appointments: { view_own: true, view_all: false, manage: false },
        customers: { view: false, edit: false },
        payments: { view: false, process: false },
        business: { 
          view_reports: false, 
          manage_services: false, 
          manage_staff: false, 
          manage_settings: false,
          export_data: false
        }
      },
      manager: {
        quotes: { view_own: true, view_all: true, manage: true },
        appointments: { view_own: true, view_all: true, manage: true },
        customers: { view: true, edit: true },
        payments: { view: true, process: false },
        business: { 
          view_reports: true, 
          manage_services: false, 
          manage_staff: false, 
          manage_settings: false,
          export_data: false
        }
      },
      admin: {
        quotes: { view_own: true, view_all: true, manage: true },
        appointments: { view_own: true, view_all: true, manage: true },
        customers: { view: true, edit: true },
        payments: { view: true, process: true },
        business: { 
          view_reports: true, 
          manage_services: true, 
          manage_staff: true, 
          manage_settings: true,
          export_data: true
        }
      },
      owner: {
        quotes: { view_own: true, view_all: true, manage: true },
        appointments: { view_own: true, view_all: true, manage: true },
        customers: { view: true, edit: true },
        payments: { view: true, process: true },
        business: { 
          view_reports: true, 
          manage_services: true, 
          manage_staff: true, 
          manage_settings: true,
          export_data: true
        }
      }
    }
  end
end
```

### 5. Role Management Views
**File**: `app/views/admin/roles/index.html.erb`

**Implementation Notes**:
```erb
<div class="max-w-6xl mx-auto py-8">
  <div class="flex justify-between items-center mb-6">
    <h1 class="text-2xl font-bold text-gray-900">Role Management</h1>
  </div>
  
  <!-- Staff Members with Roles -->
  <div class="bg-white shadow rounded-lg mb-8">
    <div class="px-6 py-4 border-b border-gray-200">
      <h2 class="text-lg font-medium text-gray-900">Staff Roles</h2>
    </div>
    
    <div class="overflow-x-auto">
      <table class="min-w-full divide-y divide-gray-200">
        <thead class="bg-gray-50">
          <tr>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Staff Member</th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Current Role</th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Permissions</th>
            <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">Actions</th>
          </tr>
        </thead>
        <tbody class="bg-white divide-y divide-gray-200">
          <% @business_users.each do |business_user| %>
            <tr>
              <td class="px-6 py-4 whitespace-nowrap">
                <div class="flex items-center">
                  <div class="h-8 w-8 rounded-full bg-gray-300 flex items-center justify-center">
                    <span class="text-sm font-medium text-gray-700">
                      <%= business_user.user.name.first.upcase %>
                    </span>
                  </div>
                  <div class="ml-3">
                    <div class="text-sm font-medium text-gray-900"><%= business_user.user.name %></div>
                    <div class="text-sm text-gray-500"><%= business_user.user.email %></div>
                  </div>
                </div>
              </td>
              <td class="px-6 py-4 whitespace-nowrap">
                <span class="inline-flex px-2 py-1 text-xs font-semibold rounded-full <%= role_badge_class(business_user.role) %>">
                  <%= business_user.role.titleize %>
                </span>
              </td>
              <td class="px-6 py-4">
                <div class="text-sm text-gray-600">
                  <%= permission_description(business_user.role) %>
                </div>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                <% unless business_user.owner? %>
                  <%= link_to "Edit Role", edit_admin_role_path(business_user), 
                              class: "text-blue-600 hover:text-blue-900" %>
                <% end %>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
  </div>
  
  <!-- Permissions Matrix -->
  <div class="bg-white shadow rounded-lg">
    <div class="px-6 py-4 border-b border-gray-200">
      <h2 class="text-lg font-medium text-gray-900">Role Permissions Matrix</h2>
      <p class="text-sm text-gray-600">Overview of what each role can do</p>
    </div>
    
    <div class="p-6">
      <div class="overflow-x-auto">
        <table class="min-w-full">
          <thead>
            <tr class="border-b border-gray-200">
              <th class="text-left py-3 text-sm font-medium text-gray-900">Permission</th>
              <th class="text-center py-3 text-sm font-medium text-gray-900">Staff</th>
              <th class="text-center py-3 text-sm font-medium text-gray-900">Manager</th>
              <th class="text-center py-3 text-sm font-medium text-gray-900">Admin</th>
              <th class="text-center py-3 text-sm font-medium text-gray-900">Owner</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-100">
            <tr>
              <td class="py-2 text-sm text-gray-900">View own quotes</td>
              <td class="text-center py-2"><span class="text-green-500">✓</span></td>
              <td class="text-center py-2"><span class="text-green-500">✓</span></td>
              <td class="text-center py-2"><span class="text-green-500">✓</span></td>
              <td class="text-center py-2"><span class="text-green-500">✓</span></td>
            </tr>
            <tr>
              <td class="py-2 text-sm text-gray-900">View all quotes</td>
              <td class="text-center py-2"><span class="text-red-500">✗</span></td>
              <td class="text-center py-2"><span class="text-green-500">✓</span></td>
              <td class="text-center py-2"><span class="text-green-500">✓</span></td>
              <td class="text-center py-2"><span class="text-green-500">✓</span></td>
            </tr>
            <tr>
              <td class="py-2 text-sm text-gray-900">Manage quotes</td>
              <td class="text-center py-2"><span class="text-red-500">✗</span></td>
              <td class="text-center py-2"><span class="text-green-500">✓</span></td>
              <td class="text-center py-2"><span class="text-green-500">✓</span></td>
              <td class="text-center py-2"><span class="text-green-500">✓</span></td>
            </tr>
            <tr>
              <td class="py-2 text-sm text-gray-900">Process payments</td>
              <td class="text-center py-2"><span class="text-red-500">✗</span></td>
              <td class="text-center py-2"><span class="text-red-500">✗</span></td>
              <td class="text-center py-2"><span class="text-green-500">✓</span></td>
              <td class="text-center py-2"><span class="text-green-500">✓</span></td>
            </tr>
            <tr>
              <td class="py-2 text-sm text-gray-900">Manage staff</td>
              <td class="text-center py-2"><span class="text-red-500">✗</span></td>
              <td class="text-center py-2"><span class="text-red-500">✗</span></td>
              <td class="text-center py-2"><span class="text-green-500">✓</span></td>
              <td class="text-center py-2"><span class="text-green-500">✓</span></td>
            </tr>
            <tr>
              <td class="py-2 text-sm text-gray-900">Business settings</td>
              <td class="text-center py-2"><span class="text-red-500">✗</span></td>
              <td class="text-center py-2"><span class="text-red-500">✗</span></td>
              <td class="text-center py-2"><span class="text-green-500">✓</span></td>
              <td class="text-center py-2"><span class="text-green-500">✓</span></td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  </div>
</div>
```

## Acceptance Criteria
- [ ] Different roles have appropriate permission levels
- [ ] Staff can only access features they're authorized for
- [ ] Role changes are properly applied and logged
- [ ] Permission matrix clearly shows what each role can do
- [ ] Unauthorized access attempts are blocked
- [ ] UI adapts based on user permissions

## Testing Requirements
- Authorization service tests for all permission combinations
- Controller tests verifying access control
- Helper method tests for permission checks
- System tests for role-based UI behavior
