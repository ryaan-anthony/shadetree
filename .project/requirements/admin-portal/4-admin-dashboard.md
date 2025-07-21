# Epic: Admin Dashboard

## Overview
Create a simple, focused dashboard that provides business owners with essential metrics and quick access to common administrative tasks.

## Objectives
- Display key business metrics at a glance
- Provide quick access to common tasks
- Show recent activity and alerts
- Enable basic reporting capabilities

## Features
1. [Dashboard Overview](admin/01-dashboard-overview.md)
2. [Key Metrics Display](admin/02-key-metrics.md)
3. [Quick Actions Panel](admin/03-quick-actions.md)
4. [Recent Activity Feed](admin/04-recent-activity.md)

## Technical Requirements
- Server-rendered dashboard with minimal JavaScript
- Basic metric calculations
- Simple activity logging
- Responsive design for mobile access

## Acceptance Criteria
- Dashboard loads within 2 seconds
- Key metrics (quotes sent, jobs scheduled, revenue) display accurately
- Quick actions (new quote, schedule appointment) work properly
- Activity feed shows relevant recent events
- Dashboard is fully responsive on mobile devices

## Dependencies
- All other Admin Portal epics
- Core Booking Platform data

## Estimate
- Story Points: 8
- Timeline: 0.5 weeks

## Technical Notes
- Use Rails fragment caching for metrics
- Implement simple counter caches for performance
- Use Hotwire for real-time updates when needed
- Keep JavaScript minimal and progressive
