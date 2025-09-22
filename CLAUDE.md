# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview
This is a Unified IoT Monitoring System for AWS Lambda that combines data reporting, offline site monitoring, and error tracking for IoT devices. The system monitors irrigation sites (both air and drip types) and sends email alerts via AWS SES.

## Common Commands

### Deployment and Management
```bash
# Full deployment of Lambda function and infrastructure
./deploy.sh

# Update existing function code only
./deploy.sh update
# or
./manage.sh update

# Check function status and configuration
./manage.sh status

# View CloudWatch logs
./manage.sh logs
./manage.sh logs --tail  # Follow logs in real-time
```

### Testing
```bash
# Run all test cases
./test_lambda.sh
# or
./manage.sh test

# Test specific operations
./test_lambda.sh data-report
./test_lambda.sh offline-check
./test_lambda.sh error-summary
./test_lambda.sh single-site
```

### Function Management
```bash
# Interactive invocation wizard
./manage.sh invoke

# Manage EventBridge schedules (enable/disable/configure)
./manage.sh schedule

# Show current configuration
./manage.sh config

# Remove function and all resources
./manage.sh cleanup
```

## Architecture

### Core Components
- **monitor.py**: Main Lambda function containing all monitoring logic
  - `MonitoringSystem` class: Handles DynamoDB operations and site queries
  - `EmailService` class: Manages email formatting and sending via SES
  - Operation handlers: `handle_data_report()`, `handle_offline_check()`, `handle_error_summary()`

### AWS Services Integration
- **DynamoDB Tables**:
  - `AIRTable`: Stores air irrigation site data
  - `DripTable`: Stores drip irrigation site data
  - `AIRErrors`: Error logs from IoT devices
- **SES**: Email notifications (sender: aws@acresofice.com)
- **EventBridge**: Scheduled triggers for automated monitoring
  - Morning Data Report: 7:30 AM IST (2:00 AM UTC) → team@acresofice.com
  - Evening Offline Check: 5:00 PM IST (11:30 AM UTC) → bsurya@acresofice.com, jnidhin@acresofice.com
  - Evening Error Summary: 5:02 PM IST (11:32 AM UTC) → bsurya@acresofice.com, jnidhin@acresofice.com

### Site Configuration
Sites are managed via `SITE_CONFIG` dictionary in monitor.py:
- Active sites: Sakti, Stakmo, Skuast, Surya, Ayee
- Each site has: name, type (air/drip), active status

## Lambda Event Payload Structure
```json
{
  "operation": "data_report|offline_check|error_summary",
  "email": ["recipient@example.com"],
  // Additional parameters per operation type
}
```

### Operation-specific Parameters
- **data_report**: `queryType` (all/single), `siteName` (if single), `count`, `subject`
- **offline_check**: `max_hours` (default: 2)
- **error_summary**: `hours` (default: 24), `limit` (default: 5)

## Important Notes
- Always update `SENDER_EMAIL` in monitor.py before deployment
- Email recipients in test scripts default to "your-email@example.com" - update before testing
- Lambda timeout is set to 300 seconds, memory to 256MB
- EventBridge schedules run at:
  - Offline monitoring: 6 PM IST (12:30 PM UTC)
  - Error summary: 5 PM IST (11:30 AM UTC)