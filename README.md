# Configuration API

A Node.js REST API for serving application configuration to mobile and web clients, deployable on AWS App Runner.

## Features

- 🔐 API key authentication
- 🚦 Rate limiting
- 🛡️ Security headers with Helmet
- 📊 Health check endpoint
- ⚙️ Environment-based configuration
- 🏷️ Feature flags support
- 📱 Mobile app optimized
- 🌍 CORS enabled
- 📈 Request logging

## Environment Configuration

The API supports two methods for configuration:

### Method 1: Single JSON Configuration (Recommended)

Set the entire configuration as a JSON string in the `APP_CONFIG` environment variable:

```bash
APP_CONFIG='{"aws":{"cognito":{"userPoolId":"us-east-1_avChxlbFf","appClientId":"356uds7rdo49e3444imumf21os"}},"api":{"websocketEndpoint":"wss://your-endpoint.com"},"bot":{"botId":"your-bot-id","foundationModel":"claude-v3.5-sonnet"},"features":{"darkMode":false,"analytics":true,"newCheckout":false},"version":"1.0.0"}'
```

**Benefits:**
- Easy to copy entire configuration from one environment to another
- Single source of truth
- Perfect for AWS Parameter Store or Secrets Manager integration
- Easier to version control configuration changes

### Method 2: Individual Environment Variables (Fallback)

If `APP_CONFIG` is not provided, the API falls back to individual environment variables:

```bash
USER_POOL_ID=us-east-1_avChxlbFf
APP_CLIENT_ID=356uds7rdo49e3444imumf21os
WEBSOCKET_ENDPOINT=wss://your-endpoint.com
BOT_ID=your-bot-id
FOUNDATION_MODEL=claude-v3.5-sonnet
FEATURE_DARK_MODE=false
FEATURE_ANALYTICS=true
FEATURE_NEW_CHECKOUT=false
CONFIG_VERSION=1.0.0
```

**Benefits:**
- Backward compatibility
- Easier to read and modify individual values
- Good for development environments

### GET /health
Health check endpoint that returns server status.

**Response:**
```json
{
  "status": "healthy",
  "timestamp": "2025-07-15T10:30:00.000Z",
  "version": "1.0.0",
  "environment": "development"
}
```

### GET /api/config
Main configuration endpoint. Requires API key authentication.

**Headers:**
- `X-API-Key` (required): Your API key
- `X-App-Id` (optional): Your app bundle identifier
- `X-App-Version` (optional): Your app version
- `X-Platform` (optional): Platform (ios, android, web)

**Response:**
```json
{
  "aws": {
    "cognito": {
      "userPoolId": "us-east-1_avChxlbFf",
      "appClientId": "356uds7rdo49e3444imumf21os"
    }
  },
  "api": {
    "websocketEndpoint": "wss://pizpdhnqwa.execute-api.us-east-1.amazonaws.com/dev"
  },
  "bot": {
    "botId": "01JWW099SZCNFE9R4JX5PWJ2Z5",
    "foundationModel": "claude-v3.5-sonnet"
  },
  "features": {
    "darkMode": false,
    "analytics": true,
    "newCheckout": false
  },
  "version": "1.0.0",
  "metadata": {
    "timestamp": "2025-07-15T10:30:00.000Z",
    "requestId": "req_1234567890_abcdef123",
    "serverVersion": "1.0.0",
    "environment": "development"
  }
}
```

### GET /api/config/version
Lightweight endpoint to check configuration version.

**Response:**
```json
{
  "version": "1.0.0",
  "timestamp": "2025-07-15T10:30:00.000Z",
  "checksum": "MTIzNDU2Nzg5MGFi"
}
```

## Local Development

### Prerequisites
- Node.js 18.x or higher
- npm 9.x or higher

### Setup

1. **Clone the repository:**
```bash
git clone <your-repo-url>
cd config-api
```

2. **Install dependencies:**
```bash
npm install
```

3. **Configure environment variables:**
Copy `.env.example` to `.env` and update the values:
```bash
cp .env .env.local
```

Edit `.env.local` with your actual configuration values.

4. **Start development server:**
```bash
npm run dev
```

5. **Test the API:**
```bash
# Health check
curl http://localhost:3000/health

# Configuration (replace with your API key)
curl -H "X-API-Key: ios-secure-key-replace-this-12345" \
     -H "X-App-Id: com.yourcompany.yourapp" \
     -H "X-App-Version: 1.0.0" \
     http://localhost:3000/api/config
```

## Deployment on AWS App Runner

AWS App Runner is the recommended platform for deploying this Node.js API as it's specifically designed for containerized web applications and APIs.

### Method 1: Deploy from Git Repository (Recommended)

1. **Push your code to a Git repository** (GitHub, GitLab, Bitbucket)

2. **Create App Runner service:**
   - Go to AWS App Runner Console: https://console.aws.amazon.com/apprunner/
   - Click "Create service"
   - Choose "Source code repository"
   - Connect your Git provider (GitLab, GitHub, etc.)
   - Select your repository: `tokkai/config-api`
   - Branch: `main`

3. **Configure build settings:**
   - Runtime: Node.js 18
   - Build command: `npm install`
   - Start command: `npm start`
   - Port: `3000`

