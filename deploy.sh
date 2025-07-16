#!/bin/bash

# Configuration API Deployment Script for AWS Amplify
# This script helps deploy your Node.js configuration API to AWS Amplify

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Configuration API Deployment Script${NC}"
echo "======================================"

# Check if required tools are installed
check_dependencies() {
    echo -e "${BLUE}Checking dependencies...${NC}"
    
    if ! command -v node &> /dev/null; then
        echo -e "${RED}❌ Node.js is not installed. Please install Node.js 18.x or higher.${NC}"
        exit 1
    fi
    
    if ! command -v npm &> /dev/null; then
        echo -e "${RED}❌ npm is not installed. Please install npm.${NC}"
        exit 1
    fi
    
    if ! command -v git &> /dev/null; then
        echo -e "${RED}❌ Git is not installed. Please install Git.${NC}"
        exit 1
    fi
    
    # Check Node.js version
    node_version=$(node -v | sed 's/v//')
    required_version="18.0.0"
    
    if ! node -pe "process.exit(require('semver').gte('$node_version', '$required_version') ? 0 : 1)" 2>/dev/null; then
        echo -e "${YELLOW}⚠️  Node.js version $node_version detected. Version 18.x or higher is recommended.${NC}"
    fi
    
    echo -e "${GREEN}✅ All dependencies are installed${NC}"
}

# Install project dependencies
install_dependencies() {
    echo -e "${BLUE}Installing project dependencies...${NC}"
    
    if [ ! -f "package.json" ]; then
        echo -e "${RED}❌ package.json not found. Make sure you're in the project root directory.${NC}"
        exit 1
    fi
    
    npm install
    echo -e "${GREEN}✅ Dependencies installed successfully${NC}"
}

# Test the application locally
test_locally() {
    echo -e "${BLUE}Testing application locally...${NC}"
    
    # Check if .env file exists
    if [ ! -f ".env" ]; then
        echo -e "${YELLOW}⚠️  .env file not found. Creating from template...${NC}"
        cp .env.example .env 2>/dev/null || echo -e "${YELLOW}Please create .env file with your configuration${NC}"
    fi
    
    # Start server in background for testing
    echo -e "${BLUE}Starting server for testing...${NC}"
    npm start &
    SERVER_PID=$!
    
    # Wait for server to start
    sleep 3
    
    # Test health endpoint
    if curl -s http://localhost:3000/health > /dev/null; then
        echo -e "${GREEN}✅ Health check passed${NC}"
    else
        echo -e "${RED}❌ Health check failed${NC}"
        kill $SERVER_PID 2>/dev/null || true
        exit 1
    fi
    
    # Kill the test server
    kill $SERVER_PID 2>/dev/null || true
    echo -e "${GREEN}✅ Local testing completed${NC}"
}

# Setup Git repository if not already initialized
setup_git() {
    echo -e "${BLUE}Setting up Git repository...${NC}"
    
    if [ ! -d ".git" ]; then
        echo -e "${YELLOW}Initializing Git repository...${NC}"
        git init
        git add .
        git commit -m "Initial commit: Configuration API setup"
        echo -e "${GREEN}✅ Git repository initialized${NC}"
    else
        echo -e "${GREEN}✅ Git repository already exists${NC}"
        
        # Check for uncommitted changes
        if ! git diff-index --quiet HEAD --; then
            echo -e "${YELLOW}⚠️  You have uncommitted changes. Committing them...${NC}"
            git add .
            git commit -m "Update: Configuration API changes"
        fi
    fi
}

# Deploy to AWS Amplify
deploy_to_amplify() {
    echo -e "${BLUE}Deploying to AWS Amplify...${NC}"
    
    # Check if AWS CLI is available for Amplify CLI
    if command -v amplify &> /dev/null; then
        echo -e "${GREEN}Amplify CLI detected. You can use:${NC}"
        echo -e "${BLUE}  amplify init${NC}"
        echo -e "${BLUE}  amplify add hosting${NC}"
        echo -e "${BLUE}  amplify publish${NC}"
    else
        echo -e "${YELLOW}Amplify CLI not found. Please install it:${NC}"
        echo -e "${BLUE}  npm install -g @aws-amplify/cli${NC}"
        echo -e "${BLUE}  amplify configure${NC}"
    fi
    
    echo -e "${BLUE}Manual deployment via Amplify Console:${NC}"
    echo "1. Go to AWS Amplify Console: https://console.aws.amazon.com/amplify/"
    echo "2. Click 'New app' → 'Host web app'"
    echo "3. Connect your Git repository"
    echo "4. Configure build settings:"
    echo "   - Build command: npm run build"
    echo "   - Start command: npm start"
    echo "   - Node.js version: 18"
    echo "5. Add environment variables (see README.md for details)"
    echo "6. Deploy!"
}

