# Implementation Task: Service Catalog UI

## Overview
Create an intuitive and responsive interface for managing and organizing services, with support for different view modes and filtering options.

## Technical Design

### Models
```ruby
class CatalogView < ApplicationRecord
  belongs_to :business
  belongs_to :user, optional: true
  
  validates :view_type, inclusion: { in: %w[list grid calendar category] }
  
  # Store view preferences
  store :preferences, accessors: [
    :default_view,
    :columns_config,
    :sort_order,
    :filters
  ], coder: JSON
end

class CatalogFilter < ApplicationRecord
  belongs_to :business
  belongs_to :user, optional: true
  
  validates :filter_type, inclusion: { in: %w[category duration price availability staff] }
  
  # Store filter configuration
  store :filter_config, coder: JSON
  
  scope :global, -> { where(user_id: nil) }
  scope :active, -> { where(status: 'active') }
end
```

### ViewComponents
```ruby
class ServiceCardComponent < ViewComponent::Base
  def initialize(service:, view_type:)
    @service = service
    @view_type = view_type
  end
  
  private
  
  def render_pricing
    # Format price display
    # Show variations if any
    # Display discounts
  end
  
  def render_availability
    # Check current availability
    # Show next available slot
    # Display capacity
  end
end

class CategoryTreeComponent < ViewComponent::Base
  def initialize(categories:, selected:)
    @categories = categories
    @selected = selected
  end
  
  private
  
  def build_tree(category)
    # Recursively build category tree
    # Handle selection state
    # Show service counts
  end
end
```

### Service Objects
```ruby
class CatalogUIService
  def self.load_catalog_view(business, user, params)
    # Load view preferences
    # Apply filters
    # Sort results
    # Paginate data
  end
  
  def self.update_view_preferences(view, preferences)
    # Update view config
    # Recalculate display
    # Cache results
    # Notify updates
  end
end

class CatalogSearchService
  def self.search_services(business, query, filters = {})
    # Parse search query
    # Apply filters
    # Check availability
    # Return results
  end
end
```

### Hotwire Components
```ruby
# app/javascript/controllers/catalog_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["grid", "filters", "search"]
  
  filter() {
    // Apply filters
    // Update URL
    // Refresh results
  }
  
  search() {
    // Handle search
    // Update results
    // Show loading state
  }
  
  toggleView(event) {
    // Switch view mode
    // Update preferences
    // Refresh display
  }
}
```

## Views
1. Catalog Layout
   - View type toggles
   - Search and filters
   - Category navigation
   - Service grid/list

2. Service Cards
   - Basic info display
   - Quick actions
   - Availability status
   - Pricing preview

## API Endpoints
```ruby
# GET /api/v1/catalog/view
{
  "view_type": "string",
  "filters": {},
  "sort": {},
  "page": number
}

# PATCH /api/v1/catalog/preferences
{
  "view_type": "string",
  "preferences": {}
}
```

## Testing Strategy
1. Component Tests
   - Service card rendering
   - Category tree building
   - Filter functionality
   - View transitions

2. Service Tests
   - View loading
   - Search functionality
   - Filter application
   - Preference management

3. Integration Tests
   - Complete catalog flow
   - Search and filtering
   - View switching
   - API functionality

## Security Considerations
- View access control
- Search input sanitization
- Filter validation
- Rate limiting
- Cache security

## Estimated Hours: 20

## Dependencies
- Core Service Models
- Frontend Framework
- Search System
