# Implementation Task: Calendar Integration

## Overview
Implement external calendar synchronization with popular calendar providers (Google Calendar, Outlook) with real-time updates and conflict resolution.

## Technical Design

### Integration Models
```ruby
class CalendarIntegration < ApplicationRecord
  belongs_to :calendar
  belongs_to :business
  
  validates :provider, inclusion: { in: %w[google outlook] }
  
  # Store provider-specific configuration
  store :provider_config, accessors: [
    :access_token,
    :refresh_token,
    :token_expires_at,
    :sync_frequency,
    :last_sync_at
  ]
  
  encrypts :access_token, :refresh_token
end
```

### OAuth2 Configuration
```ruby
# config/initializers/omniauth.rb
Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2,
    ENV['GOOGLE_CLIENT_ID'],
    ENV['GOOGLE_CLIENT_SECRET'],
    scope: 'calendar'
    
  provider :office365,
    ENV['OUTLOOK_CLIENT_ID'],
    ENV['OUTLOOK_CLIENT_SECRET'],
    scope: 'calendar'
end
```

### Service Objects

```ruby
module CalendarIntegrations
  class GoogleCalendarService
    def initialize(integration)
      @integration = integration
      @client = build_google_client
    end
    
    def sync_events
      fetch_remote_events
      handle_conflicts
      push_local_events
    end
    
    private
    
    def build_google_client
      # Initialize Google Calendar API client
    end
  end
  
  class OutlookCalendarService
    # Similar implementation for Outlook
  end
end
```

## Implementation Steps

### Phase 1: Authentication
1. OAuth2 Setup
   - Configure providers
   - Implement auth flow
   - Token management
   - Refresh handling

2. Integration Management
   - Add/remove integrations
   - Connection status
   - Error handling
   - Rate limiting

### Phase 2: Synchronization
1. Event Sync
   - Two-way sync
   - Conflict detection
   - Resolution strategies
   - Batch processing

2. Webhook Handlers
   - Setup endpoints
   - Verify signatures
   - Process updates
   - Error recovery

### Phase 3: Monitoring
1. Sync Status
   - Success/failure tracking
   - Performance metrics
   - Error reporting
   - Usage analytics

2. Health Checks
   - Connection status
   - Token validity
   - API quotas
   - Response times

## API Integration

### Google Calendar
```ruby
def push_event_to_google(event)
  client = build_google_client
  
  google_event = {
    summary: event.title,
    description: event.description,
    start: { dateTime: event.start_time.iso8601 },
    end: { dateTime: event.end_time.iso8601 }
  }
  
  client.insert_event(calendar_id, google_event)
end
```

### Outlook Calendar
```ruby
def push_event_to_outlook(event)
  client = build_outlook_client
  
  outlook_event = {
    subject: event.title,
    body: { content: event.description },
    start: { dateTime: event.start_time.iso8601 },
    end: { dateTime: event.end_time.iso8601 }
  }
  
  client.create_event(outlook_event)
end
```

## Background Jobs

### Sync Job
```ruby
class ExternalCalendarSyncJob < ApplicationJob
  queue_as :calendar_sync
  
  def perform(integration_id)
    integration = CalendarIntegration.find(integration_id)
    service = integration.build_service
    
    with_error_handling do
      service.sync_events
    end
  end
end
```

### Token Refresh Job
```ruby
class RefreshTokenJob < ApplicationJob
  queue_as :calendar_sync
  
  def perform(integration_id)
    integration = CalendarIntegration.find(integration_id)
    service = integration.build_service
    
    service.refresh_token if token_expired?(integration)
  end
end
```

## Error Handling

### Retry Strategy
1. Immediate retry for temporary failures
2. Exponential backoff for API issues
3. Manual intervention for auth failures
4. Notification for critical errors

### Common Errors
- Token expiration
- Rate limiting
- Network timeout
- API changes
- Data conflicts

## Testing Requirements

### Unit Tests
- Token management
- Event transformation
- Error handling
- Conflict resolution

### Integration Tests
- OAuth flow
- Event sync
- Webhook handling
- Error recovery

## Monitoring

### Metrics
- Sync success rate
- API response time
- Error frequency
- Token health
- Event counts

### Alerts
- Auth failures
- Sync errors
- Rate limits
- API changes
- Critical failures

## Documentation

### API References
- Google Calendar API v3
- Microsoft Graph API
- Webhook specifications
- Authentication flows

### Integration Guide
1. Setup instructions
2. Authentication flow
3. Sync behavior
4. Troubleshooting
5. Best practices
