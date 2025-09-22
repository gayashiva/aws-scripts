#!/bin/bash

# Management script for IoT Unified Monitoring Lambda
FUNCTION_NAME="iot-unified-monitoring"
ROLE_NAME="iot-monitoring-lambda-role"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_header() { echo -e "${BLUE}[HEADER]${NC} $1"; }

show_usage() {
  echo "IoT Unified Monitoring Management Script"
  echo ""
  echo "Usage: $0 [command]"
  echo ""
  echo "Commands:"
  echo "  deploy        - Deploy the Lambda function"
  echo "  update        - Update existing function code"
  echo "  status        - Show function status and configuration"
  echo "  test          - Run tests on the deployed function"
  echo "  logs          - Show recent CloudWatch logs"
  echo "  schedule      - Manage EventBridge schedules"
  echo "  cleanup       - Remove the function and associated resources"
  echo "  config        - Show current configuration"
  echo "  invoke        - Interactive function invocation"
  echo ""
  echo "Examples:"
  echo "  $0 deploy"
  echo "  $0 status"
  echo "  $0 logs --tail"
}

deploy_function() {
  print_header "Deploying IoT Unified Monitoring Function"
  if [ -f "./deploy.sh" ]; then
    chmod +x ./deploy.sh
    ./deploy.sh
  else
    print_error "deploy.sh not found"
    exit 1
  fi
}

update_function() {
  print_header "Updating Function Code"
  if [ -f "./deploy.sh" ]; then
    chmod +x ./deploy.sh
    ./deploy.sh update
  else
    print_error "deploy.sh not found"
    exit 1
  fi
}

show_status() {
  print_header "Lambda Function Status"

  # Check if function exists
  if aws lambda get-function --function-name $FUNCTION_NAME >/dev/null 2>&1; then
    print_status "✓ Function exists: $FUNCTION_NAME"

    # Get function details
    FUNCTION_INFO=$(aws lambda get-function --function-name $FUNCTION_NAME)

    RUNTIME=$(echo "$FUNCTION_INFO" | jq -r '.Configuration.Runtime')
    MEMORY=$(echo "$FUNCTION_INFO" | jq -r '.Configuration.MemorySize')
    TIMEOUT=$(echo "$FUNCTION_INFO" | jq -r '.Configuration.Timeout')
    LAST_MODIFIED=$(echo "$FUNCTION_INFO" | jq -r '.Configuration.LastModified')

    echo "  Runtime: $RUNTIME"
    echo "  Memory: ${MEMORY}MB"
    echo "  Timeout: ${TIMEOUT}s"
    echo "  Last Modified: $LAST_MODIFIED"

    # Check IAM role
    ROLE_ARN=$(echo "$FUNCTION_INFO" | jq -r '.Configuration.Role')
    print_status "✓ IAM Role: $ROLE_ARN"

    # Check environment variables
    ENV_VARS=$(echo "$FUNCTION_INFO" | jq -r '.Configuration.Environment.Variables // empty')
    if [ "$ENV_VARS" != "" ]; then
      print_status "Environment Variables:"
      echo "$ENV_VARS" | jq .
    fi

  else
    print_error "✗ Function does not exist: $FUNCTION_NAME"
  fi

  # Check EventBridge rules
  print_header "EventBridge Rules"

  OFFLINE_RULE="iot-offline-monitor-schedule"
  ERROR_RULE="iot-error-summary-schedule"

  if aws events describe-rule --name $OFFLINE_RULE >/dev/null 2>&1; then
    RULE_STATE=$(aws events describe-rule --name $OFFLINE_RULE --query 'State' --output text)
    print_status "✓ Offline Monitor Rule: $OFFLINE_RULE ($RULE_STATE)"
  else
    print_warning "✗ Offline Monitor Rule not found"
  fi

  if aws events describe-rule --name $ERROR_RULE >/dev/null 2>&1; then
    RULE_STATE=$(aws events describe-rule --name $ERROR_RULE --query 'State' --output text)
    print_status "✓ Error Summary Rule: $ERROR_RULE ($RULE_STATE)"
  else
    print_warning "✗ Error Summary Rule not found"
  fi
}

run_tests() {
  print_header "Running Tests"
  if [ -f "./test_lambda.sh" ]; then
    chmod +x ./test_lambda.sh
    ./test_lambda.sh
  else
    print_error "test_lambda.sh not found"
    exit 1
  fi
}

show_logs() {
  print_header "CloudWatch Logs"

  LOG_GROUP="/aws/lambda/$FUNCTION_NAME"

  if [ "$1" = "--tail" ]; then
    print_status "Tailing logs for $FUNCTION_NAME..."
    aws logs tail $LOG_GROUP --follow
  else
    print_status "Recent logs for $FUNCTION_NAME..."
    aws logs tail $LOG_GROUP --since 1h
  fi
}

manage_schedule() {
  print_header "EventBridge Schedule Management"

  echo "1. Enable offline monitoring schedule"
  echo "2. Disable offline monitoring schedule"
  echo "3. Enable error summary schedule"
  echo "4. Disable error summary schedule"
  echo "5. Show schedule status"
  echo "6. Update schedule email recipients"
  echo "0. Back to main menu"
  echo ""
  read -p "Choose an option: " choice

  case $choice in
  1)
    aws events enable-rule --name iot-offline-monitor-schedule
    print_status "Offline monitoring schedule enabled"
    ;;
  2)
    aws events disable-rule --name iot-offline-monitor-schedule
    print_status "Offline monitoring schedule disabled"
    ;;
  3)
    aws events enable-rule --name iot-error-summary-schedule
    print_status "Error summary schedule enabled"
    ;;
  4)
    aws events disable-rule --name iot-error-summary-schedule
    print_status "Error summary schedule disabled"
    ;;
  5)
    show_status
    ;;
  6)
    update_schedule_recipients
    ;;
  0)
    return
    ;;
  *)
    print_error "Invalid option"
    ;;
  esac
}

