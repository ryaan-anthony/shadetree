# Epic: Business Profile Management

## Overview
Enable users to create and configure business entities with essential profile information, branding, and operational settings. Start with single-business setup for MVP, with multi-business capability planned for Growth Phase.

## Goals
- Enable quick business creation and onboarding (< 10 minutes)
- Support essential business configuration
- Provide basic branding and customization
- Prepare foundation for multi-business operations
- Ensure proper data isolation and security

## Success Metrics
- Business setup completion time < 10 minutes
- Business profile completeness rate > 90%
- Cross-business data leakage incidents = 0
- Setup abandonment rate < 15%

## User Stories
- As a new user, I want to create my business profile so I can start using the platform
- As a business owner, I want to configure my business details so customers see professional information
- As a business owner, I want to upload my logo and set brand colors for quotes and communications
- As a user, I want to set my business hours and service areas so customers know when and where I'm available

## Features

### MVP Phase (P0 - Critical Path)
1. [Business Creation & Setup](business-profile/01-business-creation.md) - Initial business creation with guided setup
2. [Business Configuration](business-profile/02-business-configuration.md) - Essential business details and settings
3. [Business Hours & Service Areas](business-profile/03-business-hours-areas.md) - Operating hours and service territories

### Growth Phase (P1 - Early Value)  
4. [Business Branding & Customization](business-profile/04-business-branding.md) - Logo, colors, and branded materials

### Scale Phase (P2 - Advanced Features)
5. [Multi-Business Management](business-profile/05-multi-business-management.md) - Multiple business entities for entrepreneurs

## Technical Architecture

### Core Models
```ruby
# MVP Models
class Business < ApplicationRecord
  belongs_to :owner, class_name: 'User'
  has_many :business_users, dependent: :destroy
  has_many :users, through: :business_users
  has_many :services, dependent: :destroy
  has_many :quotes, dependent: :destroy
  
  validates :name, :email, :phone, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
  
  enum status: { active: 0, inactive: 1, suspended: 2 }
end

class BusinessUser < ApplicationRecord
  belongs_to :business
  belongs_to :user
  
  validates :role, presence: true
  enum role: { owner: 0, admin: 1, staff: 2 }
end
```

### Business Context
- All admin functionality scoped to current business
- Session-based business context for multi-business users
- Role-based access control within each business
- Audit logging for sensitive operations

## Integration Points
- Staff Management (business-scoped teams)
- Service & Pricing (business-specific catalogs)
- Admin Dashboard (business-specific metrics)
- Custom Fields (business-specific field definitions)

## Security Considerations
- Validate business ownership on all operations
- Prevent cross-business data access
- Audit business creation and sensitive changes
- Secure file uploads for branding assets

## MVP Scope Reduction
**Removed from MVP:**
- Complex multi-business switching UI
- Advanced role hierarchies
- Business-to-business relationships
- Third-party business verification
- Advanced workflow customization per business

**Simplified for MVP:**
- Single business creation flow
- Basic role system (owner, admin, staff)
- Essential business information only
- Simple branding (logo upload only)

## Phase Progression
- **MVP**: Single business setup with essential features
- **Growth**: Enhanced branding and basic multi-business
- **Scale**: Advanced multi-business with complex role management
