# Feature: Smart Industry Defaults

## Overview
Implement industry-specific default values and field presets for quote request forms that help streamline the information collection process based on the business type, making form completion easier for customers while ensuring businesses receive relevant data.

## Goals
- Provide intelligent defaults based on industry type (e.g., room sizes for cleaners, square footage for landscapers)
- Streamline quote request forms with industry-appropriate fields and terminology
- Reduce form abandonment by simplifying data entry
- Improve quote accuracy with standardized measurement collection
- Enable businesses to customize industry defaults to their specific needs

## User Stories
1. **As a business owner**, I want my quote form to use terminology specific to my industry so customers understand what information to provide.
2. **As a business owner**, I want common measurements in my industry to be pre-populated so customers don't have to guess what units to use.
3. **As a customer**, I want to understand what information is needed without industry expertise.
4. **As a customer**, I want helpful examples of measurements or specifications needed for accurate quotes.
5. **As a business owner**, I want to customize industry defaults to match my specific business needs.

## Technical Requirements

### Industry Template System
- Pre-built form templates for top 25 service industries
- Industry-specific field sets with appropriate units
- Common service categories per industry
- Default measurement units appropriate to each service
- Terminology guide per industry

### Smart Defaults
- Reasonable value ranges for numerical inputs
- Geographical location-based defaults (e.g., property sizes)
- Seasonal service defaults based on current date
- Format examples for specialized measurements
- Default options for common choices in each industry

### Customization Layer
- Template customization for business owners
- Ability to modify default values
- Option to save custom templates
- A/B testing capabilities for form variations
- Analytics on field completion rates

### Customer Assistance
- Tooltips explaining industry terms
- Visual measurement guides
- Auto-conversion between measurement units
- Smart suggestions based on partial input
- Contextual help for complex fields

## User Flows

### Business Owner Template Selection Flow
1. Select business industry during onboarding
2. Receive recommended form template
3. Review and customize default fields
4. Adjust default values if needed
5. Preview form with industry defaults
6. Publish customized form

### Customer Form Completion Flow with Smart Defaults
1. Access quote request form
2. View industry-appropriate fields
3. See helpful default values and examples
4. Modify pre-populated values as needed
5. Receive guidance on industry-specific inputs
6. Complete form with minimal friction

## Success Criteria
- 25% reduction in form abandonment rate
- 30% decrease in time to complete quote requests
- 50% reduction in follow-up questions for measurements/specifications
- >80% of form submissions contain complete, usable data
- Positive customer feedback on form clarity (>4/5)

## Dependencies
- Industry knowledge base for default values
- Geolocation services for regional defaults
- Form analytics system to measure improvements

## Implementation Notes
- Create a database of industry defaults with regular updates
- Use content management system for industry terminology
- Implement progressive disclosure for complex measurement fields
- Consider AI assistance for suggesting values based on partial inputs
- Use A/B testing to validate which defaults work best
- Provide migration path for existing forms to adopt smart defaults
- Implement analytics to track which defaults get changed most often
