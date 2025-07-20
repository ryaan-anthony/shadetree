# Epic: Authentication & User Management

## Overview
Create a streamlined authentication system connecting the marketing site with the core booking platform.

## Objectives
- Implement user registration and login
- Create password recovery system
- Design trial account creation process

## Features
1. [User Authentication System](auth/01-user-registration.md)
2. [Password Management](auth/04-password-management.md)

## Technical Requirements
- Secure authentication with Devise
- Email service integration
- CSRF protection

## Acceptance Criteria
- Registration completes in < 1 minute
- Password reset works reliably
- Security best practices followed

## Dependencies
- Core API

## Estimate
- Story Points: 10
- Timeline: 1 week

## Technical Notes
- Use background jobs for email handling
- Follow OWASP security guidelines
