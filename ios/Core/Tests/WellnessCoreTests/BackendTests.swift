import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import WellnessCore

private final class MemoryVault: SessionVault, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Session?
    func load() throws -> Session? { lock.lock(); defer { lock.unlock() }; return value }
    func save(_ session: Session) throws { lock.lock(); defer { lock.unlock() }; value = session }
    func clear() throws { lock.lock(); defer { lock.unlock() }; value = nil }
}
private final class MockProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, String)
    private static let lock = NSLock()
    private static var handlers: [String: Handler] = [:]
    static func install(host: String, handler: @escaping Handler) { lock.lock(); defer { lock.unlock() }; handlers[host] = handler }
    static func remove(host: String) { lock.lock(); defer { lock.unlock() }; handlers[host] = nil }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); let handler = Self.handlers[request.url!.host!]; Self.lock.unlock()
        do {
            let (status, body) = try XCTUnwrap(handler)(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

private func requestBody(_ request: URLRequest) throws -> Data {
    if let data = request.httpBody { return data }
    let stream = try XCTUnwrap(request.httpBodyStream); stream.open(); defer { stream.close() }
    var data = Data(); var buffer = [UInt8](repeating: 0, count: 1024)
    while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count < 0 { throw BackendError.invalidResponse }; if count == 0 { break }; data.append(contentsOf: buffer.prefix(count)) }
    return data
}

final class BackendTests: XCTestCase {
    private let owner = "11111111-1111-4111-8111-111111111111"
    private let member = "member-one"
    private func backend(vault: MemoryVault = MemoryVault(), handler: @escaping MockProtocol.Handler) throws -> Backend {
        let host = UUID().uuidString.lowercased() + ".example.test"
        MockProtocol.install(host: host, handler: handler)
        addTeardownBlock { MockProtocol.remove(host: host) }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockProtocol.self]
        return try Backend(root: URL(string: "https://\(host)")!, publicKey: "sb_publishable_test", vault: vault, network: URLSession(configuration: config))
    }
    func testPINUsesExistingEndpointAndOwnerComesFromVerifiedUser() async throws {
        let owner = owner, member = member, vault = MemoryVault()
        let api = try backend(vault: vault) { request in
            switch request.url!.path {
            case "/functions/v1/pin-login":
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "sb_publishable_test")
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                let body = try JSONDecoder().decode(JSONValue.self, from: requestBody(request))
                XCTAssertEqual(body["pin"], .string("1234"))
                return (200, "{\"memberId\":\"\(member)\",\"access_token\":\"access\",\"refresh_token\":\"refresh\"}")
            case "/auth/v1/user": return (200, "{\"id\":\"\(owner)\"}")
            case "/rest/v1/members": return (200, "[{\"id\":\"\(member)\"}]")
            default: XCTFail("Unexpected request"); return (500, "{}")
            }
        }
        let session = try await api.login(pin: "1234")
        XCTAssertEqual(session.owner, owner)
        XCTAssertEqual(try vault.load()?.refreshToken, "refresh")
        let serialized = String(data: try JSONEncoder().encode(try XCTUnwrap(vault.load())), encoding: .utf8)!
        XCTAssertFalse(serialized.contains("1234"))
    }
    func testRefreshRotatesAndKeepsOwnerFilter() async throws {
        let owner = owner, vault = MemoryVault()
        try vault.save(Session(accessToken: "expired", refreshToken: "old", owner: owner, member: member))
        let api = try backend(vault: vault) { request in
            if request.url!.path == "/auth/v1/token" {
                XCTAssertTrue(request.url!.query!.contains("grant_type=refresh_token"))
                return (200, "{\"access_token\":\"fresh\",\"refresh_token\":\"rotated\"}")
            }
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer expired" { return (401, "{}") }
            if request.url!.path == "/auth/v1/user" { return (200, "{\"id\":\"\(owner)\"}") }
            XCTAssertTrue(request.url!.absoluteString.contains("owner_user_id=eq.\(owner)"))
            return (200, "[]")
        }
        let restored = try await api.restore()
        XCTAssertEqual(restored?.refreshToken, "rotated")
        let rows = try await api.rows(table: "meals", owner: owner)
        XCTAssertTrue(rows.isEmpty)
        XCTAssertEqual(try vault.load()?.refreshToken, "rotated")
    }
    func testCannotReadAnotherOwnerOrReturnForeignRows() async throws {
        let owner = owner, vault = MemoryVault(), foreign = "33333333-3333-4333-8333-333333333333"
        try vault.save(Session(accessToken: "token", refreshToken: "refresh", owner: owner, member: member))
        let api = try backend(vault: vault) { request in
            if request.url!.path == "/auth/v1/user" { return (200, "{\"id\":\"\(owner)\"}") }
            return (200, "[{\"id\":\"meal\",\"owner_user_id\":\"\(foreign)\",\"version\":1,\"data\":{}}]")
        }
        _ = try await api.restore()
        do { _ = try await api.rows(table: "meals", owner: foreign); XCTFail("Foreign owner accepted") }
        catch { XCTAssertEqual(error as? BackendError, .sessionRequired) }
        do { _ = try await api.rows(table: "meals", owner: owner); XCTFail("Foreign row accepted") }
        catch { XCTAssertEqual(error as? BackendError, .sessionChanged) }
    }
    func testLogoutClearsLocalSessionAndOnlyRevokesThisSession() async throws {
        let owner = owner, vault = MemoryVault()
        try vault.save(Session(accessToken: "token", refreshToken: "refresh", owner: owner, member: member))
        let api = try backend(vault: vault) { request in
            if request.url!.path == "/auth/v1/user" { return (200, "{\"id\":\"\(owner)\"}") }
            XCTAssertEqual(request.url!.path, "/auth/v1/logout")
            XCTAssertEqual(request.url!.query, "scope=local")
            return (204, "")
        }
        _ = try await api.restore(); await api.signOut()
        XCTAssertNil(try vault.load())
        do { _ = try await api.rows(table: "meals", owner: owner); XCTFail("Session survived logout") }
        catch { XCTAssertEqual(error as? BackendError, .sessionRequired) }
    }
    func testRetriedImportIsIdempotentAndDeletedRowRestoresWithVersionGuard() async throws {
        let owner = owner, vault = MemoryVault()
        let id = "44444444-4444-8444-8444-444444444444", source = "22222222-2222-4222-8222-222222222222"
        try vault.save(Session(accessToken: "token", refreshToken: "refresh", owner: owner, member: member))
        let api = try backend(vault: vault) { request in
            if request.url!.path == "/auth/v1/user" { return (200, "{\"id\":\"\(owner)\"}") }
            if request.httpMethod == "POST" {
                let body = try JSONDecoder().decode(JSONValue.self, from: requestBody(request))
                XCTAssertEqual(body["id"], .string(id)); XCTAssertEqual(body["owner_user_id"], .string(owner))
                return (409, "{}")
            }
            if request.httpMethod == "PATCH" {
                let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
                XCTAssertTrue(query.contains(URLQueryItem(name: "version", value: "eq.7")))
                XCTAssertTrue(query.contains(URLQueryItem(name: "owner_user_id", value: "eq.\(owner)")))
                let body = try JSONDecoder().decode(JSONValue.self, from: requestBody(request))
                XCTAssertEqual(body["deleted_at"], .null)
                XCTAssertEqual(body["data"], .null) // Existing user edits must not be overwritten.
                return (200, "[{\"id\":\"\(id)\"}]")
            }
            return (200, "[{\"id\":\"\(id)\",\"owner_user_id\":\"\(owner)\",\"version\":7,\"deleted_at\":\"2026-11-15T10:00:00Z\",\"data\":{\"appleHealth\":{\"uuid\":\"\(source)\"}}}]")
        }
        _ = try await api.restore()
        let payload: JSONValue = .object(["appleHealth": .object(["uuid": .string(source)])])
        try await api.insertImportedWorkout(id: id, owner: owner, payload: payload)
        try await api.insertImportedWorkout(id: id, owner: owner, payload: payload)
    }
    func testForeignPhotosAreRejectedBeforeSigningOrDownloading() async throws {
        let api = try backend { _ in XCTFail("Must not send any request"); return (500, "{}") }
        for path in ["another-owner/photo.jpg", "\(owner)/../photo.jpg", "\(owner)/%2e%2e/photo.jpg"] {
            do { _ = try await api.imageData(path: path, owner: owner); XCTFail("Unsafe path accepted") }
            catch { XCTAssertEqual(error as? BackendError, .invalidResponse) }
        }
    }
    func testFailedAccountSwitchCannotRestorePreviousSession() async throws {
        let vault = MemoryVault()
        try vault.save(Session(accessToken: "previous", refreshToken: "previous", owner: owner, member: member))
        let api = try backend(vault: vault) { request in
            XCTAssertEqual(request.url!.path, "/functions/v1/pin-login")
            return (200, "{\"error\":\"invalid_pin\"}")
        }
        do { _ = try await api.login(pin: "0000"); XCTFail("Invalid PIN accepted") }
        catch { XCTAssertEqual(error as? BackendError, .invalidPIN) }
        XCTAssertNil(try vault.load())
        let restored = try await api.restore(); XCTAssertNil(restored)
    }
    func testRateLimitIsReportedWithoutTreatingItAsWrongPIN() async throws {
        let api = try backend { _ in (200, "{\"error\":\"rate_limited\"}") }
        do { _ = try await api.login(pin: "0000"); XCTFail("Rate limit ignored") }
        catch { XCTAssertEqual(error as? BackendError, .rateLimited) }
    }
    func testPrivilegedOrPlaceholderClientKeysAreRejected() {
        for key in ["sb_secret_test", "CONFIGURE_PUBLIC_KEY", "", "header.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.signature"] {
            XCTAssertThrowsError(try Backend(root: URL(string: "https://example.test")!, publicKey: key, vault: MemoryVault()))
        }
    }

    private func signedInBackend(handler: @escaping MockProtocol.Handler) async throws -> Backend {
        let owner = owner, member = member, vault = MemoryVault()
        try vault.save(Session(accessToken: "access", refreshToken: "refresh", owner: owner, member: member))
        let api = try backend(vault: vault, handler: handler)
        _ = try await api.restore()
        return api
    }
    func testSaveInsertsWithOwnerAndMutationIdAndUpdatesWithVersionGuard() async throws {
        let owner = owner
        var seen: [(String, String, String?)] = []
        let lock = NSLock()
        let api = try await signedInBackend { request in
            lock.lock(); seen.append((request.httpMethod ?? "", request.url!.path, request.url!.query)); lock.unlock()
            if request.url!.path == "/auth/v1/user" { return (200, "{\"id\":\"\(owner)\"}") }
            let body = try String(data: requestBody(request), encoding: .utf8) ?? ""
            if request.httpMethod == "POST" {
                XCTAssertTrue(body.contains("\"owner_user_id\":\"\(owner)\"")); XCTAssertTrue(body.contains("last_mutation_id"))
                return (201, "[{\"id\":\"22222222-2222-4222-8222-222222222222\",\"owner_user_id\":\"\(owner)\",\"version\":1,\"data\":{\"amount\":250},\"deleted_at\":null}]")
            }
            XCTAssertTrue(request.url!.query!.contains("version=eq.1")); XCTAssertTrue(body.contains("\"version\":2"))
            return (200, "[{\"id\":\"22222222-2222-4222-8222-222222222222\",\"owner_user_id\":\"\(owner)\",\"version\":2,\"data\":{\"amount\":500},\"deleted_at\":null}]")
        }
        let first = try await api.save(table: "water_logs", owner: owner, payload: .object(["amount": .number(250)]))
        XCTAssertEqual(first.version, 1)
        let second = try await api.save(table: "water_logs", owner: owner, payload: .object(["amount": .number(500)]), existing: first)
        XCTAssertEqual(second.version, 2)
    }
    func testSaveRejectsUnknownTablesAndForeignRowsAndMapsConflict() async throws {
        let owner = owner
        let api = try await signedInBackend { request in
            if request.url!.path == "/auth/v1/user" { return (200, "{\"id\":\"\(owner)\"}") }
            return (200, "[]")
        }
        do { _ = try await api.save(table: "members", owner: owner, payload: .null); XCTFail("must reject") } catch { XCTAssertEqual(error as? BackendError, .invalidResponse) }
        let foreign = try JSONDecoder().decode(HealthRow.self, from: Data("{\"id\":\"22222222-2222-4222-8222-222222222222\",\"owner_user_id\":\"someone-else\",\"version\":1,\"data\":{},\"deleted_at\":null}".utf8))
        do { _ = try await api.save(table: "meals", owner: owner, payload: .null, existing: foreign); XCTFail("must reject") } catch { XCTAssertEqual(error as? BackendError, .invalidResponse) }
        let mine = try JSONDecoder().decode(HealthRow.self, from: Data("{\"id\":\"22222222-2222-4222-8222-222222222222\",\"owner_user_id\":\"\(owner)\",\"version\":1,\"data\":{},\"deleted_at\":null}".utf8))
        do { _ = try await api.save(table: "meals", owner: owner, payload: .null, existing: mine); XCTFail("empty result means a concurrent edit") } catch { XCTAssertEqual(error as? BackendError, .conflict) }
        do { try await api.softDelete(table: "meals", row: mine, owner: owner); XCTFail("empty result means a concurrent edit") } catch { XCTAssertEqual(error as? BackendError, .conflict) }
    }
    func testInvokeOnlyCallsKnownFunctionsAndSurfacesFunctionErrors() async throws {
        let owner = owner
        let api = try await signedInBackend { request in
            if request.url!.path == "/auth/v1/user" { return (200, "{\"id\":\"\(owner)\"}") }
            XCTAssertEqual(request.url!.path, "/functions/v1/food-lookup")
            return (200, request.url!.absoluteString.isEmpty ? "" : "{\"foods\":[]}")
        }
        let ok = try await api.invoke("food-lookup", body: .object(["query": .string("חלב")]), owner: owner)
        XCTAssertEqual(ok["foods"], .array([]))
        do { _ = try await api.invoke("pin-login", body: .null, owner: owner); XCTFail("must reject") } catch { XCTAssertEqual(error as? BackendError, .invalidResponse) }
    }
    func testUploadImageSendsJPEGToOwnerFolderAndRejectsNonJPEG() async throws {
        let owner = owner
        var uploaded: (path: String, type: String?, size: Int)?
        let lock = NSLock()
        let api = try await signedInBackend { request in
            if request.url!.path == "/auth/v1/user" { return (200, "{\"id\":\"\(owner)\"}") }
            lock.lock(); uploaded = (request.url!.path, request.value(forHTTPHeaderField: "Content-Type"), try requestBody(request).count); lock.unlock()
            return (200, "{\"Key\":\"ok\"}")
        }
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3])
        let path = try await api.uploadImage(jpeg, owner: owner)
        XCTAssertTrue(path.hasPrefix(owner + "/") && path.hasSuffix(".jpg"))
        XCTAssertEqual(uploaded?.path, "/storage/v1/object/health-images/" + path)
        XCTAssertEqual(uploaded?.type, "image/jpeg"); XCTAssertEqual(uploaded?.size, jpeg.count)
        do { _ = try await api.uploadImage(Data([1, 2, 3]), owner: owner); XCTFail("must reject non-JPEG") } catch { XCTAssertEqual(error as? BackendError, .invalidResponse) }
        do { _ = try await api.uploadImage(Data(), owner: owner); XCTFail("must reject empty") } catch { XCTAssertEqual(error as? BackendError, .invalidResponse) }
    }
    func testCalendarFeedURLUsesFunctionsHost() async throws {
        let owner = owner
        let api = try await signedInBackend { request in request.url!.path == "/auth/v1/user" ? (200, "{\"id\":\"\(owner)\"}") : (200, "{}") }
        if let url = api.calendarFeedURL { XCTAssertTrue(url.absoluteString.hasSuffix(".functions.supabase.co/calendar-feed") && url.scheme == "https") }
    }
    func testMemberProfileUpdateAndAvatarUploadAreGuarded() async throws {
        let owner = owner
        var seen: [String] = []
        let lock = NSLock()
        let api = try await signedInBackend { request in
            if request.url!.path == "/auth/v1/user" { return (200, "{\"id\":\"\(owner)\"}") }
            lock.lock(); seen.append("\(request.httpMethod ?? "") \(request.url!.path)?\(request.url!.query ?? "")"); lock.unlock()
            return (200, "{}")
        }
        let id = "22222222-2222-4222-8222-222222222222"
        try await api.updateMemberProfile(id: id, owner: owner, fields: ["display_name": .string("חיים"), "color": .string("#E8A02E")])
        XCTAssertTrue(seen.contains { $0.hasPrefix("PATCH /rest/v1/members?id=eq.\(id)") })
        do { try await api.updateMemberProfile(id: id, owner: owner, fields: ["pin": .string("1234")]); XCTFail("pin must not be writable") } catch { XCTAssertEqual(error as? BackendError, .invalidResponse) }
        let url = try await api.uploadAvatar(Data([0xFF, 0xD8, 0xFF, 0x00]), memberID: id, owner: owner)
        XCTAssertTrue(url.contains("/storage/v1/object/public/avatars/\(id)/") && url.hasPrefix("https://"))
        do { _ = try await api.uploadAvatar(Data([1, 2, 3]), memberID: id, owner: owner); XCTFail("non-JPEG must be rejected") } catch { XCTAssertEqual(error as? BackendError, .invalidResponse) }
    }
    func testAttachmentsAreUploadedSignedAndDeletedWithGuards() async throws {
        let owner = owner
        var seen: [String] = []
        let lock = NSLock()
        let api = try await signedInBackend { request in
            if request.url!.path == "/auth/v1/user" { return (200, "{\"id\":\"\(owner)\"}") }
            lock.lock(); seen.append("\(request.httpMethod ?? "") \(request.url!.path)?\(request.url!.query ?? "")"); lock.unlock()
            if request.url!.path.contains("/object/sign/") { return (200, "{\"signedURL\":\"/object/sign/attachments/p/x.pdf?token=t\"}") }
            return (200, "{}")
        }
        let parent = "22222222-2222-4222-8222-222222222222"
        try await api.uploadAttachment(Data([1, 2]), path: "\(parent)/abc-חשבון.pdf", mimeType: "application/pdf", owner: owner)
        XCTAssertTrue(seen.contains { $0.hasPrefix("POST /storage/v1/object/attachments/\(parent)/") })
        for bad in ["../x/y.pdf", "a/b/c.pdf", "/abs/x.pdf", "\(parent)/x?.pdf", "noslash.pdf"] {
            do { try await api.uploadAttachment(Data([1]), path: bad, mimeType: "image/png", owner: owner); XCTFail("\(bad) must be rejected") } catch { XCTAssertEqual(error as? BackendError, .invalidResponse) }
        }
        let url = try await api.signedAttachmentURL(path: "\(parent)/x.pdf", owner: owner)
        XCTAssertEqual(url.scheme, "https"); XCTAssertTrue(url.path.contains("/storage/v1/object/sign/attachments/"))
        try await api.deleteAttachment(id: parent, path: "\(parent)/x.pdf", owner: owner)
        XCTAssertTrue(seen.contains { $0.hasPrefix("DELETE /storage/v1/object/attachments/") } && seen.contains { $0.hasPrefix("DELETE /rest/v1/attachments?id=eq.") })
    }
    func testHouseholdAccessIsAllowListedPagedAndGuarded() async throws {
        let owner = owner
        var seen: [String] = []
        let lock = NSLock()
        let api = try await signedInBackend { request in
            if request.url!.path == "/auth/v1/user" { return (200, "{\"id\":\"\(owner)\"}") }
            lock.lock(); seen.append("\(request.httpMethod ?? "") \(request.url!.path)?\(request.url!.query ?? "")"); lock.unlock()
            if request.url!.path.hasSuffix("/rpc/complete_chore") { return (204, "") }
            if request.httpMethod == "PATCH" { return (200, "[{\"id\":\"22222222-2222-4222-8222-222222222222\",\"title\":\"x\"}]") }
            if request.httpMethod == "POST" { return (201, "[{\"id\":\"22222222-2222-4222-8222-222222222222\"}]") }
            return (200, "[{\"id\":\"a\"},{\"id\":\"b\"}]")
        }
        let rows = try await api.householdRows(table: "tasks", owner: owner, filters: [.init(name: "section_id", value: "eq.s1")], order: "position.asc")
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(seen.contains { $0.contains("deleted_at=is.null") && $0.contains("section_id=eq.s1") && $0.contains("order=position.asc") }, "soft-deleted rows must be excluded")
        _ = try await api.householdRows(table: "members", owner: owner, columns: "id,display_name", order: "display_name.asc")
        XCTAssertTrue(seen.contains { $0.contains("/members?") && $0.contains("select=id,display_name") || $0.contains("/members?") && $0.contains("select=id%2Cdisplay_name") }, "members must not select the protected pin column")
        let id = "22222222-2222-4222-8222-222222222222"
        _ = try await api.householdInsert(table: "tasks", owner: owner, fields: ["id": .string(id), "title": .string("חלב")])
        _ = try await api.householdUpdate(table: "tasks", owner: owner, id: id, fields: ["is_completed": .bool(true)])
        try await api.householdRPC("complete_chore", owner: owner, args: ["p_chore_id": .string(id), "p_completed_by": .string(id)])
        for table in ["members", "activity_log", "push_subscriptions", "health_profiles"] {
            do { _ = try await api.householdInsert(table: table, owner: owner, fields: ["id": .string(id)]); XCTFail("\(table) must not be writable") } catch { XCTAssertEqual(error as? BackendError, .invalidResponse) }
        }
        do { _ = try await api.householdRows(table: "push_subscriptions", owner: owner); XCTFail("must not be readable") } catch { XCTAssertEqual(error as? BackendError, .invalidResponse) }
        do { _ = try await api.householdUpdate(table: "tasks", owner: owner, id: "not-a-uuid", fields: ["title": .string("x")]); XCTFail("bad id") } catch { XCTAssertEqual(error as? BackendError, .invalidResponse) }
        do { try await api.householdRPC("drop_everything", owner: owner, args: [:]); XCTFail("unknown rpc") } catch { XCTAssertEqual(error as? BackendError, .invalidResponse) }
    }
}
