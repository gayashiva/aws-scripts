# Unified IoT Monitoring System

A comprehensive AWS Lambda-based monitoring system that combines data reporting, offline site monitoring, and error tracking for IoT devices into a single, efficient solution.

## Features

### 🔄 **Unified Operations**
- **Data Reporting**: Query and format site data from DynamoDB tables
- **Offline Monitoring**: Check sites that haven't reported within specified timeframes
- **Error Tracking**: Monitor and summarize errors from IoT devices

### 🏢 **Multi-Site Support**
- Air irrigation sites: Sakti, Stakmo, Surya
- Drip irrigation sites: Skuast
- Easily configurable site management
- Support for both active and inactive sites

### 📧 **Smart Email Notifications**
- HTML and plain text email formats
- Conditional sending (only sends when issues exist)
- Multiple recipient support
- Customizable subjects and content

### ⏰ **Automated Scheduling**
- Offline monitoring at 6 PM IST daily
- Error summary reports at 5 PM IST daily
- EventBridge integration for reliable scheduling

### 🛠️ **Improved Architecture**
- Object-oriented design with clear separation of concerns
- Centralized configuration management
- Better error handling and logging
- Type hints for better code maintainability

## Quick Start

### Prerequisites
- AWS CLI installed and configured
- Python 3.9+ (for local development)
- Bash shell (for deployment scripts)
- jq (for JSON parsing in test scripts)

### 1. Clone/Download Files
Ensure you have all the required files:
```
├── unified_monitoring_lambda.py
├── lambda-execution-policy.json
├── lambda-trust-policy.json
├── deploy.sh
├── test_lambda.sh
├── requirements.txt
└── README.md
```

### 2. Configure Settings
Edit the configuration in `unified_monitoring_lambda.py`:

```python
# Update site configurations
SITE_CONFIG = {
    'YourSite': {'name': 'Your Site Name', 'type': 'air', 'active': True},
    # Add or modify sites as needed
}

# Update email sender
SENDER_EMAIL = "your-verified-ses-email@domain.com"
```

### 3. Deploy
Make the deployment script executable and run it:
```bash
chmod +x deploy.sh
./deploy.sh
```

The script will:
- Create IAM role and policies
- Package and deploy the Lambda function
- Optionally create EventBridge schedules
- Run basic tests

### 4. Test the Deployment
```bash
chmod +x test_lambda.sh
# Update email in test script first
./test_lambda.sh
```

## Usage

### Manual Invocation Examples

#### Data Report - All Sites
```bash
aws lambda invoke --function-name iot-unified-monitoring \
  --payload '{
    "operation": "data_report",
    "queryType": "all",
    "count": 5,
    "email": ["admin@yourcompany.com"],
    "subject": "Daily Site Data Report"
  }' response.json
```

#### Data Report - Single Site
```bash
aws lambda invoke --function-name iot-unified-monitoring \
  --payload '{
    "operation": "data_report",
    "queryType": "single",
    "siteName": "Sakti",
    "count": 10,
    "email": ["admin@yourcompany.com"]
  }' response.json
```

#### Offline Site Check
```bash
aws lambda invoke --function-name iot-unified-monitoring \
  --payload '{
    "operation": "offline_check",
    "max_hours": 2,
    "email": ["alerts@yourcompany.com"]
  }' response.json
```

#### Error Summary
```bash
aws lambda invoke --function-name iot-unified-monitoring \
  --payload '{
    "operation": "error_summary",
    "hours": 24,
    "limit": 5,
    "email": ["admin@yourcompany.com"]
  }' response.json
```

## Event Payload Reference

### Common Parameters
- `operation` (required): `"data_report"`, `"offline_check"`, or `"error_summary"`
- `email` (required): String or array of email addresses

### Data Report Parameters
- `queryType`: `"single"` or `"all"`
- `siteName`: Site code (required if `queryType` is `"single"`)
- `count`: Number of records to retrieve (default: 5)
- `subject`: Custom email subject (optional)

### Offline Check Parameters
- `max_hours`: Hours threshold for offline detection (default: 2)

### Error Summary Parameters
- `hours`: Hours to look back for errors (default: 24)
- `limit`: Maximum errors per site to report (default: 5)

## Scheduled Operations

The system can be configured with EventBridge rules for automatic execution:

- **Offline Monitoring**: Daily at 6 PM IST (12:30 PM UTC)
- **Error Summary**: Daily at 5 PM IST (11:30 AM UTC)

### Updating Scheduled Email Recipients
```bash
# Update the EventBridge rule target
aws events put-targets --rule iot-offline-monitor-schedule \
  --targets "Id"="1","Arn"="arn:aws:lambda:REGION:ACCOUNT:function:iot-unified-monitoring","Input"='{"operation":"offline_check","email":["new-admin@company.com"]}'
```

## Customization

### Adding New Sites
1. Update `SITE_CONFIG` in `unified_monitoring_lambda.py`
2. Ensure DynamoDB tables exist for the site data
3. Update and redeploy:
```bash
./deploy.sh update
```

### Adding New Operations
1. Create a new handler function (e.g., `handle_new_operation`)
2. Add the operation to the router in `lambda_handler`
3. Update documentation and tests

### Modifying Email Templates
Email formatting is handled by the `EmailService` class. Customize the HTML and text templates in:
- `format_offline_alert_email()`
- `format_error_summary_email()`

## Monitoring and Troubleshooting

### CloudWatch Logs
View function logs:
```bash
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/iot-unified-monitoring
aws logs tail /aws/lambda/iot-unified-monitoring
```

### Common Issues

**1. Email Not Sending**
- Verify SES email is verified
- Check IAM permissions for SES
- Ensure sender email in configuration matches SES

**2. DynamoDB Access Issues**
- Verify table names in `TABLE_CONFIG`
- Check IAM permissions for DynamoDB
- Ensure tables exist in the correct region

**3. Function Timeout**
- Increase timeout in deployment script
- Check for slow DynamoDB queries
- Monitor memory usage

**4. Scheduled Rules Not Working**
- Verify EventBridge rule is enabled
- Check rule targets configuration
- Verify Lambda permissions for EventBridge

## Security Considerations

- IAM roles follow least-privilege principle
- No hardcoded credentials in code
- Email addresses validated before sending
- DynamoDB access limited to specific tables

## Cost Optimization

- Function runs only when needed
- Conditional email sending reduces SES costs
- Efficient DynamoDB queries with limits
- Appropriate memory allocation (256MB)

## Migration from Old Functions

This unified function replaces three separate Lambda functions:
1. Data querying/reporting function
2. Offline site monitoring function  
3. Error monitoring function

**Migration Steps:**
1. Deploy the new unified function
2. Update any EventBridge rules to use the new function
3. Test all operations thoroughly
4. Remove the old functions once confirmed working
5. Clean up old IAM roles and policies

## Support

For issues or questions:
1. Check CloudWatch logs for error details
2. Run test scripts to verify functionality
3. Review AWS service quotas and limits
4. Ensure all prerequisites are met

## Version History

- **v2.0** - Unified monitoring system with improved architecture
- **v1.x** - Original separate functions (deprecated)

## License

Internal use only - Please maintain security of AWS credentials and email addresses.
