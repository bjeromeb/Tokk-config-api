import Foundation
import UIKit

// MARK: - Configuration Models

struct AppConfig: Codable {
    let aws: AWSConfig
    let api: APIConfig
    let bot: BotConfig
    let features: FeatureFlags
    let version: String
    let metadata: ConfigMetadata?
    
    struct AWSConfig: Codable {
        let cognito: CognitoConfig
        
        struct CognitoConfig: Codable {
            let userPoolId: String
            let appClientId: String
        }
    }
    
    struct APIConfig: Codable {
        let websocketEndpoint: String
    }
    
    struct BotConfig: Codable {
        let botId: String
        let foundationModel: String
    }
    
    struct FeatureFlags: Codable {
        let darkMode: Bool
        let analytics: Bool
        let newCheckout: Bool
    }
    
    struct ConfigMetadata: Codable {
        let timestamp: String
        let requestId: String
        let serverVersion: String
        let environment: String
    }
}

struct ConfigVersion: Codable {
    let version: String
    let timestamp: String
    let checksum: String
}

// MARK: - Configuration Errors

enum ConfigError: Error, LocalizedError {
    case invalidURL
    case unauthorized
    case serverError(Int)
    case networkError(Error)
    case decodingError(Error)
    case rateLimited(retryAfter: Int?)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid configuration URL"
        case .unauthorized:
            return "Invalid API key"
        case .serverError(let code):
            return "Server error (HTTP \(code))"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to decode configuration: \(error.localizedDescription)"
        case .rateLimited(let retryAfter):
            if let retryAfter = retryAfter {
                return "Rate limit exceeded. Retry after \(retryAfter) seconds."
            } else {
                return "Rate limit exceeded. Please try again later."
            }
        }
    }
}

// MARK: - Feature Enum

enum ConfigFeature {
    case darkMode
    case analytics
    case newCheckout
}

// MARK: - Configuration Service

@MainActor
class ConfigurationService: ObservableObject {
    
    // MARK: - Properties
    
    @Published var currentConfig: AppConfig?
    @Published var isLoading = false
    @Published var lastUpdateTime: Date?
    @Published var error: ConfigError?
    
    private let baseURL: String
    private let apiKey: String
    private let urlSession: URLSession
    
    // Cache configuration for offline use
    private let userDefaults = UserDefaults.standard
    private let configCacheKey = "cached_app_config"
    private let lastFetchKey = "last_config_fetch"
    
    // MARK: - Initialization
    
    init(baseURL: String, apiKey: String) {
        self.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = apiKey
        
        // Configure URL session with timeout and caching
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.urlSession = URLSession(configuration: config)
        
        // Load cached configuration if available
        loadCachedConfiguration()
    }
    
    // MARK: - Public Methods
    
    /// Fetches the latest configuration from the server
    func fetchConfiguration() async {
        isLoading = true
        error = nil
        
        do {
            let config = try await performConfigurationRequest()
            currentConfig = config
            lastUpdateTime = Date()
            cacheConfiguration(config)
            print("✅ Configuration fetched successfully")
        } catch let configError as ConfigError {
            error = configError
            print("❌ Configuration fetch failed: \(configError.localizedDescription)")
            // Fall back to cached configuration if available
            if currentConfig == nil {
                loadCachedConfiguration()
            }
        } catch {
            let wrappedError = ConfigError.networkError(error)
            self.error = wrappedError
            print("❌ Unexpected error: \(error)")
        }
        
        isLoading = false
    }
    
    /// Checks if configuration should be refreshed based on cache age
    func shouldRefreshConfiguration() -> Bool {
        guard let lastFetch = userDefaults.object(forKey: lastFetchKey) as? Date else {
            return true // Never fetched before
        }
        
        // Refresh if older than 5 minutes
        return Date().timeIntervalSince(lastFetch) > 300
    }
    
