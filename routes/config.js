const express = require('express');
const router = express.Router();

// Valid API keys 
const VALID_API_KEYS = [
  process.env.API_KEY_IOS,
  process.env.API_KEY_ANDROID,
  process.env.API_KEY_WEB
];


// Legacy fallback config for v1 (individual environment variables)
const getLegacyConfig = () => {
  return {
    aws: {
      cognito: {
        userPoolId: process.env.USER_POOL_ID,
        appClientId: process.env.APP_CLIENT_ID
      }
    },
    api: {
      websocketEndpoint: process.env.WEBSOCKET_ENDPOINT 
    },
    bot: {
      botId: process.env.BOT_ID,
      foundationModel: process.env.FOUNDATION_MODEL || "claude-v3.7-sonnet"
    },
    features: {
      darkMode: process.env.FEATURE_DARK_MODE === 'true' || false,
      analytics: process.env.FEATURE_ANALYTICS === 'true' || true,
      newCheckout: process.env.FEATURE_NEW_CHECKOUT === 'true' || false
    },
    version: process.env.CONFIG_VERSION || "1.0.0"
  };
};

// Generic config loader that supports any version
const getAppConfig = (version = '', environment = '') => {
  const versionSuffix = version ? `_${version}` : '';
  const envSuffix = environment ? `_${environment.toUpperCase()}` : '';
  const envVarName = `APP_CONFIG${versionSuffix}${envSuffix}`;
  
  if (process.env[envVarName]) {
    try {
      const parsedConfig = JSON.parse(process.env[envVarName]);
      console.log(`✅ Configuration loaded from ${envVarName} environment variable`);
      return parsedConfig;
    } catch (error) {
      console.error(`❌ Failed to parse ${envVarName} JSON:`, error.message);
    }
  }
  
  // Fallback logic
  if (environment && !version) {
    return configCache.get('') || getLegacyConfig();
  }
  if (environment && version) {
    return configCache.get(version) || configCache.get('') || getLegacyConfig();
  }
  if (version && !environment) {
    return configCache.get('') || getLegacyConfig();
  }
  
  return getLegacyConfig();
};

// Cache configs on startup
const configCache = new Map();
['', '2', '3', '4', '5'].forEach(version => {
  const config = getAppConfig(version);
  configCache.set(version, config);
  
  const testConfig = getAppConfig(version, 'test');
  configCache.set(`${version}_test`, testConfig);
});

// Legacy constants for backward compatibility
const APP_CONFIG = configCache.get('');
const APP_CONFIG_TEST = configCache.get('_test');

// Rate limiting - simple in-memory store (use Redis in production)
const rateLimitStore = new Map();
const RATE_LIMIT_WINDOW = 60 * 1000; // 1 minute
const RATE_LIMIT_MAX_REQUESTS = 100;

// Rate limiting middleware
const rateLimit = (req, res, next) => {
  const clientId = req.ip + (req.headers['x-app-id'] || 'unknown');
  const now = Date.now();
  
  if (!rateLimitStore.has(clientId)) {
    rateLimitStore.set(clientId, { count: 1, resetTime: now + RATE_LIMIT_WINDOW });
    return next();
  }
  
  const clientData = rateLimitStore.get(clientId);
  
  if (now > clientData.resetTime) {
    // Reset the count
    clientData.count = 1;
    clientData.resetTime = now + RATE_LIMIT_WINDOW;
    return next();
  }
  
  if (clientData.count >= RATE_LIMIT_MAX_REQUESTS) {
    return res.status(429).json({
      error: 'Too Many Requests',
      message: 'Rate limit exceeded. Please try again later.',
      retryAfter: Math.ceil((clientData.resetTime - now) / 1000)
    });
  }
  
  clientData.count++;
  next();
};

// API key validation middleware
const validateApiKey = (req, res, next) => {
  const apiKey = req.headers['x-api-key'] || 
                 req.headers['authorization']?.replace('Bearer ', '') ||
                 req.query.apiKey;
  
  if (!apiKey) {
    return res.status(401).json({
      error: 'Unauthorized',
      message: 'API key is required. Provide it in X-API-Key header, Authorization header, or apiKey query parameter.'
    });
  }
  
  if (!VALID_API_KEYS.includes(apiKey)) {
    console.warn(`Invalid API key attempt: ${apiKey.substring(0, 8)}... from IP: ${req.ip}`);
    return res.status(401).json({
      error: 'Unauthorized',
      message: 'Invalid API key provided.'
    });
  }
  
  // Store the validated API key for logging
  req.validatedApiKey = apiKey;
  next();
};

// Request validation middleware
const validateRequest = (req, res, next) => {
  const appId = req.headers['x-app-id'];
  const appVersion = req.headers['x-app-version'];
  const platform = req.headers['x-platform'];
  
  // Optional validation - log but don't block
  if (!appId) {
    console.warn(`Missing X-App-Id header from IP: ${req.ip}`);
  }
  
  if (!appVersion) {
    console.warn(`Missing X-App-Version header from IP: ${req.ip}`);
  }
  
  next();
};

