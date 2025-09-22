#!/bin/bash

# Configuration
FUNCTION_NAME="iot-unified-monitoring"
YOUR_EMAIL="bsurya@acresofice.com" # Change this to your actual email

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

# Function to invoke Lambda and display results
invoke_lambda() {
  local test_name="$1"
  local payload="$2"

  print_status "Testing: $test_name"
  echo "Payload: $payload"

  aws lambda invoke \
    --function-name $FUNCTION_NAME \
    --payload "$payload" \
    --cli-binary-format raw-in-base64-out \
    response.json >/dev/null 2>&1

  if [ $? -eq 0 ]; then
    print_status "Invocation successful"

    # Check the response
    if grep -q '"statusCode": 200' response.json; then
      print_status "✓ Function executed successfully"
      # Extract and display the message
      MESSAGE=$(jq -r '.body | fromjson | .message' response.json 2>/dev/null)
      if [ "$MESSAGE" != "null" ] && [ "$MESSAGE" != "" ]; then
        echo "Result: $MESSAGE"
      fi
    else
      print_error "✗ Function returned an error"
      cat response.json
    fi
  else
    print_error "✗ Failed to invoke function"
  fi

  echo ""
  echo "-----------------------------------"
  echo ""
}

# Main test function
run_tests() {
  print_status "Starting Lambda function tests..."

  if [ "$YOUR_EMAIL" = "your-email@example.com" ]; then
    print_warning "Please update YOUR_EMAIL variable in this script with your actual email address"
    read -p "Enter your email address for testing: " YOUR_EMAIL
  fi

  # Test 1: Data report for all sites
  invoke_lambda "Data Report - All Sites" '{
        "operation": "data_report",
        "queryType": "all",
        "count": 3,
        "email": ["'$YOUR_EMAIL'"],
        "subject": "Test Data Report - All Sites"
    }'

  # Test 2: Data report for single site
  invoke_lambda "Data Report - Single Site (Sakti)" '{
        "operation": "data_report",
        "queryType": "single",
        "siteName": "Sakti",
        "count": 5,
        "email": ["'$YOUR_EMAIL'"],
        "subject": "Test Data Report - Sakti Site"
    }'

  # Test 3: Offline check
  invoke_lambda "Offline Site Check" '{
        "operation": "offline_check",
        "max_hours": 2,
        "email": ["'$YOUR_EMAIL'"]
    }'

  # Test 4: Error summary
  invoke_lambda "Error Summary Report" '{
        "operation": "error_summary",
        "hours": 24,
        "limit": 5,
        "email": ["'$YOUR_EMAIL'"]
    }'

  # Test 5: Invalid operation (should fail)
  invoke_lambda "Invalid Operation (Expected to Fail)" '{
        "operation": "invalid_op",
        "email": ["'$YOUR_EMAIL'"]
    }'

  print_status "All tests completed!"
  print_status "Check your email for any reports that were sent"
  print_status "Full responses are in response.json"
}

# Show usage
show_usage() {
  echo "Usage: $0 [test_type]"
  echo ""
  echo "Test types:"
  echo "  all             - Run all tests (default)"
  echo "  data-report     - Test data reporting"
  echo "  offline-check   - Test offline monitoring"
  echo "  error-summary   - Test error summary"
  echo "  single-site     - Test single site data report"
  echo ""
  echo "Example:"
  echo "  $0 data-report"
  echo "  $0 all"
}

# Handle specific test types
case "$1" in
"data-report")
  invoke_lambda "Data Report Test" '{
            "operation": "data_report",
            "queryType": "all",
            "count": 3,
            "email": ["'$YOUR_EMAIL'"]
        }'
  ;;
"offline-check")
  invoke_lambda "Offline Check Test" '{
            "operation": "offline_check",
            "max_hours": 2,
            "email": ["'$YOUR_EMAIL'"]
        }'
  ;;
"error-summary")
  invoke_lambda "Error Summary Test" '{
            "operation": "error_summary",
            "hours": 24,
            "limit": 5,
            "email": ["'$YOUR_EMAIL'"]
        }'
  ;;
"single-site")
  invoke_lambda "Single Site Test" '{
            "operation": "data_report",
            "queryType": "single",
            "siteName": "Sakti",
            "count": 5,
            "email": ["'$YOUR_EMAIL'"]
        }'
  ;;
"help" | "-h" | "--help")
  show_usage
  ;;
"all" | "")
  run_tests
  ;;
*)
  print_error "Unknown test type: $1"
  show_usage
  exit 1
  ;;
esac
