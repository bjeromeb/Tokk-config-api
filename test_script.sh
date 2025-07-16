#!/bin/bash

# API Testing Script
# Tests the configuration API endpoints locally or on deployed environment

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default configuration
BASE_URL="http://localhost:3000"
API_KEY="ios-secure-key-replace-this-12345"
APP_ID="com.yourcompany.testapp"
APP_VERSION="1.0.0"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--url)
            BASE_URL="$2"
            shift 2
            ;;
        -k|--key)
            API_KEY="$2"
            shift 2
            ;;
        -a|--app-id)
            APP_ID="$2"
            shift 2
            ;;
        -v|--version)
            APP_VERSION="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -u, --url URL        Base URL (default: http://localhost:3000)"
            echo "  -k, --key KEY        API Key (default: ios-secure-key-replace-this-12345)"
            echo "  -a, --app-id ID      App ID (default: com.yourcompany.testapp)"
            echo "  -v, --version VER    App Version (default: 1.0.0)"
            echo "  -h, --help           Show this help"
            echo ""
            echo "Examples:"
            echo "  $0                                           # Test local server"
            echo "  $0 -u https://your-app.amplifyapp.com/api   # Test deployed API"
            echo "  $0 -k your-production-key                   # Use different API key"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}🧪 Testing Configuration API${NC}"
echo "============================="
echo "Base URL: $BASE_URL"
echo "API Key: ${API_KEY:0:10}..."
echo "App ID: $APP_ID"
echo "App Version: $APP_VERSION"
echo ""

# Function to make HTTP request with common headers
make_request() {
    local method=$1
    local endpoint=$2
    local api_key_override=$3
    local expected_code=$4
    
    local actual_api_key="${api_key_override:-$API_KEY}"
    
    response=$(curl -s -w "\n%{http_code}" \
        -X "$method" \
        -H "X-API-Key: $actual_api_key" \
        -H "X-App-Id: $APP_ID" \
        -H "X-App-Version: $APP_VERSION" \
        -H "X-Platform: ios" \
        -H "Content-Type: application/json" \
        -H "User-Agent: ConfigAPI-Test/1.0" \
        "$BASE_URL$endpoint")
    
    body=$(echo "$response" | head -n -1)
    code=$(echo "$response" | tail -n 1)
    
    if [ -n "$expected_code" ] && [ "$code" -eq "$expected_code" ]; then
        return 0
    elif [ -z "$expected_code" ] && [ "$code" -eq 200 ]; then
        return 0
    else
        return 1
    fi
}

# Check if jq is available for JSON formatting
if command -v jq &> /dev/null; then
    HAS_JQ=true
else
    HAS_JQ=false
    echo -e "${YELLOW}⚠️  jq not found. JSON responses will not be formatted.${NC}"
    echo ""
fi

# Function to format JSON if jq is available
format_json() {
    if [ "$HAS_JQ" = true ]; then
        echo "$1" | jq .
    else
        echo "$1"
    fi
}

# Test results tracking
TESTS_PASSED=0
TESTS_FAILED=0
TOTAL_TESTS=0

# Function to record test result
record_test() {
    local test_name=$1
    local passed=$2
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if [ "$passed" = true ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✅ $test_name passed${NC}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}❌ $test_name failed${NC}"
    fi
}

# Test 1: Health Check
echo -e "${BLUE}Test 1: Health Check${NC}"
echo "Endpoint: GET $BASE_URL/health"
echo "Expected: 200 OK with health status"

health_response=$(curl -s -w "\n%{http_code}" "$BASE_URL/health" 2>/dev/null)
if [ $? -eq 0 ]; then
    health_body=$(echo "$health_response" | head -n -1)
    health_code=$(echo "$health_response" | tail -n 1)
    
    if [ "$health_code" -eq 200 ]; then
        record_test "Health Check" true
        echo "Response:"
        format_json "$health_body"
    else
        record_test "Health Check" false
        echo "HTTP Code: $health_code"
        echo "Response: $health_body"
    fi
else
    record_test "Health Check" false
    echo "Connection failed. Is the server running?"
fi
echo ""

# Test 2: Configuration Endpoint (Valid API Key)
echo -e "${BLUE}Test 2: Configuration Endpoint (Valid API Key)${NC}"
echo "Endpoint: GET $BASE_URL/api/config"
echo "Expected: 200 OK with configuration data"

if make_request "GET" "/api/config" "" 200; then
    record_test "Valid API Key Authentication" true
    echo "Response preview:"
    if [ "$HAS_JQ" = true ]; then
        echo "$body" | jq '{
            version: .version,
            aws: .aws,
            features: .features,
            metadata: .metadata
        }'
    else
        echo "$body"
    fi
else
    record_test "Valid API Key Authentication" false
    echo "HTTP Code: $code"
    echo "Response: $body"
fi
echo ""

# Test 3: Configuration Endpoint (Invalid API Key)
echo -e "${BLUE}Test 3: Configuration Endpoint (Invalid API Key)${NC}"
echo "Endpoint: GET $BASE_URL/api/config"
echo "Expected: 401 Unauthorized"