# Generate environment variables template
generate_env_template() {
    echo -e "${BLUE}Environment Variables for Amplify:${NC}"
    echo "================================="
    echo "Copy these to your Amplify Console environment variables:"
    echo ""
    echo -e "${GREEN}Option A: Single JSON Configuration (Recommended)${NC}"
    echo 'APP_CONFIG={"aws":{"cognito":{"userPoolId":"us-east-1_avChxlbFf","appClientId":"356uds7rdo49e3444imumf21os"}},"api":{"websocketEndpoint":"wss://your-websocket-endpoint.com"},"bot":{"botId":"your-bot-id","foundationModel":"claude-v3.5-sonnet"},"features":{"darkMode":false,"analytics":true,"newCheckout":false},"version":"1.0.0"}'
    echo "API_KEY_IOS=your-secure-ios-key"
    echo "API_KEY_ANDROID=your-secure-android-key"
    echo "API_KEY_WEB=your-secure-web-key"
    echo "ADMIN_API_KEY=your-admin-key"
    echo "NODE_ENV=production"
    echo ""
    echo -e "${YELLOW}Option B: Individual Variables (Fallback)${NC}"
    echo "USER_POOL_ID=us-east-1_avChxlbFf"
    echo "APP_CLIENT_ID=356uds7rdo49e3444imumf21os"
    echo "WEBSOCKET_ENDPOINT=wss://your-websocket-endpoint.com"
    echo "BOT_ID=your-bot-id"
    echo "FOUNDATION_MODEL=claude-v3.5-sonnet"
    echo "API_KEY_IOS=your-secure-ios-key"
    echo "API_KEY_ANDROID=your-secure-android-key"
    echo "API_KEY_WEB=your-secure-web-key"
    echo "ADMIN_API_KEY=your-admin-key"
    echo "NODE_ENV=production"
    echo "FEATURE_DARK_MODE=false"
    echo "FEATURE_ANALYTICS=true"
    echo "FEATURE_NEW_CHECKOUT=false"
    echo ""
    echo -e "${YELLOW}⚠️  Remember to replace placeholder values with your actual configuration!${NC}"
}

# Generate JSON configuration from individual values
generate_json_config() {
    echo -e "${BLUE}Generating JSON Configuration:${NC}"
    echo "============================="
    
    # Prompt for configuration values
    read -p "Enter AWS Cognito User Pool ID [us-east-1_avChxlbFf]: " user_pool_id
    user_pool_id=${user_pool_id:-"us-east-1_avChxlbFf"}
    
    read -p "Enter AWS Cognito App Client ID [356uds7rdo49e3444imumf21os]: " app_client_id
    app_client_id=${app_client_id:-"356uds7rdo49e3444imumf21os"}
    
    read -p "Enter WebSocket Endpoint [wss://your-endpoint.com]: " websocket_endpoint
    websocket_endpoint=${websocket_endpoint:-"wss://your-endpoint.com"}
    
    read -p "Enter Bot ID [your-bot-id]: " bot_id
    bot_id=${bot_id:-"your-bot-id"}
    
    read -p "Enter Foundation Model [claude-v3.5-sonnet]: " foundation_model
    foundation_model=${foundation_model:-"claude-v3.5-sonnet"}
    
    read -p "Enable Dark Mode? [false]: " dark_mode
    dark_mode=${dark_mode:-"false"}
    
    read -p "Enable Analytics? [true]: " analytics
    analytics=${analytics:-"true"}
    
    read -p "Enable New Checkout? [false]: " new_checkout
    new_checkout=${new_checkout:-"false"}
    
    read -p "Configuration Version [1.0.0]: " config_version
    config_version=${config_version:-"1.0.0"}
    
    # Generate JSON
    json_config=$(cat << EOF
{
  "aws": {
    "cognito": {
      "userPoolId": "$user_pool_id",
      "appClientId": "$app_client_id"
    }
  },
  "api": {
    "websocketEndpoint": "$websocket_endpoint"
  },
  "bot": {
    "botId": "$bot_id",
    "foundationModel": "$foundation_model"
  },
  "features": {
    "darkMode": $dark_mode,
    "analytics": $analytics,
    "newCheckout": $new_checkout
  },
  "version": "$config_version"
}
EOF
)
    
    # Minify JSON (remove newlines and extra spaces)
    minified_json=$(echo "$json_config" | jq -c .)
    
    echo -e "${GREEN}Generated APP_CONFIG environment variable:${NC}"
    echo "========================================="
    echo "APP_CONFIG=$minified_json"
    echo ""
    echo -e "${BLUE}Copy this line to your Amplify Console environment variables.${NC}"
    
    # Save to file for easy copying
    echo "APP_CONFIG=$minified_json" > app_config.env
    echo -e "${GREEN}✅ Configuration saved to app_config.env file${NC}"
}

