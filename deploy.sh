#!/bin/bash

# Configuration
FUNCTION_NAME="iot-unified-monitoring"
ROLE_NAME="iot-monitoring-lambda-role"
REGION="us-east-1" # Change this to your preferred region
RUNTIME="python3.12"
TIMEOUT=300
MEMORY_SIZE=256

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if AWS CLI is configured
check_aws_config() {
  print_status "Checking AWS CLI configuration..."
  if ! aws sts get-caller-identity >/dev/null 2>&1; then
    print_error "AWS CLI is not configured or credentials are invalid"
    print_error "Please run 'aws configure' to set up your credentials"
    exit 1
  fi

  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  print_status "Using AWS Account: $ACCOUNT_ID"
}

# Function to create IAM role
create_iam_role() {
  print_status "Creating IAM role: $ROLE_NAME"

  # Check if role already exists
  if aws iam get-role --role-name $ROLE_NAME >/dev/null 2>&1; then
    print_warning "Role $ROLE_NAME already exists, updating..."
  else
    # Create the role
    aws iam create-role \
      --role-name $ROLE_NAME \
      --assume-role-policy-document file://lambda-trust-policy.json \
      --description "Execution role for IoT monitoring Lambda function"

    if [ $? -eq 0 ]; then
      print_status "Role created successfully"
    else
      print_error "Failed to create role"
      exit 1
    fi
  fi

  # Attach the custom policy
  print_status "Attaching custom policy..."
  aws iam put-role-policy \
    --role-name $ROLE_NAME \
    --policy-name IoTMonitoringPolicy \
    --policy-document file://lambda-execution-policy.json

  # Wait for role to be ready
  print_status "Waiting for role to be ready..."
  sleep 10
}

# Function to create deployment package
create_deployment_package() {
  print_status "Creating deployment package..."

  # Remove old package if exists
  rm -f deployment-package.zip

  # Create a clean directory for packaging
  rm -rf package
  mkdir package

  # Copy the Lambda function code
  cp monitor.py package/

  # Install dependencies if requirements.txt exists
  if [ -f "requirements.txt" ]; then
    print_status "Installing Python dependencies..."
    pip install -r requirements.txt -t package/
  fi

  # Create the deployment package
  cd package
  zip -r ../deployment-package.zip .
  cd ..

  # Clean up
  rm -rf package

  if [ -f "deployment-package.zip" ]; then
    print_status "Deployment package created: deployment-package.zip"
  else
    print_error "Failed to create deployment package"
    exit 1
  fi
}

# Function to deploy Lambda function
deploy_lambda() {
  print_status "Deploying Lambda function: $FUNCTION_NAME"

  ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/$ROLE_NAME"

  # Check if function already exists
  if aws lambda get-function --function-name $FUNCTION_NAME >/dev/null 2>&1; then
    print_warning "Function $FUNCTION_NAME already exists, updating code..."

    # Update function code
    aws lambda update-function-code \
      --function-name $FUNCTION_NAME \
      --zip-file fileb://deployment-package.zip

    # Update function configuration
    aws lambda update-function-configuration \
      --function-name $FUNCTION_NAME \
      --runtime $RUNTIME \
      --timeout $TIMEOUT \
      --memory-size $MEMORY_SIZE \
      --environment 'Variables={REGION='$REGION',SENDER_EMAIL=aws@acresofice.com}'
  else
    # Create new function
    aws lambda create-function \
      --function-name $FUNCTION_NAME \
      --runtime $RUNTIME \
      --role $ROLE_ARN \
      --handler monitor.lambda_handler \
      --zip-file fileb://deployment-package.zip \
      --timeout $TIMEOUT \
      --memory-size $MEMORY_SIZE \
      --environment 'Variables={REGION='$REGION',SENDER_EMAIL=aws@acresofice.com}' \
      --description "Unified IoT monitoring system for data reporting, offline monitoring, and error tracking"
  fi

  if [ $? -eq 0 ]; then
    print_status "Lambda function deployed successfully"
  else
    print_error "Failed to deploy Lambda function"
    exit 1
  fi
}

