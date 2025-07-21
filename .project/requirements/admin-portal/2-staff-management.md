# Epic: Staff Management

## Overview
Provide business owners with essential staff management capabilities including invitations, role assignments, and basic scheduling coordination.

## Objectives
- Invite and manage team members
- Assign basic roles and permissions
- Set staff availability schedules
- Track basic staff activity

## Features
1. [Staff Invitations](staff/01-staff-invitations.md)
2. [Role & Permission Management](staff/02-roles-permissions.md)
3. [Staff Availability](staff/03-staff-availability.md)
4. [Staff Activity Tracking](staff/04-activity-tracking.md)

## Technical Requirements
- Email invitation system
- Simple role-based access control
- Weekly availability scheduling
- Basic activity logging

## Acceptance Criteria
- Business owners can invite staff via email
- Staff can accept invitations and set up accounts
- Roles properly restrict access to features
- Availability schedules integrate with appointment booking
- Activity logs show key staff actions

## Dependencies
- User Authentication System
- Email System

## Estimate
- Story Points: 21
- Timeline: 1.5 weeks

## Technical Notes
- Use Devise for user management
- Implement simple role system with enums
- Store availability as weekly recurring schedule
- Use Rails logging for activity tracking
