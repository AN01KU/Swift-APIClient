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

    var headers: [String: String]? {
        ["Accept": "application/vnd.github+json"]
    }
}

// 2. Create a request interceptor for authentication
struct GitHubAuthInterceptor: BaseAPI.RequestInterceptor {
    let token: String

    func adapt(_ request: URLRequest) async throws -> URLRequest {
        var request = request
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
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

// 4. Event monitor for observability (replaces the deprecated APIAnalytics)
final class DemoEventMonitor: BaseAPI.RequestEventMonitor, @unchecked Sendable {
    func requestDidStart(_ request: URLRequest, endpoint: String, method: String) {
        print("→ \(method) \(endpoint)")
    }

    func requestDidFinish(
        _ request: URLRequest, endpoint: String, method: String,
        response: HTTPURLResponse, duration: TimeInterval
    ) {
        print("✓ \(method) \(endpoint) \(response.statusCode) (\(String(format: "%.2f", duration))s)")
    }

    func requestDidFail(
        _ request: URLRequest, endpoint: String, method: String,
        error: BaseAPI.APIError, duration: TimeInterval
    ) {
        print("✗ \(method) \(endpoint) — \(error.localizedDescription)")
    }
}

// 5. Main demo class
final class APIClientDemo {
    private let client: BaseAPI.BaseAPIClient<GitHubAPI>

    init() {
        client = BaseAPI.BaseAPIClient(
            interceptors: [
                GitHubAuthInterceptor(token: "YOUR_GITHUB_TOKEN"),
                BaseAPI.RetryPolicy(maxAttempts: 3, backoff: .exponential(base: 1, multiplier: 2, maxDelay: 30)),
            ],
            eventMonitors: [DemoEventMonitor()],
            logger: APIClientLogger(),
            unauthorizedHandler: { endpoint in
                print("Unauthorized: \(endpoint.stringValue)")
            }
        )
    }

    // MARK: - Example requests

    func fetchUser() async {
        do {
            let (user, _): BaseAPI.APIResponse<GitHubUser> = try await client.get(.user(username: "torvalds"))
            print("User: \(user.login), repos: \(user.publicRepos)")
        } catch {
            handleError(error)
        }
    }

    func fetchRepos() async {
        do {
            let (repos, _): BaseAPI.APIResponse<[GitHubRepo]> = try await client.get(.repos(username: "torvalds"))
            for repo in repos.prefix(3) {
                print("\(repo.name): ★\(repo.stargazersCount)")
            }
        } catch {
            handleError(error)
        }
    }

    func createRepo() async {
        let body = CreateRepoRequest(name: "demo-repo", description: "Created via APIClient")
        do {
            let (repo, _): BaseAPI.APIResponse<GitHubRepo> = try await client.post(
                .createRepo(name: body.name, description: body.description),
                body: body
            )
            print("Created: \(repo.fullName)")
        } catch {
            handleError(error)
        }
    }

    func downloadWithProgress() async {
        for try await progress in client.download(.repos(username: "torvalds")) {
            if let data = progress.data {
                print("Download complete: \(data.count) bytes")
            } else if let fraction = progress.fraction {
                print("Progress: \(Int(fraction * 100))%")
            }
        }
    }

    // MARK: - Fluent RequestBuilder example

    func fetchUserWithBuilder() async {
        do {
            let (user, _): BaseAPI.APIResponse<GitHubUser> = try await client
                .request(.user(username: "torvalds"))
                .headers(["X-Request-ID": UUID().uuidString])
                .timeout(15)
                .response()
            print("User via builder: \(user.login)")
        } catch {
            handleError(error)
        }
    }

    // MARK: - Multipart upload example

    func uploadFile() async {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("sample.txt")
        do {
            try "Sample content".write(to: fileURL, atomically: true, encoding: .utf8)

            let data = BaseAPI.MultipartData(
                parameters: ["description": "Sample upload" as AnyObject],
                fileKeyName: "file",
                fileURLs: [fileURL]
            )
            let response = try await client.multipartUpload(
                .createRepo(name: "upload-test", description: "Upload test"),
                method: .post,
                data: data
            )
            print("Upload status: \(response.statusCode)")
            try? FileManager.default.removeItem(at: fileURL)
        } catch {
            handleError(error)
        }
    }

    // MARK: - Error handling

    private func handleError(_ error: Error) {
        guard let apiError = error as? BaseAPI.APIError else {
            print("Unexpected error: \(error.localizedDescription)")
            return
        }
        switch apiError {
        case .networkError(let urlError):
            print("Network error: \(urlError.localizedDescription)")
        case .serverError(_, let code, let requestID):
            print("Server error \(code) (request ID: \(requestID))")
        case .decodingFailed(_, let message):
            print("Decoding failed: \(message)")
        default:
            print("API error: \(apiError.localizedDescription)")
        }
    }
}
