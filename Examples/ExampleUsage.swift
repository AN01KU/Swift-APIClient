import APIClient
import Foundation

// MARK: - Demo: Complete APIClient Usage Example

// 1. Define your API endpoints
enum GitHubAPI: BaseAPI.APIEndpoint {
    case user(username: String)
    case repos(username: String)
    case createRepo(name: String, description: String)

    var baseURL: URL { URL(string: "https://api.github.com")! }

    var path: String {
        switch self {
        case .user(let username):
            return "users/\(username)"
        case .repos(let username):
            return "users/\(username)/repos"
        case .createRepo:
            return "user/repos"
        }
    }

}

// 2. Create a request interceptor for authentication
struct GitHubAuthInterceptor: BaseAPI.RequestInterceptor {
    let token: String

    func adapt(_ request: URLRequest) async throws -> URLRequest {
        var request = request
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        return request
    }
}

// 3. Define your data models
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

// 4. Analytics tracking (optional)
final class DemoAnalytics: BaseAPI.APIAnalytics, @unchecked Sendable {
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

// 5. Main demo class
class APIClientDemo {
    private let client: BaseAPI.BaseAPIClient<GitHubAPI>

    init() {
        let logger = APIClientLogger()
        let analytics = DemoAnalytics()
        let interceptor = GitHubAuthInterceptor(token: "YOUR_GITHUB_TOKEN")

        client = BaseAPI.BaseAPIClient(
            interceptor: interceptor,
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
                .user(username: "torvalds")
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
                body: newRepo
            )

            let repo = response.data
            print("✅ Created repository: \(repo.fullName)")

        } catch {
            handleError(error)
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
                data: multipartData
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
