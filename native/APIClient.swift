import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case server(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "请求地址无效"
        case .server(let message): return message
        case .invalidResponse: return "后端返回了无法识别的数据"
        }
    }
}

final class APIClient: @unchecked Sendable {
    static let shared = APIClient()

    private let baseURL = URL(string: "http://127.0.0.1:8098/api/")!
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    func envelope<Value: Decodable>(
        _ path: String,
        query: [URLQueryItem] = []
    ) async throws -> APIEnvelope<Value> {
        let request = try makeRequest(path: path, query: query)
        return try await decode(request)
    }

    func get<Value: Decodable>(
        _ path: String,
        query: [URLQueryItem] = []
    ) async throws -> Value {
        let response: APIEnvelope<Value> = try await envelope(path, query: query)
        guard response.success else { throw APIError.server(response.message) }
        guard let data = response.data else { throw APIError.invalidResponse }
        return data
    }

    func command(
        _ path: String,
        query: [URLQueryItem] = []
    ) async throws -> String {
        let response: APIEnvelope<EmptyPayload> = try await envelope(path, query: query)
        guard response.success else { throw APIError.server(response.message) }
        return response.message
    }

    func post<Body: Encodable, Value: Decodable>(
        _ path: String,
        body: Body
    ) async throws -> APIEnvelope<Value> {
        var request = try makeRequest(path: path)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await decode(request)
    }

    func postCommand<Body: Encodable>(_ path: String, body: Body) async throws -> String {
        let response: APIEnvelope<EmptyPayload> = try await post(path, body: body)
        guard response.success else { throw APIError.server(response.message) }
        return response.message
    }

    func getUserProfile() async throws -> UserProfile {
        let sessdata = try readSessdata()
        guard let url = URL(string: "https://api.bilibili.com/x/space/myinfo") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("SESSDATA=\(sessdata)", forHTTPHeaderField: "Cookie")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw APIError.invalidResponse
        }

        let envelope = try JSONDecoder().decode(BilibiliEnvelope<UserProfile>.self, from: data)
        guard envelope.code == 0 else {
            throw APIError.server(envelope.message)
        }
        guard let profile = envelope.data else {
            throw APIError.invalidResponse
        }
        return profile
    }

    private func makeRequest(path: String, query: [URLQueryItem] = []) throws -> URLRequest {
        let url = baseURL.appendingPathComponent(path)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        if !query.isEmpty { components.queryItems = query }
        guard let finalURL = components.url else { throw APIError.invalidURL }
        return URLRequest(url: finalURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
    }

    private func decode<Value: Decodable>(_ request: URLRequest) async throws -> APIEnvelope<Value> {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw APIError.invalidResponse
        }
        do {
            return try JSONDecoder().decode(APIEnvelope<Value>.self, from: data)
        } catch {
            throw APIError.server("数据解析失败：\(error.localizedDescription)")
        }
    }

    private func readSessdata() throws -> String {
        let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Bilidown", isDirectory: true)
        let databaseURL = supportDirectory.appendingPathComponent("data.db")
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw APIError.server("尚未找到登录信息")
        }

        let output = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [databaseURL.path, "SELECT value FROM field WHERE name = 'sessdata' LIMIT 1;"]
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw APIError.server("读取登录信息失败")
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let sessdata = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sessdata.isEmpty else {
            throw APIError.server("当前账户尚未登录")
        }
        return sessdata
    }
}

private struct BilibiliEnvelope<Value: Decodable>: Decodable {
    let code: Int
    let message: String
    let data: Value?
}