    /// Fetches configuration only if cache is stale
    func fetchConfigurationIfNeeded() async {
        if shouldRefreshConfiguration() {
            await fetchConfiguration()
        }
    }
    
    /// Gets current configuration version without full config
    func fetchConfigurationVersion() async throws -> ConfigVersion {
        guard let url = URL(string: "\(baseURL)/config/version") else {
            throw ConfigError.invalidURL
        }
        
        var request = createBaseRequest(for: url)
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            try handleHTTPResponse(response)
            return try JSONDecoder().decode(ConfigVersion.self, from: data)
        } catch let error as ConfigError {
            throw error
        } catch {
            throw ConfigError.networkError(error)
        }
    }
    
    // MARK: - Feature Flag Helpers
    
    /// Check if a specific feature is enabled
    func isFeatureEnabled(_ feature: ConfigFeature) -> Bool {
        guard let config = currentConfig else { return false }
        
        switch feature {
        case .darkMode:
            return config.features.darkMode
        case .analytics:
            return config.features.analytics
        case .newCheckout:
            return config.features.newCheckout
        }
    }
    
    /// Get AWS Cognito configuration
    func getCognitoConfig() -> (userPoolId: String, appClientId: String)? {
        guard let config = currentConfig else { return nil }
        return (config.aws.cognito.userPoolId, config.aws.cognito.appClientId)
    }
    
    /// Get WebSocket endpoint
    func getWebSocketEndpoint() -> String? {
        return currentConfig?.api.websocketEndpoint
    }
    
    /// Get bot configuration
    func getBotConfig() -> (botId: String, model: String)? {
        guard let config = currentConfig else { return nil }
        return (config.bot.botId, config.bot.foundationModel)
    }
    
    // MARK: - Private Methods
    
    private func performConfigurationRequest() async throws -> AppConfig {
        guard let url = URL(string: "\(baseURL)/config") else {
            throw ConfigError.invalidURL
        }
        
        var request = createBaseRequest(for: url)
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            try handleHTTPResponse(response)
            
            let decoder = JSONDecoder()
            return try decoder.decode(AppConfig.self, from: data)
        } catch let error as ConfigError {
            throw error
        } catch DecodingError.keyNotFound(let key, let context) {
            print("❌ Missing key '\(key.stringValue)' in configuration response")
            throw ConfigError.decodingError(DecodingError.keyNotFound(key, context))
        } catch DecodingError.typeMismatch(let type, let context) {
            print("❌ Type mismatch for '\(type)' in configuration response")
            throw ConfigError.decodingError(DecodingError.typeMismatch(type, context))
        } catch {
            throw ConfigError.networkError(error)
        }
    }
    
    private func createBaseRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        
        // Required headers
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        
        // Optional but recommended headers
        if let bundleId = Bundle.main.bundleIdentifier {
            request.setValue(bundleId, forHTTPHeaderField: "X-App-Id")
        }
        
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            request.setValue(version, forHTTPHeaderField: "X-App-Version")
        }
        
        if let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            request.setValue(buildNumber, forHTTPHeaderField: "X-Build-Number")
        }
        
        request.setValue("ios", forHTTPHeaderField: "X-Platform")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // Device info (optional)
        let device = UIDevice.current
        request.setValue("\(device.systemName) \(device.systemVersion)", forHTTPHeaderField: "X-OS-Version")
        request.setValue(device.model, forHTTPHeaderField: "X-Device-Model")
        
        return request
    }
    
    private func handleHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConfigError.networkError(URLError(.badServerResponse))
        }
        
        switch httpResponse.statusCode {
        case 200:
            return // Success
        case 401:
            throw ConfigError.unauthorized
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw ConfigError.rateLimited(retryAfter: retryAfter)
        case 400...499:
            throw ConfigError.serverError(httpResponse.statusCode)
        case 500...599:
            throw ConfigError.serverError(httpResponse.statusCode)
        default:
            throw ConfigError.serverError(httpResponse.statusCode)
        }
    }
    
    private func cacheConfiguration(_ config: AppConfig) {
        do {
            let data = try JSONEncoder().encode(config)
            userDefaults.set(data, forKey: configCacheKey)
            userDefaults.set(Date(), forKey: lastFetchKey)
            print("✅ Configuration cached successfully")
        } catch {
            print("❌ Failed to cache configuration: \(error)")
        }
    }
    
    private func loadCachedConfiguration() {
        guard let data = userDefaults.data(forKey: configCacheKey) else {
            print("ℹ️ No cached configuration found")
            return
        }
        
        do {
            let config = try JSONDecoder().decode(AppConfig.self, from: data)
            currentConfig = config
            lastUpdateTime = userDefaults.object(forKey: lastFetchKey) as? Date
            print("✅ Loaded cached configuration")
        } catch {
            print("❌ Failed to load cached configuration: \(error)")
            // Clear corrupted cache
            userDefaults.removeObject(forKey: configCacheKey)
            userDefaults.removeObject(forKey: lastFetchKey)
        }
    }
    
    /// Clear all cached configuration data
    func clearCache() {
        userDefaults.removeObject(forKey: configCacheKey)
        userDefaults.removeObject(forKey: lastFetchKey)
        currentConfig = nil
        lastUpdateTime = nil
        print("✅ Configuration cache cleared")
    }
}

