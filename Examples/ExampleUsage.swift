import APIClient
import Foundation

// MARK: - Demo: Complete APIClient Usage Example

// 1. Define your API endpoints
enum GitHubAPI: BaseAPI.APIEndpoint {
    case user(username: String)
    case repos(username: String)
    case createRepo(name: String, description: String)

    var baseURL: String { "https://api.github.com" }

    var url: URL {
        switch self {
        case .user(let username):
            return URL(string: "\(baseURL)/users/\(username)")!
        case .repos(let username):
            return URL(string: "\(baseURL)/users/\(username)/repos")!
        case .createRepo:
            return URL(string: "\(baseURL)/user/repos")!
        }
    }

    var stringValue: String {
        switch self {
        case .user(let username):
            return "users/\(username)"
        case .repos(let username):
            return "users/\(username)/repos"
        case .createRepo(let name, _):
            return "user/repos/\(name)"
        }
    }

    var authHeader: [String: String]? {
        // In a real app, get token securely from keychain or environment
        return ["Authorization": "token YOUR_GITHUB_TOKEN"]
    }
}

// 2. Define your data models
struct GitHubUser: Codable {
    let id: Int
    let login: String
    let name: String?
    let bio: String?
    let publicRepos: Int
    let followers: Int
    let following: Int

    enum CodingKeys: String, CodingKey {
        case id, login, name, bio, followers, following
        case publicRepos = "public_repos"
    }
}

struct GitHubRepo: Codable {
    let id: Int
    let name: String
    let fullName: String
    let description: String?
    let isPrivate: Bool
    let stargazersCount: Int
    let forksCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case fullName = "full_name"
        case isPrivate = "private"
        case stargazersCount = "stargazers_count"
        case forksCount = "forks_count"
    }
}

struct CreateRepoRequest: Codable {
    let name: String
    let description: String
    let isPrivate: Bool = false

    enum CodingKeys: String, CodingKey {
        case name, description
        case isPrivate = "private"
    }
}

// 3. Analytics tracking (optional)
class DemoAnalytics: BaseAPI.APIAnalytics {
    func addAnalytics(
        endpoint: String,
        method: String,
        startTime: Date,
        endTime: Date,
        success: Bool,
        statusCode: Int?,
        error: String?
    ) {
        let duration = endTime.timeIntervalSince(startTime)
        print("📊 Analytics: \(method) \(endpoint) - \(success ? "✅" : "❌") (\(duration)s)")
    }
}

// 4. Main demo class
class APIClientDemo {
    private let client: BaseAPI.BaseAPIClient<GitHubAPI>

    init() {
        // Initialize with logger and analytics
        let logger = APIClientLogger()
        let analytics = DemoAnalytics()

        client = BaseAPI.BaseAPIClient(
            analytics: analytics,
            logger: logger,
            unauthorizedHandler: { endpoint in
                print("🔒 Unauthorized access to \(endpoint.stringValue)")
            }
        )
    }

    // MARK: - Async/Await Examples

    func fetchUserAsync() async {
        print("\n🚀 Fetching user with async/await...")

        do {
            let response: BaseAPI.APIResponse<GitHubUser> = try await client.get(
                .user(username: "torvalds"),
                printResponseBody: true
            )

            let user = response.data
            print("👤 User: \(user.login)")
            print("📝 Bio: \(user.bio ?? "No bio")")
            print("📊 Repos: \(user.publicRepos), Followers: \(user.followers)")

        } catch {
            handleError(error)
        }
    }

    func fetchReposAsync() async {
        print("\n📚 Fetching repositories with async/await...")

        do {
            let response: BaseAPI.APIResponse<[GitHubRepo]> = try await client.get(
                .repos(username: "torvalds")
            )

            let repos = response.data.prefix(3)  // Show first 3
            for repo in repos {
                print("📦 \(repo.name): ⭐\(repo.stargazersCount) 🍴\(repo.forksCount)")
            }

        } catch {
            handleError(error)
        }
    }

