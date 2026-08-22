import Foundation
import Supabase

enum SupabaseConfigError: LocalizedError {
    case missingURL
    case missingKey

    var errorDescription: String? {
        switch self {
        case .missingURL: return "SUPABASE_URL is missing — copy Config/Secrets.xcconfig.example to Secrets.xcconfig and fill it in."
        case .missingKey: return "SUPABASE_ANON_KEY is missing — copy Config/Secrets.xcconfig.example to Secrets.xcconfig and fill it in."
        }
    }
}

/// Wraps the Supabase Swift client and makes sure every request carries the
/// `x-device-id` header the backend's RLS policies key off (see
/// ios/backend/migrations/0002_access_control.sql). This is a *separate*
/// Supabase project from the website's — its URL/anon key live only in this
/// app's Secrets.xcconfig, never in the Next.js app's .env.
enum SupabaseService {
    static let shared: SupabaseClient = {
        do {
            return try makeClient()
        } catch {
            fatalError("Yachad Supabase config error: \(error.localizedDescription)")
        }
    }()

    private static func makeClient() throws -> SupabaseClient {
        guard
            let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            !urlString.isEmpty,
            !urlString.contains("YOUR-PROJECT-REF"),
            let url = URL(string: urlString)
        else {
            throw SupabaseConfigError.missingURL
        }
        guard
            let anonKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
            !anonKey.isEmpty,
            anonKey != "YOUR_ANON_PUBLIC_KEY"
        else {
            throw SupabaseConfigError.missingKey
        }

        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: anonKey,
            options: SupabaseClientOptions(
                global: SupabaseClientOptions.GlobalOptions(
                    headers: ["x-device-id": DeviceIdentity.shared.id.uuidString.lowercased()]
                )
            )
        )
    }
}