update_schedule_recipients() {
  print_status "Current schedule configurations:"

  echo ""
  echo "Offline Monitor Rule targets:"
  aws events list-targets-by-rule --rule iot-offline-monitor-schedule --query 'Targets[0].Input' --output text | jq .

  echo ""
  echo "Error Summary Rule targets:"
  aws events list-targets-by-rule --rule iot-error-summary-schedule --query 'Targets[0].Input' --output text | jq .

  echo ""
  read -p "Enter new email address (or comma-separated list): " NEW_EMAIL

  if [ "$NEW_EMAIL" != "" ]; then
    # Convert comma-separated emails to JSON array
    EMAIL_ARRAY=$(echo "$NEW_EMAIL" | sed 's/,/","/g' | sed 's/^/"/' | sed 's/$/"/')

    # Update offline monitor rule
    aws events put-targets --rule iot-offline-monitor-schedule \
      --targets "Id"="1","Arn"="$(aws lambda get-function --function-name $FUNCTION_NAME --query 'Configuration.FunctionArn' --output text)","Input"="{\"operation\":\"offline_check\",\"email\":[$EMAIL_ARRAY],\"max_hours\":2}"

    # Update error summary rule
    aws events put-targets --rule iot-error-summary-schedule \
      --targets "Id"="1","Arn"="$(aws lambda get-function --function-name $FUNCTION_NAME --query 'Configuration.FunctionArn' --output text)","Input"="{\"operation\":\"error_summary\",\"email\":[$EMAIL_ARRAY],\"hours\":24,\"limit\":5}"

    print_status "Email recipients updated successfully"
  fi
}

cleanup_resources() {
  print_header "Cleanup Resources"
  print_warning "This will remove the Lambda function and associated resources."
  read -p "Are you sure? (y/N): " confirm

  if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
    # Remove EventBridge rules
    print_status "Removing EventBridge rules..."
    aws events remove-targets --rule iot-offline-monitor-schedule --ids "1" 2>/dev/null || true
    aws events remove-targets --rule iot-error-summary-schedule --ids "1" 2>/dev/null || true
    aws events delete-rule --name iot-offline-monitor-schedule 2>/dev/null || true
    aws events delete-rule --name iot-error-summary-schedule 2>/dev/null || true

    # Remove Lambda function
    print_status "Removing Lambda function..."
    aws lambda delete-function --function-name $FUNCTION_NAME 2>/dev/null || true

    # Remove IAM role and policies
    print_status "Removing IAM role..."
    aws iam delete-role-policy --role-name $ROLE_NAME --policy-name IoTMonitoringPolicy 2>/dev/null || true
    aws iam delete-role --role-name $ROLE_NAME 2>/dev/null || true

    print_status "Cleanup completed"
  else
    print_status "Cleanup cancelled"
  fi
}

show_config() {
  print_header "Current Configuration"

  if aws lambda get-function --function-name $FUNCTION_NAME >/dev/null 2>&1; then
    print_status "Function Configuration:"
    aws lambda get-function-configuration --function-name $FUNCTION_NAME | jq .
  else
    print_error "Function not found"
  fi
}

interactive_invoke() {
  print_header "Interactive Function Invocation"

  echo "Select operation:"
  echo "1. Data Report - All Sites"
  echo "2. Data Report - Single Site"
  echo "3. Offline Check"
  echo "4. Error Summary"
  echo "5. Custom Payload"
  echo "0. Cancel"
  echo ""
  read -p "Choose an option: " choice

  read -p "Enter email address: " email

  case $choice in
  1)
    PAYLOAD="{\"operation\":\"data_report\",\"queryType\":\"all\",\"count\":5,\"email\":[\"$email\"]}"
    ;;
  2)
    read -p "Enter site name (Sakti, Stakmo, Skuast, Surya): " site
    PAYLOAD="{\"operation\":\"data_report\",\"queryType\":\"single\",\"siteName\":\"$site\",\"count\":5,\"email\":[\"$email\"]}"
    ;;
  3)
    PAYLOAD="{\"operation\":\"offline_check\",\"max_hours\":2,\"email\":[\"$email\"]}"
    ;;
  4)
    PAYLOAD="{\"operation\":\"error_summary\",\"hours\":24,\"limit\":5,\"email\":[\"$email\"]}"
    ;;
  5)
    read -p "Enter JSON payload: " PAYLOAD
    ;;
  0)
    return
    ;;
  *)
    print_error "Invalid option"
    return
    ;;
  esac

  print_status "Invoking function with payload:"
  echo "$PAYLOAD" | jq .

  aws lambda invoke --function-name $FUNCTION_NAME \
    --payload "$PAYLOAD" \
    --cli-binary-format raw-in-base64-out \
    response.json

  print_status "Response:"
  cat response.json | jq .
}

# Main menu
case "$1" in
"deploy")
  deploy_function
  ;;
"update")
  update_function
  ;;
"status")
  show_status
  ;;
"test")
  run_tests
  ;;
"logs")
  show_logs "$2"
  ;;
"schedule")
  manage_schedule
  ;;
"cleanup")
  cleanup_resources
  ;;
"config")
  show_config
  ;;
"invoke")
  interactive_invoke
  ;;
"help" | "-h" | "--help" | "")
  show_usage
  ;;
*)
  print_error "Unknown command: $1"
  show_usage
  exit 1
  ;;
esac
