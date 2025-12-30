# iOS Integration Implementation Guide

## ⚠️ CRITICAL: Fix Deployment Target FIRST

Your Xcode project has `IPHONEOS_DEPLOYMENT_TARGET = 26.1` which is INVALID (iOS 26 doesn't exist).

**Fix immediately:**
1. Open `ClearSplit.xcodeproj` in Xcode
2. Select project → Build Settings → search "Deployment Target"
3. Set to **iOS 16.0** for all targets (ClearSplit, ClearSplitTests, ClearSplitUITests)

---

## 📁 Files Already Created

✅ `APIConfig.swift` - Base URL configuration  
✅ `Models.swift` - AuthTokens, User, Group models  
✅ `APIError.swift` - Typed API errors  

---

## 📁 Files You Need to Create

Copy the code from this guide into new files in Xcode:

### 1. KeychainService.swift

```swift
//
//  KeychainService.swift
//  ClearSplit
//

import Foundation
import Security

enum KeychainService {
    private static let accessTokenKey = "com.clearsplit.accessToken"
    private static let refreshTokenKey = "com.clearsplit.refreshToken"
    
    // MARK: - Save
    
    static func saveTokens(_ tokens: AuthTokens) throws {
        try save(tokens.accessToken, forKey: accessTokenKey)
        try save(tokens.refreshToken, forKey: refreshTokenKey)
    }
    
    static func save(_ value: String, forKey key: String) throws {
        let data = value.data(using: .utf8)!
        
        // Delete existing
        delete(forKey: key)
        
        // Add new
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "KeychainService", code: Int(status))
        }
    }
    
    // MARK: - Retrieve
    
    static func getTokens() -> AuthTokens? {
        guard let accessToken = getString(forKey: accessTokenKey),
              let refreshToken = getString(forKey: refreshTokenKey) else {
            return nil
        }
        return AuthTokens(accessToken: accessToken, refreshToken: refreshToken, tokenType: "Bearer")
    }
    
    static func getString(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }
    
    // MARK: - Delete
    
    static func deleteTokens() {
        delete(forKey: accessTokenKey)
        delete(forKey: refreshTokenKey)
    }
    
    @discardableResult
    static func delete(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
```

### 2. APIClient.swift

```swift
//
//  APIClient.swift
//  ClearSplit
//

import Foundation

@MainActor
class APIClient {
    static let shared = APIClient()
    
    private let session: URLSession
    private var isRefreshing = false
    private var refreshTask: Task<AuthTokens, Error>?
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Request
    
    func request<T: Decodable>(
        _ endpoint: String,
        method: String = "GET",
        body: Encodable? = nil,
        requiresAuth: Bool = true
    ) async throws -> T {
        var request = try buildRequest(endpoint, method: method, body: body, requiresAuth: requiresAuth)
        
        do {
            return try await performRequest(request)
        } catch APIError.unauthorized where requiresAuth {
            // Attempt refresh and retry once
            try await refreshTokens()
            request = try buildRequest(endpoint, method: method, body: body, requiresAuth: true)
            return try await performRequest(request)
        }
    }
    
    // MARK: - Build Request
    
    private func buildRequest(_ endpoint: String, method: String, body: Encodable?, requiresAuth: Bool) throws -> URLRequest {
        guard let url = URL(string: endpoint, relativeTo: APIConfig.baseURL) else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if requiresAuth, let tokens = KeychainService.getTokens() {
            request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        }
        
        if let body = body {
            request.httpBody = try JSONEncoder().encode(body)
        }
        
        return request
    }
    
    // MARK: - Perform Request
    
    private func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200...299:
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw APIError.decodingError(error)
            }
            
        case 401:
            throw APIError.unauthorized
            
        default:
            let message = try? JSONDecoder().decode([String: String].self, from: data)
            throw APIError.serverError(httpResponse.statusCode, message?["detail"])
        }
    }
    
    // MARK: - Refresh Tokens (Single-Flight)
    
    private func refreshTokens() async throws {
        // If refresh is already in progress, wait for it
        if let existingTask = refreshTask {
            _ = try await existingTask.value
            return
        }
        
        // Start new refresh task
        let task = Task<AuthTokens, Error> {
            guard let tokens = KeychainService.getTokens() else {
                throw APIError.unauthorized
            }
            
            struct RefreshRequest: Encodable {
                let refreshToken: String
                
                enum CodingKeys: String, CodingKey {
                    case refreshToken = "refresh_token"
                }
            }
            
            let refreshRequest = RefreshRequest(refreshToken: tokens.refreshToken)
            let newTokens: AuthTokens = try await performRequest(
                buildRequest("/auth/refresh", method: "POST", body: refreshRequest, requiresAuth: false)
            )
            
            try KeychainService.saveTokens(newTokens)
            return newTokens
        }
        
        refreshTask = task
        defer { refreshTask = nil }
        
        _ = try await task.value
    }
}
```

### 3. AuthService.swift

```swift
//
//  AuthService.swift
//  ClearSplit
//

import Foundation

struct AuthService {
    struct LoginRequest: Encodable {
        let email: String
        let password: String
    }
    
    static func login(email: String, password: String) async throws -> AuthTokens {
        let request = LoginRequest(email: email, password: password)
        let tokens: AuthTokens = try await APIClient.shared.request(
            "/auth/login",
            method: "POST",
            body: request,
            requiresAuth: false
        )
        try KeychainService.saveTokens(tokens)
        return tokens
    }
    
    static func me() async throws -> User {
        return try await APIClient.shared.request("/auth/me")
    }
    
    static func logout() {
        KeychainService.deleteTokens()
    }
}
```

### 4. GroupsService.swift

```swift
//
//  GroupsService.swift
//  ClearSplit
//

import Foundation

struct GroupsService {
    static func listGroups() async throws -> [Group] {
        return try await APIClient.shared.request("/groups")
    }
}
```

### 5. LoginViewModel.swift

```swift
//
//  LoginViewModel.swift
//  ClearSplit
//

import Foundation

@MainActor
class LoginViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    func login() async -> Bool {
        guard validate() else { return false }
        
        isLoading = true
        errorMessage = nil
        
        do {
            _ = try await AuthService.login(email: email, password: password)
            isLoading = false
            return true
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            return false
        }
    }
    
    private func validate() -> Bool {
        guard !email.isEmpty else {
            errorMessage = "Email is required"
            return false
        }
        guard !password.isEmpty else {
            errorMessage = "Password is required"
            return false
        }
        return true
    }
}
```

### 6. GroupsViewModel.swift

```swift
//
//  GroupsViewModel.swift
//  ClearSplit
//

import Foundation

@MainActor
class GroupsViewModel: ObservableObject {
    @Published var groups: [Group] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    func loadGroups() async {
        isLoading = true
        errorMessage = nil
        
        do {
            groups = try await GroupsService.listGroups()
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }
}
```

### 7. LoginView.swift

```swift
//
//  LoginView.swift
//  ClearSplit
//

import SwiftUI

struct LoginView: View {
    @StateObject private var viewModel = LoginViewModel()
    @Binding var isAuthenticated: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("ClearSplit")
                    .font(.largeTitle)
                    .bold()
                
                VStack(spacing: 16) {
                    TextField("Email", text: $viewModel.email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    
                    SecureField("Password", text: $viewModel.password)
                        .textContentType(.password)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                }
                .disabled(viewModel.isLoading)
                
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                Button(action: {
                    Task {
                        if await viewModel.login() {
                            isAuthenticated = true
                        }
                    }
                }) {
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Text("Log In")
                            .bold()
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                .disabled(viewModel.isLoading)
            }
            .padding()
            .navigationTitle("Login")
        }
    }
}
```

### 8. GroupsListView.swift

```swift
//
//  GroupsListView.swift
//  ClearSplit
//

import SwiftUI

struct GroupsListView: View {
    @StateObject private var viewModel = GroupsViewModel()
    @Binding var isAuthenticated: Bool
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading groups...")
                } else if let errorMessage = viewModel.errorMessage {
                    VStack(spacing: 16) {
                        Text(errorMessage)
                            .foregroundColor(.red)
                        Button("Retry") {
                            Task {
                                await viewModel.loadGroups()
                            }
                        }
                    }
                } else if viewModel.groups.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.3")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No groups yet")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
                } else {
                    List(viewModel.groups) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.name)
                                .font(.headline)
                            Text(group.currency)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Groups")
            .toolbar {
                Button("Log Out") {
                    AuthService.logout()
                    isAuthenticated = false
                }
            }
            .refreshable {
                await viewModel.loadGroups()
            }
            .task {
                if viewModel.groups.isEmpty {
                    await viewModel.loadGroups()
                }
            }
        }
    }
}
```

### 9. RootView.swift

```swift
//
//  RootView.swift
//  ClearSplit
//

import SwiftUI

struct RootView: View {
    @State private var isAuthenticated = false
    @State private var isCheckingAuth = true
    
    var body: some View {
        Group {
            if isCheckingAuth {
                ProgressView("Loading...")
            } else if isAuthenticated {
                GroupsListView(isAuthenticated: $isAuthenticated)
            } else {
                LoginView(isAuthenticated: $isAuthenticated)
            }
        }
        .task {
            await checkAuthentication()
        }
    }
    
    private func checkAuthentication() async {
        // Check if we have tokens
        guard KeychainService.getTokens() != nil else {
            isCheckingAuth = false
            isAuthenticated = false
            return
        }
        
        // Verify tokens with /auth/me
        do {
            _ = try await AuthService.me()
            isAuthenticated = true
        } catch {
            // Invalid tokens, clear them
            AuthService.logout()
            isAuthenticated = false
        }
        
        isCheckingAuth = false
    }
}
```

### 10. Update ClearSplitApp.swift

```swift
import SwiftUI

@main
struct ClearSplitApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
```

---

## 🔧 Xcode Project Configuration

### Fix Build Settings (CRITICAL)

Open `ClearSplit.xcodeproj` in Xcode:

1. **Select project** in navigator → **ClearSplit** target → **Build Settings**

2. **Search for these settings and update:**

| Setting | Debug | Release |
|---------|-------|---------|
| **iOS Deployment Target** | `16.0` | `16.0` |
| **Architectures** | `Standard Architectures (arm64)` | `Standard Architectures (arm64)` |
| **Build Active Architecture Only** | `Yes` | `No` |
| **Excluded Architectures** | *(empty)* | *(empty)* |

3. **Repeat for `ClearSplitTests` and `ClearSplitUITests` targets**

---

## 📝 Info.plist Configuration

Add to `Info.plist`:

```xml
<key>BASE_URL</key>
<string>http://localhost:8000</string>
```

For **real device testing**, change to your Mac's LAN IP:
```xml
<key>BASE_URL</key>
<string>http://192.168.1.100:8000</string>
```

To find your Mac's IP:
```bash
ifconfig | grep "inet " | grep -v 127.0.0.1
```

---

## ✅ Verification Commands

### 1. Build via Xcode
- Open project in Xcode
- Select **iPhone 15 Simulator**
- Press `⌘+B` (Build)

### 2. Build via CLI
```bash
cd /Users/yslim0622/ClearSplit/ios/ClearSplit/ClearSplit

# Build for simulator
xcodebuild -scheme ClearSplit \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  clean build

# Check settings
xcodebuild -showBuildSettings -scheme ClearSplit | grep -E "(DEPLOYMENT|ARCHS|ONLY_ACTIVE)"
```

### 3. Run the App
1. Start backend: `cd backend && uvicorn app.main:app --reload`
2. Run app in simulator
3. Test flow:
   - Login with test credentials
   - View groups list
   - Pull to refresh
   - Log out

---

## 📚 Team Setup Documentation

### Prerequisites
- Xcode 15.0+
- macOS Ventura or later
- ClearSplit backend running

### Setup Steps

1. **Clone repository**
   ```bash
   git clone https://github.com/yslim-030622/ClearSplit.git
   cd ClearSplit/ios/ClearSplit/ClearSplit
   ```

2. **Open project**
   ```bash
   open ClearSplit.xcodeproj
   ```

3. **Select simulator**
   - Xcode → Select **iPhone 15** (or any iOS 16+ simulator)

4. **Configure BASE_URL** (if needed)
   - Edit `Info.plist` → Change `BASE_URL` value
   - Simulator: `http://localhost:8000`
   - Device: `http://YOUR_MAC_IP:8000`

5. **Build and run**
   - Press `⌘+R`

### Troubleshooting

#### Build fails with "No such module"
```bash
# Clean build folder
⌘+Shift+K in Xcode
# Or via CLI:
xcodebuild clean
rm -rf ~/Library/Developer/Xcode/DerivedData/ClearSplit-*
```

#### "Cannot connect to backend"
- Check backend is running: `curl http://localhost:8000/health`
- For device: Use Mac's LAN IP in Info.plist
- Check firewall allows connections on port 8000

#### Intel Mac vs Apple Silicon
**Both work the same way!** No special configuration needed.

**What we did:**
- ✅ Architectures: `Standard Architectures` (supports both)
- ✅ Build Active Architecture Only: `YES` (Debug)
- ✅ Excluded Architectures: *empty* (never exclude arm64)

**Never:**
- ❌ Set "Excluded Architectures" to exclude arm64
- ❌ Use Rosetta-only builds
- ❌ Add architecture-specific hacks

---

## 🔍 Why These Settings Matter

### 1. Standard Architectures
- **Intel Mac:** Builds for arm64 (simulator runs on Rosetta)
- **Apple Silicon:** Builds natively for arm64
- Both produce identical binaries

### 2. Build Active Architecture Only (YES in Debug)
- Speeds up debug builds (only builds for current simulator arch)
- Release builds all architectures (for App Store)

### 3. iOS Deployment Target 16.0
- Supports async/await syntax
- Modern SwiftUI features
- 95%+ iOS device coverage

### 4. Empty Excluded Architectures
- Never exclude arm64 (would break Apple Silicon Macs and all real devices)
- Never exclude x86_64 (would break Intel Mac simulators)

---

## 📋 File Checklist

- [x] APIConfig.swift
- [x] Models.swift (AuthTokens, User, Group)
- [x] APIError.swift
- [ ] KeychainService.swift
- [ ] APIClient.swift
- [ ] AuthService.swift
- [ ] GroupsService.swift
- [ ] LoginViewModel.swift
- [ ] GroupsViewModel.swift
- [ ] LoginView.swift
- [ ] GroupsListView.swift
- [ ] RootView.swift
- [ ] ClearSplitApp.swift (update)
- [ ] Info.plist (add BASE_URL)
- [ ] Xcode build settings (fix deployment target)

---

## 🎯 Next Steps

1. **FIX DEPLOYMENT TARGET** (most critical!)
2. Copy all Swift files into Xcode project
3. Update Info.plist with BASE_URL
4. Build and test

**Estimated time:** 30-45 minutes to implement all files.