# Generate API keys
generate_api_keys() {
    echo -e "${BLUE}Generating secure API keys...${NC}"
    
    # Generate random API keys
    ios_key="ios-$(openssl rand -hex 16)"
    android_key="android-$(openssl rand -hex 16)"
    web_key="web-$(openssl rand -hex 16)"
    admin_key="admin-$(openssl rand -hex 20)"
    
    echo -e "${GREEN}Generated API Keys:${NC}"
    echo "=================="
    echo "API_KEY_IOS=$ios_key"
    echo "API_KEY_ANDROID=$android_key"
    echo "API_KEY_WEB=$web_key"
    echo "ADMIN_API_KEY=$admin_key"
    echo ""
    echo -e "${YELLOW}⚠️  Save these keys securely! You'll need them for your mobile apps and Amplify environment variables.${NC}"
}

# Main deployment flow
main() {
    echo -e "${GREEN}Starting deployment process...${NC}"
    echo ""
    
    # Parse command line arguments
    case "${1:-all}" in
        "deps")
            check_dependencies
            install_dependencies
            ;;
        "test")
            test_locally
            ;;
        "git")
            setup_git
            ;;
        "keys")
            generate_api_keys
            ;;
        "env")
            generate_env_template
            ;;
        "json")
            generate_json_config
            ;;
        "deploy")
            deploy_to_amplify
            ;;
        "all"|*)
            check_dependencies
            install_dependencies
            test_locally
            setup_git
            echo ""
            generate_api_keys
            echo ""
            generate_env_template
            echo ""
            deploy_to_amplify
            ;;
    esac
    
    echo ""
    echo -e "${GREEN}🎉 Deployment process completed!${NC}"
    echo -e "${BLUE}Next steps:${NC}"
    echo "1. Push your code to a Git repository (GitHub, GitLab, etc.)"
    echo "2. Set up AWS Amplify hosting with your repository"
    echo "3. Configure environment variables in Amplify Console"
    echo "4. Test your deployed API"
    echo "5. Update your iOS app with the production API URL"
    echo ""
    echo -e "${BLUE}📚 For detailed instructions, see README.md${NC}"
}

# Script usage
usage() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  all     - Run complete deployment process (default)"
    echo "  deps    - Check and install dependencies"
    echo "  test    - Test application locally"
    echo "  git     - Setup Git repository"
    echo "  keys    - Generate secure API keys"
    echo "  env     - Show environment variables template"
    echo "  json    - Interactive JSON configuration generator"
    echo "  deploy  - Show deployment instructions"
    echo ""
    echo "Examples:"
    echo "  $0          # Run complete process"
    echo "  $0 test     # Test locally only"
    echo "  $0 keys     # Generate new API keys"
}

# Check if help is requested
if [[ "${1}" == "-h" || "${1}" == "--help" ]]; then
    usage
    exit 0
fi

# Run main function
main "$@"