if make_request "GET" "/api/config" "invalid-key-12345" 401; then
    record_test "Invalid API Key Rejection" true
    echo "Response:"
    format_json "$body"
else
    record_test "Invalid API Key Rejection" false
    echo "HTTP Code: $code (expected 401)"
    echo "Response: $body"
fi
echo ""

# Test 4: Configuration Endpoint (No API Key)
echo -e "${BLUE}Test 4: Configuration Endpoint (No API Key)${NC}"
echo "Endpoint: GET $BASE_URL/api/config"
echo "Expected: 401 Unauthorized"

no_key_response=$(curl -s -w "\n%{http_code}" \
    -H "X-App-Id: $APP_ID" \
    -H "X-App-Version: $APP_VERSION" \
    "$BASE_URL/api/config" 2>/dev/null)

if [ $? -eq 0 ]; then
    no_key_body=$(echo "$no_key_response" | head -n -1)
    no_key_code=$(echo "$no_key_response" | tail -n 1)
    
    if [ "$no_key_code" -eq 401 ]; then
        record_test "Missing API Key Rejection" true
        echo "Response:"
        format_json "$no_key_body"
    else
        record_test "Missing API Key Rejection" false
        echo "HTTP Code: $no_key_code (expected 401)"
        echo "Response: $no_key_body"
    fi
else
    record_test "Missing API Key Rejection" false
    echo "Connection failed"
fi
echo ""

# Test 5: Configuration Version Endpoint
echo -e "${BLUE}Test 5: Configuration Version Endpoint${NC}"
echo "Endpoint: GET $BASE_URL/api/config/version"
echo "Expected: 200 OK with version info"

if make_request "GET" "/api/config/version" "" 200; then
    record_test "Configuration Version Endpoint" true
    echo "Response:"
    format_json "$body"
else
    record_test "Configuration Version Endpoint" false
    echo "HTTP Code: $code"
    echo "Response: $body"
fi
echo ""

# Test 6: Non-existent Endpoint
echo -e "${BLUE}Test 6: Non-existent Endpoint${NC}"
echo "Endpoint: GET $BASE_URL/api/nonexistent"
echo "Expected: 404 Not Found"

if make_request "GET" "/api/nonexistent" "" 404; then
    record_test "404 Error Handling" true
    echo "Response:"
    format_json "$body"
else
    record_test "404 Error Handling" false
    echo "HTTP Code: $code (expected 404)"
    echo "Response: $body"
fi
echo ""

# Test 7: Rate Limiting (Optional - only if server is running locally)
if [[ "$BASE_URL" == *"localhost"* ]] || [[ "$BASE_URL" == *"127.0.0.1"* ]]; then
    echo -e "${BLUE}Test 7: Rate Limiting (Stress Test)${NC}"
    echo "Sending 10 rapid requests to test rate limiting..."
    
    rate_limit_triggered=false
    
    for i in {1..10}; do
        if make_request "GET" "/api/config" "" ""; then
            if [ "$code" -eq 429 ]; then
                rate_limit_triggered=true
                break
            fi
        fi
        sleep 0.1
    done
    
    if [ "$rate_limit_triggered" = true ]; then
        record_test "Rate Limiting" true
        echo "Rate limiting triggered as expected (HTTP 429)"
        echo "Response:"
        format_json "$body"
    else
        echo -e "${YELLOW}⚠️  Rate limiting not triggered (this may be normal for low request volumes)${NC}"
        # Don't count this as pass or fail since it depends on configuration
    fi
    echo ""
fi

# Test 8: Response Headers
echo -e "${BLUE}Test 8: Security Headers${NC}"
echo "Checking for security headers..."

headers_response=$(curl -s -I \
    -H "X-API-Key: $API_KEY" \
    "$BASE_URL/api/config" 2>/dev/null)

if [ $? -eq 0 ]; then
    has_security_headers=true
    
    # Check for important security headers
    if echo "$headers_response" | grep -qi "x-content-type-options"; then
        echo -e "${GREEN}✅ X-Content-Type-Options header present${NC}"
    else
        echo -e "${YELLOW}⚠️  X-Content-Type-Options header missing${NC}"
        has_security_headers=false
    fi
    
    if echo "$headers_response" | grep -qi "x-frame-options"; then
        echo -e "${GREEN}✅ X-Frame-Options header present${NC}"
    else
        echo -e "${YELLOW}⚠️  X-Frame-Options header missing${NC}"
        has_security_headers=false
    fi
    
    if echo "$headers_response" | grep -qi "strict-transport-security"; then
        echo -e "${GREEN}✅ Strict-Transport-Security header present${NC}"
    else
        echo -e "${YELLOW}⚠️  Strict-Transport-Security header missing (normal for HTTP)${NC}"
    fi
    
    record_test "Security Headers" $has_security_headers
else
    record_test "Security Headers" false
    echo "Failed to fetch headers"
fi
echo ""

# Test Summary
echo -e "${BLUE}📊 Test Summary${NC}"
echo "==============="
echo "Total Tests: $TOTAL_TESTS"
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}🎉 All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}❌ Some tests failed. Please check the configuration and try again.${NC}"
    exit 1
fi