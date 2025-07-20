# Implementation Task: Service Search & Discovery

## Overview
Create a powerful search and discovery system that helps customers and staff find relevant services through search, filters, and recommendations.

## Technical Design

### Models
```ruby
class ServiceIndex < ApplicationRecord
  belongs_to :service
  
  # Store search-optimized content
  store :search_content, coder: JSON
  store :keywords, coder: JSON
  store :metadata, coder: JSON
  
  validates :last_indexed_at, presence: true
  
  scope :searchable, -> { joins(:service).where(services: { status: 'active' }) }
end

class SearchableAttribute < ApplicationRecord
  belongs_to :business
  
  validates :attribute_type, inclusion: { in: %w[tag category property custom] }
  validates :indexing_type, inclusion: { in: %w[exact fuzzy phonetic] }
  
  # Store attribute configuration
  store :configuration, coder: JSON
end

class ServiceRecommendation < ApplicationRecord
  belongs_to :business
  belongs_to :source_service, class_name: 'Service'
  belongs_to :recommended_service, class_name: 'Service'
  
  validates :recommendation_type, inclusion: { in: %w[similar complementary popular] }
  validates :score, numericality: { greater_than: 0, less_than_or_equal_to: 1.0 }
  
  # Store recommendation metadata
  store :metadata, coder: JSON
end
```

### Service Objects
```ruby
class ServiceSearchService
  def self.search(business, query, options = {})
    # Parse search query
    # Apply filters
    # Calculate relevance
    # Return results
  end
  
  def self.suggest(query, limit = 5)
    # Generate suggestions
    # Check popularity
    # Apply corrections
    # Return suggestions
  end
end

class ServiceIndexingService
  def self.index_service(service)
    ServiceIndex.transaction do
      # Extract searchable content
      # Generate keywords
      # Update index
      # Calculate scores
    end
  end
  
  def self.update_indexes(business)
    # Reindex all services
    # Update search data
    # Recalculate scores
    # Clear caches
  end
end

class RecommendationService
  def self.generate_recommendations(service)
    # Analyze service attributes
    # Find similar services
    # Calculate scores
    # Store recommendations
  end
  
  def self.get_recommendations(service, type)
    # Load recommendations
    # Apply filters
    # Check availability
    # Return results
  end
end
```

### Background Jobs
```ruby
class ServiceIndexingJob < ApplicationJob
  def perform(service_id)
    # Update search index
    # Generate keywords
    # Calculate scores
    # Update caches
  end
end

class RecommendationGenerationJob < ApplicationJob
  def perform(business_id)
    # Generate recommendations
    # Update scores
    # Clear old recommendations
    # Update caches
  end
end
```

## Search Features
1. Query Processing
   - Keyword extraction
   - Spell correction
   - Synonym expansion
   - Language detection

2. Filtering
   - Category filters
   - Price range
   - Duration
   - Availability
   - Custom attributes

3. Sorting
   - Relevance
   - Price
   - Duration
   - Popularity
   - Availability

## API Endpoints
```ruby
# GET /api/v1/services/search
{
  "query": "string",
  "filters": {},
  "sort": "string",
  "page": number
}

# GET /api/v1/services/:id/recommendations
{
  "type": "similar|complementary|popular",
  "limit": number
}
```

## Testing Strategy
1. Model Tests
   - Index management
   - Recommendation scoring
   - Attribute handling

2. Service Tests
   - Search functionality
   - Index updates
   - Recommendation generation
   - Query processing

3. Integration Tests
   - Complete search flow
   - Recommendation system
   - API functionality
   - Cache behavior

## Security Considerations
- Query sanitization
- Rate limiting
- Cache security
- Access control
- Data privacy

## Estimated Hours: 20

## Dependencies
- Core Service Models
- Search Engine Integration
- Caching System