    func createRepoAsync() async {
        print("\n➕ Creating repository with async/await...")

        let newRepo = CreateRepoRequest(
            name: "demo-repo",
            description: "A demo repository created via API"
        )

        do {
            let response: BaseAPI.APIResponse<GitHubRepo> = try await client.post(
                .createRepo(name: newRepo.name, description: newRepo.description),
                body: newRepo,
                printRequestBody: true,
                printResponseBody: true
            )

            let repo = response.data
            print("✅ Created repository: \(repo.fullName)")

        } catch {
            handleError(error)
        }
    }

    // MARK: - Callback Examples

    func fetchUserCallback() {
        print("\n🔄 Fetching user with callback...")

        client.get(.user(username: "torvalds")) { (result: BaseAPI.APIResult<GitHubUser>) in
            switch result {
            case .success(let response):
                let user = response.data
                print("👤 User (callback): \(user.login)")

            case .failure(let error):
                self.handleError(error)
            }
        }
    }

    func fetchReposCallback() {
        print("\n📚 Fetching repositories with callback...")

        client.get(.repos(username: "torvalds")) { (result: BaseAPI.APIResult<[GitHubRepo]>) in
            switch result {
            case .success(let response):
                let repos = response.data.prefix(2)
                for repo in repos {
                    print("📦 \(repo.name) (callback)")
                }

            case .failure(let error):
                self.handleError(error)
            }
        }
    }

    // MARK: - Multipart Upload Example

    func uploadFileExample() async {
        print("\n📤 Multipart upload example...")

        // Create sample file
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("sample.txt")
        let content = "Sample file content for upload demo"

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)

            let multipartData = BaseAPI.MultipartData(
                parameters: ["description": "Sample upload" as AnyObject],
                fileKeyName: "file",
                fileURLs: [fileURL]
            )

            let response = try await client.multipartUpload(
                .createRepo(name: "upload-test", description: "Upload test"),
                method: .post,
                data: multipartData,
                printRequestBody: true
            )

            print("✅ Upload completed with status: \(response.statusCode)")

            // Clean up
            try? FileManager.default.removeItem(at: fileURL)

        } catch {
            handleError(error)
        }
    }

    // MARK: - Error Handling

    private func handleError(_ error: Error) {
        if let apiError = error as? BaseAPI.APIError {
            switch apiError {
            case .missingAuthHeader:
                print("❌ Missing authentication header")
            case .networkError(let message):
                print("❌ Network error: \(message)")
            case .serverError(_, let code, let requestID):
                print("❌ Server error \(code), Request ID: \(requestID)")
            case .decodingFailed(_, let message):
                print("❌ Decoding failed: \(message)")
            default:
                print("❌ API Error: \(apiError.localizedDescription)")
            }
        } else {
            print("❌ Unexpected error: \(error.localizedDescription)")
        }
    }

    // MARK: - Run Demo

    func runDemo() async {
        print("🎯 APIClient Demo Starting...")
        print("=" * 50)

        // Async/await examples
        await fetchUserAsync()
        await fetchReposAsync()
        // Note: createRepoAsync requires valid auth token
        // await createRepoAsync()

        // Callback examples
        fetchUserCallback()
        fetchReposCallback()

        // Multipart upload example
        // await uploadFileExample()

        print("\n✅ Demo completed!")
    }
}

// MARK: - Usage Instructions

/*
 To run this demo:

 1. Add your GitHub token to the authHeader in GitHubAPI enum
 2. Create an instance of APIClientDemo and call runDemo()

 Example:
 ```swift
 let demo = APIClientDemo()
 await demo.runDemo()
 ```

 Features demonstrated:
 - ✅ Custom endpoint definitions
 - ✅ Codable data models
 - ✅ Async/await API calls
 - ✅ Callback-based API calls
 - ✅ GET and POST requests
 - ✅ Request/response body logging
 - ✅ Error handling
 - ✅ Analytics tracking
 - ✅ Authentication headers
 - ✅ Multipart file uploads
 - ✅ Structured logging with APIClientLogger
 */

extension String {
    static func * (lhs: String, rhs: Int) -> String {
        return String(repeating: lhs, count: rhs)
    }
}