4. **Add environment variables:**
   ```
   NODE_ENV = production
   APP_CONFIG = {"aws":{"cognito":{"userPoolId":"us-east-1_avChxlbFf","appClientId":"356uds7rdo49e3444imumf21os"}},"api":{"websocketEndpoint":"wss://your-websocket-endpoint.com"},"bot":{"botId":"your-bot-id","foundationModel":"claude-v3.5-sonnet"},"features":{"darkMode":false,"analytics":true,"newCheckout":false},"version":"1.0.0"}
   API_KEY_IOS = your-secure-ios-key
   API_KEY_ANDROID = your-secure-android-key
   API_KEY_WEB = your-secure-web-key
   ADMIN_API_KEY = your-admin-key
   ```

5. **Deploy:**
   - Review configuration and click "Create & deploy"
   - App Runner will automatically build and deploy your application
   - Your API will be available at: `https://your-service-id.region.awsapprunner.com`

### Method 2: Deploy using App Runner CLI

1. **Install App Runner CLI:**
```bash
pip install awscli
aws configure
```

2. **Create apprunner.yaml in your project:**
```yaml
version: 1.0
runtime: nodejs18
build:
  commands:
    build:
      - npm ci --production
run:
  runtime-version: 18
  command: npm start
  network:
    port: 3000
    env: PORT
  env:
    - name: NODE_ENV
      value: production
```

3. **Deploy:**
```bash
aws apprunner create-service \
  --service-name config-api \
  --source-configuration '{
    "CodeRepository": {
      "RepositoryUrl": "https://gitlab.com/tokkai/config-api",
      "SourceCodeVersion": {
        "Type": "BRANCH",
        "Value": "main"
      },
      "CodeConfiguration": {
        "ConfigurationSource": "REPOSITORY"
      }
    },
    "AutoDeploymentsEnabled": true
  }'
```

### Why App Runner over AWS Amplify?

App Runner is better suited for this Node.js API because:
- ✅ **Designed for APIs**: Native support for server applications
- ✅ **Automatic scaling**: Scales based on traffic automatically  
- ✅ **Container-based**: Better for Node.js server applications
- ✅ **Simpler configuration**: No complex build configurations needed
- ✅ **Better performance**: Optimized for API workloads
- ✅ **Cost-effective**: Pay only for what you use

### Alternative Deployment Options

#### AWS Amplify (Static hosting alternative)
If you prefer Amplify, you can still deploy but it requires specific configuration for server-side applications. See the troubleshooting section below.

#### AWS Elastic Beanstalk
For more advanced configurations and monitoring:
```bash
eb init config-api
eb create production
eb deploy
```

#### Docker Container
For local development or other cloud platforms:
```bash
docker build -t config-api .
docker run -p 3000:3000 config-api
```

## Security Considerations

### API Keys
- Store API keys securely and rotate them regularly
- Use different keys for different platforms/environments
- Consider using AWS Secrets Manager for production

### Rate Limiting
- Current implementation uses in-memory storage
- For production, consider using Redis or AWS ElastiCache
- Adjust rate limits based on your usage patterns

### CORS
- Update CORS origins in `server.js` for production
- Restrict to your actual app domains

### Environment Variables
- Never commit `.env` files to version control
- Use Amplify Console environment variables for production
- Consider using AWS Systems Manager Parameter Store for sensitive config

## iOS Client Implementation

```swift
class ConfigurationService {
    private let baseURL = "https://your-service-id.region.awsapprunner.com/api"
    private let apiKey = "your-secure-ios-key"
    
    func fetchConfiguration() async throws -> AppConfig {
        guard let url = URL(string: "\(baseURL)/config") else {
            throw ConfigError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue(Bundle.main.bundleIdentifier, forHTTPHeaderField: "X-App-Id")
        request.setValue(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String, 
                        forHTTPHeaderField: "X-App-Version")
        request.setValue("ios", forHTTPHeaderField: "X-Platform")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ConfigError.serverError
        }
        
        return try JSONDecoder().decode(AppConfig.self, from: data)
    }
}
```

## Monitoring and Logging

### CloudWatch Logs
- App Runner automatically sends logs to CloudWatch
- Monitor for error patterns and rate limit hits
- Set up alarms for high error rates

### Access Logs
- View real-time logs in App Runner Console
- Monitor API usage and performance
- Track configuration fetch patterns

### Custom Metrics
Consider adding:
- Request count by platform
- Configuration fetch frequency
- Error rates by endpoint

## Troubleshooting

### Common Issues

1. **Service fails to start:**
   - Check Node.js version is set to 18.x
   - Verify all dependencies are in `package.json`
   - Check service logs in App Runner Console

2. **API returns 401 Unauthorized:**
   - Verify API key is correct
   - Check header name is `X-API-Key`
   - Ensure API key is in environment variables

3. **CORS errors:**
   - Update CORS origins in `server.js`
   - Check if request includes credentials

4. **Rate limiting:**
   - Check rate limit settings in `routes/config.js`
   - Consider implementing Redis for distributed rate limiting

5. **Environment variables not loading:**
   - Verify variables are set in App Runner Console
   - Check variable names match exactly
   - Restart service after adding variables

### Deployment Issues

**Build fails:**
- Check that `package.json` includes all required dependencies
- Verify Node.js version compatibility
- Review build logs in App Runner Console

**Service won't start:**
- Ensure `npm start` script exists in `package.json`
- Check that the application listens on the correct port (from PORT env var)
- Verify environment variables are properly configured

### Support

For issues with this API:
1. Check the logs in AWS CloudWatch or App Runner Console
2. Verify environment variables are set correctly  
3. Test endpoints locally first
4. Check network connectivity and DNS resolution
5. Review App Runner service configuration