// Versioned config endpoint (v2, v3, v4, etc.)
router.get('/v:version/config/:environment', rateLimit, validateApiKey, validateRequest, (req, res) => {
  try {
    const { version, environment } = req.params;
    const appId = req.headers['x-app-id'] || 'unknown';
    const appVersion = req.headers['x-app-version'] || 'unknown';
    const platform = req.headers['x-platform'] || 'unknown';
    
    console.log(`✅ V${version} config served for env '${environment}' - App: ${appId}, Version: ${appVersion}, Platform: ${platform}, IP: ${req.ip}`);
    
    const requestId = `req_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    const cacheKey = environment === 'test' ? `${version}_test` : version;
    const config = configCache.get(cacheKey);
    
    const response = {
      ...config,
      metadata: {
        timestamp: new Date().toISOString(),
        requestId: requestId,
        serverVersion: process.env.npm_package_version || '1.0.0',
        environment: environment,
        apiVersion: version
      }
    };
    
    res.set({
      'Cache-Control': 'public, max-age=300',
      'ETag': `"${Buffer.from(JSON.stringify(config)).toString('base64')}"`
    });
    
    res.json(response);
  } catch (error) {
    console.error(`❌ Error serving v${req.params.version} config:`, error);
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Unable to retrieve configuration',
      timestamp: new Date().toISOString()
    });
  }
});

router.get('/v:version/config', rateLimit, validateApiKey, validateRequest, (req, res) => {
  try {
    const { version } = req.params;
    const appId = req.headers['x-app-id'] || 'unknown';
    const appVersion = req.headers['x-app-version'] || 'unknown';
    const platform = req.headers['x-platform'] || 'unknown';
    
    console.log(`✅ V${version} config served - App: ${appId}, Version: ${appVersion}, Platform: ${platform}, IP: ${req.ip}`);
    
    const requestId = `req_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    const config = configCache.get(version);
    
    const response = {
      ...config,
      metadata: {
        timestamp: new Date().toISOString(),
        requestId: requestId,
        serverVersion: process.env.npm_package_version || '1.0.0',
        environment: process.env.NODE_ENV || 'development',
        apiVersion: version
      }
    };
    
    res.set({
      'Cache-Control': 'public, max-age=300',
      'ETag': `"${Buffer.from(JSON.stringify(config)).toString('base64')}"`
    });
    
    res.json(response);
  } catch (error) {
    console.error(`❌ Error serving v${req.params.version} config:`, error);
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Unable to retrieve configuration',
      timestamp: new Date().toISOString()
    });
  }
});

// Legacy v1 config endpoints (backward compatibility)
router.get('/config/:environment', rateLimit, validateApiKey, validateRequest, (req, res) => {
  try {
    const { environment } = req.params;
    const appId = req.headers['x-app-id'] || 'unknown';
    const appVersion = req.headers['x-app-version'] || 'unknown';
    const platform = req.headers['x-platform'] || 'unknown';
    
    console.log(`✅ Config served for env '${environment}' - App: ${appId}, Version: ${appVersion}, Platform: ${platform}, IP: ${req.ip}`);
    
    const requestId = `req_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    const config = environment === 'test' ? APP_CONFIG_TEST : APP_CONFIG;
    
    const response = {
      ...config,
      metadata: {
        timestamp: new Date().toISOString(),
        requestId: requestId,
        serverVersion: process.env.npm_package_version || '1.0.0',
        environment: environment
      }
    };
    
    res.set({
      'Cache-Control': 'public, max-age=300',
      'ETag': `"${Buffer.from(JSON.stringify(config)).toString('base64')}"`
    });
    
    res.json(response);
  } catch (error) {
    console.error('❌ Error serving config:', error);
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Unable to retrieve configuration',
      timestamp: new Date().toISOString()
    });
  }
});

router.get('/config', rateLimit, validateApiKey, validateRequest, (req, res) => {
  try {
    const appId = req.headers['x-app-id'] || 'unknown';
    const appVersion = req.headers['x-app-version'] || 'unknown';
    const platform = req.headers['x-platform'] || 'unknown';
    
    console.log(`✅ Config served - App: ${appId}, Version: ${appVersion}, Platform: ${platform}, IP: ${req.ip}`);
    
    const requestId = `req_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    
    const response = {
      ...APP_CONFIG,
      metadata: {
        timestamp: new Date().toISOString(),
        requestId: requestId,
        serverVersion: process.env.npm_package_version || '1.0.0',
        environment: process.env.NODE_ENV || 'development'
      }
    };
    
    res.set({
      'Cache-Control': 'public, max-age=300',
      'ETag': `"${Buffer.from(JSON.stringify(APP_CONFIG)).toString('base64')}"`
    });
    
    res.json(response);
  } catch (error) {
    console.error('❌ Error serving config:', error);
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Unable to retrieve configuration',
      timestamp: new Date().toISOString()
    });
  }
});

// Config version endpoint (lightweight)
router.get('/config/version', rateLimit, validateApiKey, (req, res) => {
  res.json({
    version: APP_CONFIG.version,
    timestamp: new Date().toISOString(),
    checksum: Buffer.from(JSON.stringify(APP_CONFIG)).toString('base64').substring(0, 16)
  });
});

// Admin endpoint to update feature flags (protected)
router.post('/config/features', validateApiKey, (req, res) => {
  // Additional admin key check
  const adminKey = req.headers['x-admin-key'];
  if (adminKey !== process.env.ADMIN_API_KEY) {
    return res.status(403).json({ error: 'Forbidden', message: 'Admin access required' });
  }
  
  const { features } = req.body;
  if (!features || typeof features !== 'object') {
    return res.status(400).json({ error: 'Bad Request', message: 'Features object is required' });
  }
  
  // Update feature flags (in production, persist to database)
  Object.assign(APP_CONFIG.features, features);
  
  console.log(`🔧 Feature flags updated by admin: ${JSON.stringify(features)}`);
  
  res.json({
    message: 'Feature flags updated successfully',
    features: APP_CONFIG.features,
    timestamp: new Date().toISOString()
  });
});

module.exports = router;