# Function to create EventBridge rules for scheduled execution
create_scheduled_rules() {
  print_status "Creating EventBridge rules for scheduled execution..."

  # Rule for offline monitoring (runs at 6 PM IST = 12:30 PM UTC)
  OFFLINE_RULE_NAME="iot-offline-monitor-schedule"
  print_status "Creating rule: $OFFLINE_RULE_NAME"

  aws events put-rule \
    --name $OFFLINE_RULE_NAME \
    --schedule-expression "cron(30 12 * * ? *)" \
    --description "Runs offline monitoring check at 6 PM IST daily"

  # Add Lambda permission for EventBridge
  aws lambda add-permission \
    --function-name $FUNCTION_NAME \
    --statement-id offline-monitor-permission \
    --action lambda:InvokeFunction \
    --principal events.amazonaws.com \
    --source-arn "arn:aws:events:$REGION:$ACCOUNT_ID:rule/$OFFLINE_RULE_NAME" \
    2>/dev/null || print_warning "Permission may already exist"

  # Add target to rule
  aws events put-targets \
    --rule $OFFLINE_RULE_NAME \
    --targets "Id"="1","Arn"="arn:aws:lambda:$REGION:$ACCOUNT_ID:function:$FUNCTION_NAME","Input"='{"operation":"offline_check","email":["your-email@example.com"],"max_hours":2}'

  # Rule for error summary (runs at 5 PM IST = 11:30 AM UTC)
  ERROR_RULE_NAME="iot-error-summary-schedule"
  print_status "Creating rule: $ERROR_RULE_NAME"

  aws events put-rule \
    --name $ERROR_RULE_NAME \
    --schedule-expression "cron(30 11 * * ? *)" \
    --description "Runs error summary at 5 PM IST daily"

  # Add Lambda permission for EventBridge
  aws lambda add-permission \
    --function-name $FUNCTION_NAME \
    --statement-id error-summary-permission \
    --action lambda:InvokeFunction \
    --principal events.amazonaws.com \
    --source-arn "arn:aws:events:$REGION:$ACCOUNT_ID:rule/$ERROR_RULE_NAME" \
    2>/dev/null || print_warning "Permission may already exist"

  # Add target to rule
  aws events put-targets \
    --rule $ERROR_RULE_NAME \
    --targets "Id"="1","Arn"="arn:aws:lambda:$REGION:$ACCOUNT_ID:function:$FUNCTION_NAME","Input"='{"operation":"error_summary","email":["your-email@example.com"],"hours":24,"limit":5}'

  print_status "EventBridge rules created successfully"
  print_warning "Please update the email addresses in the EventBridge rules to your actual recipients"
}

# Function to test the deployment
test_deployment() {
  print_status "Testing Lambda function deployment..."

  # Test with a simple data report
  TEST_PAYLOAD='{
        "operation": "data_report",
        "queryType": "all",
        "count": 2,
        "email": ["test@example.com"]
    }'

  print_status "Running test invocation..."
  RESULT=$(aws lambda invoke \
    --function-name $FUNCTION_NAME \
    --payload "$TEST_PAYLOAD" \
    --cli-binary-format raw-in-base64-out \
    response.json 2>&1)

  if [ $? -eq 0 ]; then
    print_status "Test invocation successful"
    print_status "Response saved to response.json"

    # Check for errors in the response
    if grep -q '"statusCode": 500' response.json; then
      print_warning "Function returned an error. Check response.json for details"
    else
      print_status "Function executed successfully"
    fi
  else
    print_error "Test invocation failed"
    echo "$RESULT"
  fi
}

# Main execution
main() {
  print_status "Starting deployment of unified IoT monitoring Lambda function..."

  # Check required files
  if [ ! -f "monitor.py" ]; then
    print_error "monitor.py not found"
    exit 1
  fi

  if [ ! -f "lambda-trust-policy.json" ]; then
    print_error "lambda-trust-policy.json not found"
    exit 1
  fi

  if [ ! -f "lambda-execution-policy.json" ]; then
    print_error "lambda-execution-policy.json not found"
    exit 1
  fi

  check_aws_config
  create_iam_role
  create_deployment_package
  deploy_lambda

  # Ask user if they want to create scheduled rules
  read -p "Do you want to create EventBridge rules for scheduled execution? (y/N): " create_rules
  if [ "$create_rules" = "y" ] || [ "$create_rules" = "Y" ]; then
    create_scheduled_rules
  fi

  test_deployment

  print_status "Deployment completed!"
  print_status "Function name: $FUNCTION_NAME"
  print_status "Region: $REGION"

  echo ""
  print_status "To invoke the function manually, use:"
  echo "aws lambda invoke --function-name $FUNCTION_NAME --payload '{\"operation\":\"data_report\",\"queryType\":\"all\",\"email\":[\"your-email@example.com\"]}' response.json"

  echo ""
  print_status "To update the function code later, run:"
  echo "./deploy.sh update"
}

# Handle update mode
if [ "$1" = "update" ]; then
  print_status "Updating existing Lambda function..."
  check_aws_config
  create_deployment_package

  aws lambda update-function-code \
    --function-name $FUNCTION_NAME \
    --zip-file fileb://deployment-package.zip

  print_status "Function updated successfully!"
  exit 0
fi

# Run main deployment
main
