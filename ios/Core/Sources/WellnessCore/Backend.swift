import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct Session: Codable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let owner: String
    public let member: String
    public init(accessToken: String, refreshToken: String, owner: String, member: String) {
        self.accessToken = accessToken; self.refreshToken = refreshToken; self.owner = owner; self.member = member
    }
}

public protocol SessionVault: Sendable {
    func load() throws -> Session?
    func save(_ session: Session) throws
    func clear() throws
}

public enum BackendError: Error, Equatable {
    case configuration, invalidPIN, rateLimited, sessionRequired, sessionChanged, connection, server(Int), invalidResponse, conflict
}

public actor Backend {
    private let root: URL
    private let key: String
    private let vault: any SessionVault
    private let network: URLSession
    private var current: Session?
    private var generation = 0
    private var refreshTask: Task<Session, Error>?
    private var refreshAttempt: UUID?
    public init(root: URL, publicKey: String, vault: any SessionVault, network: URLSession? = nil) throws {
        guard root.scheme == "https", root.host != nil, root.user == nil, root.password == nil,
              !publicKey.isEmpty, !publicKey.hasPrefix("sb_secret_"), publicKey != "CONFIGURE_PUBLIC_KEY" else { throw BackendError.configuration }
        if !publicKey.hasPrefix("sb_publishable_") {
            let parts = publicKey.split(separator: ".")
            guard parts.count == 3 else { throw BackendError.configuration }
            var encoded = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
            guard let data = Data(base64Encoded: encoded),
                  let claims = try? JSONDecoder().decode(JSONValue.self, from: data), claims["role"] == .string("anon") else { throw BackendError.configuration }
        }
        self.root = root; key = publicKey; self.vault = vault
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.network = network ?? URLSession(configuration: config)
    }
    private func raw(_ path: String, method: String = "GET", token: String? = nil, body: JSONValue? = nil, query: [URLQueryItem] = [], binary: (Data, String)? = nil) async throws -> (Data, Int) {
        var parts = URLComponents(url: root, resolvingAgainstBaseURL: false)!
        parts.path = path; parts.queryItems = query.isEmpty ? nil : query; parts.fragment = nil
        guard let url = parts.url else { throw BackendError.configuration }
        var req = URLRequest(url: url); req.httpMethod = method; req.timeoutInterval = 20
        req.setValue(key, forHTTPHeaderField: "apikey"); req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("return=representation", forHTTPHeaderField: "Prefer")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        else if key.split(separator: ".").count == 3 { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = try JSONEncoder().encode(body) }
        if let binary { req.httpBody = binary.0; req.setValue(binary.1, forHTTPHeaderField: "Content-Type"); req.setValue("false", forHTTPHeaderField: "x-upsert") }
        do {
            let (data, response) = try await network.data(for: req)
            guard let response = response as? HTTPURLResponse else { throw BackendError.invalidResponse }
            return (data, response.statusCode)
        } catch is CancellationError { throw CancellationError() }
        catch let e as BackendError { throw e }
        catch { throw BackendError.connection }
    }
    private func json(_ data: Data) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: data) }
    public func login(pin: String) async throws -> Session {
        guard pin.count == 4, pin.allSatisfy({ $0.isASCII && $0.isNumber }) else { throw BackendError.invalidPIN }
        generation += 1; let attempt = generation
        refreshTask?.cancel(); refreshTask = nil; refreshAttempt = nil; current = nil
        try vault.clear()
        let (data, status) = try await raw("/functions/v1/pin-login", method: "POST", body: .object(["pin": .string(pin)]))
        let result = try json(data)
        if status == 429 || result["error"] == .string("rate_limited") { throw BackendError.rateLimited }
        guard status == 200 else { throw BackendError.server(status) }
        if let error = result["error"].stringValue, error != "invalid_pin" { throw BackendError.invalidResponse }
        guard status == 200, result["error"] == .null,
              let token = result["access_token"].stringValue, let refresh = result["refresh_token"].stringValue,
              let member = result["memberId"].stringValue else { throw BackendError.invalidPIN }
        let (userData, userStatus) = try await raw("/auth/v1/user", token: token)
        guard userStatus == 200, let owner = try json(userData)["id"].stringValue, UUID(uuidString: owner) != nil else { throw BackendError.sessionRequired }
        let (membersData, membersStatus) = try await raw("/rest/v1/members", token: token, query: [.init(name: "select", value: "id"), .init(name: "user_id", value: "eq.\(owner)")])
        guard membersStatus == 200, try json(membersData).arrayValue.contains(where: { $0["id"].stringValue == member }) else { throw BackendError.sessionChanged }
        guard attempt == generation else { throw BackendError.sessionChanged }
        let session = Session(accessToken: token, refreshToken: refresh, owner: owner, member: member)
        try vault.save(session); current = session; return session
    }
    public func restore() async throws -> Session? {
        guard let stored = try vault.load() else { return nil }
        current = stored
        let (data, status) = try await authorized("/auth/v1/user", expectedOwner: stored.owner)
        guard status == 200, try json(data)["id"].stringValue == stored.owner, let session = current else { throw BackendError.sessionChanged }
        return session
    }
    private func refreshed(_ old: Session) async throws -> Session {
        guard let active = current, active.owner == old.owner else { throw BackendError.sessionChanged }
        if active.refreshToken != old.refreshToken { return active }
        if let refreshTask { return try await refreshTask.value }
        let attempt = UUID()
        let task = Task { try await self.performRefresh(old) }; refreshTask = task; refreshAttempt = attempt
        defer { if refreshAttempt == attempt { refreshTask = nil; refreshAttempt = nil } }
        return try await task.value
    }
    private func performRefresh(_ old: Session) async throws -> Session {
        let (data, status) = try await raw("/auth/v1/token", method: "POST", body: .object(["refresh_token": .string(old.refreshToken)]), query: [.init(name: "grant_type", value: "refresh_token")])
        let result = try json(data)
        guard status == 200, let token = result["access_token"].stringValue, let refresh = result["refresh_token"].stringValue else { throw BackendError.sessionRequired }
        let (user, userStatus) = try await raw("/auth/v1/user", token: token)
        guard userStatus == 200, try json(user)["id"].stringValue == old.owner else { throw BackendError.sessionChanged }
        try Task.checkCancellation()
        guard current?.refreshToken == old.refreshToken else { throw BackendError.sessionChanged }
        let session = Session(accessToken: token, refreshToken: refresh, owner: old.owner, member: old.member)
        try vault.save(session); current = session; return session
    }
    private func authorized(_ path: String, method: String = "GET", expectedOwner: String, body: JSONValue? = nil, query: [URLQueryItem] = [], binary: (Data, String)? = nil) async throws -> (Data, Int) {
        guard var session = current, session.owner == expectedOwner else { throw BackendError.sessionRequired }
        var result = try await raw(path, method: method, token: session.accessToken, body: body, query: query, binary: binary)
        if result.1 == 401 {
            session = try await refreshed(session)
            result = try await raw(path, method: method, token: session.accessToken, body: body, query: query, binary: binary)
        }
        guard current?.owner == expectedOwner else { throw BackendError.sessionChanged }
        return result
    }
    // MARK: - Household tables (shared, not owner-scoped: sections, tasks, chores, events, members)
    public static let householdReadable: Set<String> = ["sections", "tasks", "chores", "chore_completions", "family_events", "members", "activity_log"]
    public static let householdWritable: Set<String> = ["sections", "tasks", "chores", "family_events"]
    private static let householdRPCs: Set<String> = ["complete_chore"]

    /// Reads a household table, paging up to 10,000 rows. `deleted_at is null` is applied for tables that soft-delete.
    public func householdRows(table: String, owner: String, filters: [URLQueryItem] = [], order: String? = nil, limit: Int = 1000, singlePage: Bool = false) async throws -> [JSONValue] {
        guard Self.householdReadable.contains(table) else { throw BackendError.invalidResponse }
        let softDeletes: Set<String> = ["sections", "tasks", "chores", "family_events"]
        var rows: [JSONValue] = [], offset = 0
        while true {
            var query: [URLQueryItem] = [.init(name: "select", value: "*"), .init(name: "limit", value: String(limit)), .init(name: "offset", value: String(offset))] + filters
            if softDeletes.contains(table) { query.append(.init(name: "deleted_at", value: "is.null")) }
            if let order { query.append(.init(name: "order", value: order)) }
            let (data, status) = try await authorized("/rest/v1/\(table)", expectedOwner: owner, query: query)
            guard status == 200 else { throw BackendError.server(status) }
            let batch = try json(data).arrayValue
            rows += batch
            if singlePage || batch.count < limit { return rows }
            offset += limit; guard offset < 10_000 else { throw BackendError.invalidResponse }
        }
    }
    public func householdInsert(table: String, owner: String, fields: [String: JSONValue]) async throws -> JSONValue {
        guard Self.householdWritable.contains(table), fields["id"]?.stringValue.flatMap({ UUID(uuidString: $0) }) != nil else { throw BackendError.invalidResponse }
        let (data, status) = try await authorized("/rest/v1/\(table)", method: "POST", expectedOwner: owner, body: .object(fields))
        guard (200..<300).contains(status) else { throw BackendError.server(status) }
        guard let row = try json(data).arrayValue.first else { throw BackendError.invalidResponse }
        return row
    }
    /// Partial update by id. Soft delete is `deleted_at` set to a timestamp.
    public func householdUpdate(table: String, owner: String, id: String, fields: [String: JSONValue]) async throws -> JSONValue {
        guard Self.householdWritable.contains(table), UUID(uuidString: id) != nil, !fields.isEmpty, fields["id"] == nil else { throw BackendError.invalidResponse }
        let (data, status) = try await authorized("/rest/v1/\(table)", method: "PATCH", expectedOwner: owner, body: .object(fields), query: [.init(name: "id", value: "eq.\(id)")])
        guard (200..<300).contains(status) else { throw BackendError.server(status) }
        guard let row = try json(data).arrayValue.first else { throw BackendError.conflict }
        return row
    }
    public func householdRPC(_ name: String, owner: String, args: [String: JSONValue]) async throws {
        guard Self.householdRPCs.contains(name) else { throw BackendError.invalidResponse }
        let (_, status) = try await authorized("/rest/v1/rpc/\(name)", method: "POST", expectedOwner: owner, body: .object(args))
        guard (200..<300).contains(status) else { throw BackendError.server(status) }
    }

    public static let writableTables: Set<String> = ["meals", "water_logs", "weight_logs", "nutrition_goals", "health_profiles", "personal_foods", "recipes", "workout_plans", "workout_sessions"]
    private static let readableTables = writableTables
    private static let functions: Set<String> = ["food-lookup", "nutrition-analyze", "wellness-ai", "wellness-chat", "wellness-training"]

    /// Inserts (existing == nil) or updates with optimistic versioning, exactly like the web store.
    @discardableResult
    public func save(table: String, owner: String, payload: JSONValue, existing: HealthRow? = nil, id: String? = nil) async throws -> HealthRow {
        guard Self.writableTables.contains(table) else { throw BackendError.invalidResponse }
        let mutation = UUID().uuidString.lowercased()
        let data: Data, status: Int
        if let existing {
            guard existing.owner_user_id == owner, UUID(uuidString: existing.id) != nil else { throw BackendError.invalidResponse }
            let body: JSONValue = .object(["data": payload, "version": .number(Double(existing.version + 1)), "last_mutation_id": .string(mutation)])
            (data, status) = try await authorized("/rest/v1/\(table)", method: "PATCH", expectedOwner: owner, body: body,
                query: [.init(name: "id", value: "eq.\(existing.id)"), .init(name: "owner_user_id", value: "eq.\(owner)"), .init(name: "version", value: "eq.\(existing.version)")])
        } else {
            let rowID = (id ?? UUID().uuidString).lowercased()
            guard UUID(uuidString: rowID) != nil else { throw BackendError.invalidResponse }
            let body: JSONValue = .object(["id": .string(rowID), "owner_user_id": .string(owner), "data": payload, "last_mutation_id": .string(mutation)])
            (data, status) = try await authorized("/rest/v1/\(table)", method: "POST", expectedOwner: owner, body: body)
        }
        if status == 409 { throw BackendError.conflict }
        guard (200..<300).contains(status) else { throw BackendError.server(status) }
        let saved = try JSONDecoder().decode([HealthRow].self, from: data)
        guard saved.count == 1, saved[0].owner_user_id == owner else { throw BackendError.conflict }
        return saved[0]
    }

    /// Soft delete (sets deleted_at) guarded by the row version, so a concurrent edit is never lost.
    public func softDelete(table: String, row: HealthRow, owner: String) async throws {
        guard Self.writableTables.contains(table), row.owner_user_id == owner, UUID(uuidString: row.id) != nil else { throw BackendError.invalidResponse }
        let body: JSONValue = .object(["deleted_at": .string(ISO8601DateFormatter().string(from: Date())), "version": .number(Double(row.version + 1)), "last_mutation_id": .string(UUID().uuidString.lowercased())])
        let (data, status) = try await authorized("/rest/v1/\(table)", method: "PATCH", expectedOwner: owner, body: body,
            query: [.init(name: "id", value: "eq.\(row.id)"), .init(name: "owner_user_id", value: "eq.\(owner)"), .init(name: "version", value: "eq.\(row.version)"), .init(name: "deleted_at", value: "is.null")])
        guard (200..<300).contains(status) else { throw BackendError.server(status) }
        guard try json(data).arrayValue.count == 1 else { throw BackendError.conflict }
    }

    /// Calls one of the existing Supabase edge functions the web app uses.
    public func invoke(_ function: String, body: JSONValue, owner: String) async throws -> JSONValue {
        guard Self.functions.contains(function) else { throw BackendError.invalidResponse }
        let (data, status) = try await authorized("/functions/v1/\(function)", method: "POST", expectedOwner: owner, body: body)
        guard (200..<300).contains(status) else { throw BackendError.server(status) }
        let result = try json(data)
        if result["error"] != .null { throw BackendError.invalidResponse }
        return result
    }

    public func rows(table: String, owner: String, extra: [URLQueryItem] = [], includeDeleted: Bool = false) async throws -> [HealthRow] {
        guard Self.readableTables.contains(table) else { throw BackendError.invalidResponse }
        var rows: [HealthRow] = [], offset = 0
        while true {
            let query: [URLQueryItem] = [.init(name: "select", value: "*"), .init(name: "owner_user_id", value: "eq.\(owner)"), .init(name: "order", value: "id.asc"), .init(name: "limit", value: "500"), .init(name: "offset", value: String(offset))] + (includeDeleted ? [] : [.init(name: "deleted_at", value: "is.null")]) + extra
            let (data, status) = try await authorized("/rest/v1/\(table)", expectedOwner: owner, query: query)
            guard status == 200 else { throw BackendError.server(status) }
            let batch = try JSONDecoder().decode([HealthRow].self, from: data)
            guard batch.allSatisfy({ $0.owner_user_id == owner }) else { throw BackendError.sessionChanged }
            rows += batch
            if batch.count < 500 { return rows }
            offset += 500; guard offset < 10_000 else { throw BackendError.invalidResponse }
        }
    }
    public func insertImportedWorkout(id: String, owner: String, payload: JSONValue) async throws {
        guard UUID(uuidString: id) != nil else { throw BackendError.invalidResponse }
        let body: JSONValue = .object(["id": .string(id), "owner_user_id": .string(owner), "data": payload, "last_mutation_id": .string(id)])
        let (_, status) = try await authorized("/rest/v1/workout_sessions", method: "POST", expectedOwner: owner, body: body)
        if status == 409 {
            let existing = try await rows(table: "workout_sessions", owner: owner, extra: [.init(name: "id", value: "eq.\(id)")], includeDeleted: true)
            guard existing.count == 1, existing[0].data["appleHealth"]["uuid"] == payload["appleHealth"]["uuid"] else { throw BackendError.conflict }
            if existing[0].deleted_at != nil {
                // An explicit re-import restores the same row; it never overwrites edited data.
                let (restored, restoreStatus) = try await authorized("/rest/v1/workout_sessions", method: "PATCH", expectedOwner: owner,
                    body: .object(["deleted_at": .null, "last_mutation_id": .string(UUID().uuidString.lowercased())]),
                    query: [.init(name: "id", value: "eq.\(id)"), .init(name: "owner_user_id", value: "eq.\(owner)"), .init(name: "version", value: "eq.\(existing[0].version)")])
                guard (200..<300).contains(restoreStatus), try json(restored).arrayValue.count == 1 else { throw BackendError.conflict }
            }
        } else if !(200..<300).contains(status) { throw BackendError.server(status) }
    }
    public func removeImportedWorkout(_ row: HealthRow, owner: String) async throws {
        guard row.owner_user_id == owner, UUID(uuidString: row.id) != nil,
              let source = row.data["appleHealth"]["uuid"].stringValue, UUID(uuidString: source) != nil else { throw BackendError.invalidResponse }
        let date = ISO8601DateFormatter().string(from: Date())
        let body: JSONValue = .object(["deleted_at": .string(date), "last_mutation_id": .string(UUID().uuidString.lowercased())])
        let (data, status) = try await authorized("/rest/v1/workout_sessions", method: "PATCH", expectedOwner: owner, body: body,
            query: [.init(name: "id", value: "eq.\(row.id)"), .init(name: "owner_user_id", value: "eq.\(owner)"), .init(name: "version", value: "eq.\(row.version)"), .init(name: "deleted_at", value: "is.null")])
        guard (200..<300).contains(status) else { throw BackendError.server(status) }
        guard try json(data).arrayValue.count == 1 else { throw BackendError.conflict }
    }
    /// Uploads a prepared JPEG to the private health-images bucket under the owner's folder and returns its path.
    public func uploadImage(_ jpeg: Data, owner: String) async throws -> String {
        guard !jpeg.isEmpty, jpeg.count <= 5_242_880, jpeg.starts(with: [0xFF, 0xD8, 0xFF]) else { throw BackendError.invalidResponse }
        let path = "\(owner)/\(UUID().uuidString.lowercased()).jpg"
        let (_, status) = try await authorized("/storage/v1/object/health-images/\(path)", method: "POST", expectedOwner: owner, binary: (jpeg, "image/jpeg"))
        guard (200..<300).contains(status) else { throw BackendError.server(status) }
        return path
    }

    public func imageData(path: String, owner: String) async throws -> Data {
        guard path.count <= 500, path.hasPrefix(owner + "/"), !path.contains(".."),
              path.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-_/ .".contains($0)) }) else { throw BackendError.invalidResponse }
        let (data, status) = try await authorized("/storage/v1/object/sign/health-images/\(path)", method: "POST", expectedOwner: owner, body: .object(["expiresIn": .number(60)]))
        guard status == 200, let signed = try json(data)["signedURL"].stringValue,
              signed.hasPrefix("/object/sign/health-images/"), let url = URL(string: "/storage/v1" + signed, relativeTo: root)?.absoluteURL,
              url.scheme == "https", url.host == root.host else { throw BackendError.invalidResponse }
        let (image, response) = try await network.data(from: url)
        guard current?.owner == owner else { throw BackendError.sessionChanged }
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.mimeType?.hasPrefix("image/") == true, image.count <= 8 * 1024 * 1024 else { throw BackendError.invalidResponse }
        return image
    }
    public func signOut() async {
        let old = current; generation += 1; refreshTask?.cancel(); refreshTask = nil; refreshAttempt = nil; current = nil
        try? vault.clear()
        if let old { _ = try? await raw("/auth/v1/logout", method: "POST", token: old.accessToken, query: [.init(name: "scope", value: "local")]) }
    }
}