// MARK: - Usage Example in SwiftUI

import SwiftUI

struct ContentView: View {
    @StateObject private var configService = ConfigurationService(
        baseURL: "https://your-app.amplifyapp.com/api",
        apiKey: "your-secure-ios-key"
    )
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if configService.isLoading {
                    ProgressView("Loading configuration...")
                } else if let error = configService.error {
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.red)
                            .font(.largeTitle)
                        Text("Configuration Error")
                            .font(.headline)
                        Text(error.localizedDescription)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task {
                                await configService.fetchConfiguration()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                } else if let config = configService.currentConfig {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Configuration Loaded")
                            .font(.headline)
                        
                        Group {
                            Text("Version: \(config.version)")
                            Text("Bot Model: \(config.bot.foundationModel)")
                            Text("Dark Mode: \(configService.isFeatureEnabled(.darkMode) ? "Enabled" : "Disabled")")
                            Text("Analytics: \(configService.isFeatureEnabled(.analytics) ? "Enabled" : "Disabled")")
                        }
                        .font(.caption)
                        
                        if let lastUpdate = configService.lastUpdateTime {
                            Text("Last updated: \(lastUpdate, style: .relative) ago")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    Text("No configuration available")
                        .foregroundColor(.secondary)
                }
                
                Button("Refresh Configuration") {
                    Task {
                        await configService.fetchConfiguration()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(configService.isLoading)
            }
            .padding()
            .navigationTitle("Config Demo")
        }
        .task {
            await configService.fetchConfigurationIfNeeded()
        }
        .refreshable {
            await configService.fetchConfiguration()
        }
    }
}

// MARK: - Usage in App Delegate or SceneDelegate

class AppDelegate: NSObject, UIApplicationDelegate {
    
    lazy var configService = ConfigurationService(
        baseURL: "https://your-app.amplifyapp.com/api",
        apiKey: "your-secure-ios-key"
    )
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // Fetch configuration on app launch
        Task {
            await configService.fetchConfiguration()
            
            // Example: Configure analytics based on feature flag
            if configService.isFeatureEnabled(.analytics) {
                // Initialize analytics SDK
                print("Analytics enabled - initializing SDK")
            }
            
            // Example: Configure AWS Cognito
            if let cognitoConfig = configService.getCognitoConfig() {
                // Initialize AWS Cognito with fetched configuration
                print("Configuring Cognito with pool: \(cognitoConfig.userPoolId)")
            }
        }
        
        return true
    }
}