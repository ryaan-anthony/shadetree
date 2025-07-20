# Implementation Task: Service Import/Export

## Overview
Create a system for importing and exporting service definitions, enabling businesses to migrate services and share configurations across locations.

## Technical Design

### Models
```ruby
class ServiceExport < ApplicationRecord
  belongs_to :business
  belongs_to :created_by, class_name: 'User'
  has_one_attached :export_file
  
  validates :export_type, inclusion: { in: %w[full partial template] }
  validates :format, inclusion: { in: %w[json csv excel] }
  
  # Store export configuration
  store :export_config, accessors: [
    :included_services,
    :include_variations,
    :include_resources,
    :include_pricing
  ], coder: JSON
end

class ServiceImport < ApplicationRecord
  belongs_to :business
  belongs_to :imported_by, class_name: 'User'
  has_one_attached :import_file
  
  validates :import_type, inclusion: { in: %w[new update merge] }
  
  # Store import configuration and results
  store :import_config, coder: JSON
  store :validation_results, coder: JSON
  store :import_results, coder: JSON
end

class ServiceMapping < ApplicationRecord
  belongs_to :service_import
  belongs_to :source_service, class_name: 'Service', optional: true
  belongs_to :target_service, class_name: 'Service', optional: true
  
  validates :mapping_type, inclusion: { in: %w[exact fuzzy manual] }
  
  # Store mapping details
  store :mapping_details, coder: JSON
end
```

### Service Objects
```ruby
class ServiceExportService
  def self.generate_export(business, config)
    ServiceExport.transaction do
      # Generate export file
      # Include related data
      # Apply transformations
      # Handle attachments
    end
  end
  
  def self.format_export_data(services, format)
    # Transform service data
    # Apply format-specific rules
    # Handle relationships
    # Generate output
  end
end

class ServiceImportService
  def self.validate_import(business, file)
    # Parse import file
    # Validate structure
    # Check data integrity
    # Return validation results
  end
  
  def self.process_import(import_id)
    ServiceImport.transaction do
      # Process import file
      # Handle mappings
      # Create/update services
      # Track results
    end
  end
end

class ServiceMappingService
  def self.auto_map_services(import)
    # Analyze source services
    # Find matching targets
    # Generate mappings
    # Return conflicts
  end
  
  def self.resolve_conflicts(import, resolutions)
    # Apply manual resolutions
    # Update mappings
    # Validate changes
    # Return results
  end
end
```

### Background Jobs
```ruby
class ServiceExportGenerationJob < ApplicationJob
  def perform(export_id)
    # Generate export file
    # Process attachments
    # Create archive
    # Send notification
  end
end

class ServiceImportProcessingJob < ApplicationJob
  def perform(import_id)
    # Process import chunks
    # Handle mappings
    # Create services
    # Send notifications
  end
end
```

## File Formats
1. JSON Export Format
```json
{
  "metadata": {
    "version": "1.0",
    "business_id": "uuid",
    "exported_at": "datetime"
  },
  "services": [
    {
      "key": "string",
      "name": "string",
      "category": "string",
      "variations": [],
      "requirements": [],
      "resources": []
    }
  ]
}
```

2. CSV Export Format
```csv
key,name,category,duration,price,description
service1,Service 1,Category 1,60,100.00,"Description 1"
service2,Service 2,Category 2,30,50.00,"Description 2"
```

## Testing Strategy
1. Model Tests
   - Export generation
   - Import validation
   - Mapping logic
   - File handling

2. Service Tests
   - Export processing
   - Import handling
   - Conflict resolution
   - Data transformation

3. Integration Tests
   - Complete export flow
   - Import process
   - File format handling
   - Error recovery

## Security Considerations
- File validation
- Data sanitization
- Access control
- Rate limiting
- Size restrictions
- Audit logging

## Estimated Hours: 20

## Dependencies
- Core Service Models
- File Storage System
- Background Jobs
