import FirebaseAuth
import FirebaseCore
import FirebaseFunctions
import Foundation

/// Callable Cloud Functions client — uses **Firebase Functions SDK** so requests hit the same Firebase project as `GoogleService-Info.plist` (avoids stale code on an old hard-coded Cloud Run URL).
enum CallableTransport {
    private static let callableRegion = "us-central1"

    static func post(functionName: String, payload: [String: Any]) async throws -> Any {
        guard FirebaseApp.app()?.options.projectID != nil else {
            throw CommunityServiceError.invalidResponse
        }
        guard Auth.auth().currentUser != nil else {
            throw NSError(
                domain: "CommunityService",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Sign in again, then try joining."]
            )
        }
        _ = try await Auth.auth().currentUser?.getIDToken()
        let functions = Functions.functions(region: callableRegion)
        let callable = functions.httpsCallable(functionName)
        callable.timeoutInterval = 120
        AppDebugLog.log("CallableTransport.post: httpsCallable(\(functionName)) region=\(callableRegion)")
        do {
            return try await call(callable, functionName: functionName, payload: payload)
        } catch {
            // Cold-started / just-deployed functions can transiently reject a still-valid ID token on
            // their first invocation. One forced-refresh retry clears it instead of surfacing a false
            // "sign in again" (mirrors `UserService.fetchProfileOnceWithPermissionRetry`).
            guard isUnauthenticated(error), let user = Auth.auth().currentUser else {
                throw mapFirebaseCallableError(error)
            }
            AppDebugLog.log("CallableTransport.post: \(functionName) unauthenticated — forcing ID token refresh and retrying once")
            _ = try? await forceRefreshIDToken(user: user)
            do {
                return try await call(callable, functionName: functionName, payload: payload)
            } catch {
                throw mapFirebaseCallableError(error)
            }
        }
    }

    private static func call(_ callable: HTTPSCallable, functionName: String, payload: [String: Any]) async throws -> Any {
        let result = try await callable.call(payload)
        guard let dict = result.data as? [String: Any] else {
            throw CommunityServiceError.invalidResponse
        }
        AppDebugLog.log("CallableTransport.post: \(functionName) response keys=\(dict.keys.sorted())")
        return dict
    }

    /// Matches `UserService.forceRefreshIDToken` — this Firebase Auth SDK only exposes the
    /// completion-handler form of `getIDTokenForcingRefresh`, so it's wrapped manually.
    private static func forceRefreshIDToken(user: User) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            user.getIDTokenForcingRefresh(true) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// gRPC code 16 == UNAUTHENTICATED (matches `grpcCodeToCallableStatus` below).
    private static func isUnauthenticated(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == FunctionsErrorDomain && ns.code == 16
    }

    /// Maps Firebase callable errors to the same `CommunityService` NSError shape as the legacy HTTP parser.
    private static func mapFirebaseCallableError(_ error: Error) -> NSError {
        let ns = error as NSError
        if ns.domain == FunctionsErrorDomain {
            let message = ns.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            let status = grpcCodeToCallableStatus(ns.code)
            return errorFromCallablePayload([
                "status": status,
                "message": message.isEmpty ? "Request failed" : message,
            ])
        }
        return NSError(
            domain: "CommunityService",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: ns.localizedDescription]
        )
    }

    /// gRPC status codes as returned by `FunctionsErrorCode` / `NSError.code` for HTTPS callables.
    private static func grpcCodeToCallableStatus(_ code: Int) -> String {
        switch code {
        case 3: return "INVALID_ARGUMENT"
        case 5: return "NOT_FOUND"
        case 6: return "ALREADY_EXISTS"
        case 7: return "PERMISSION_DENIED"
        case 9: return "FAILED_PRECONDITION"
        case 16: return "UNAUTHENTICATED"
        default: return "INTERNAL"
        }
    }

    static func unwrapEnvelope(_ data: Any?) throws -> [String: Any] {
        guard let dict = data as? [String: Any],
              let ok = dict["ok"] as? Bool,
              ok,
              let inner = dict["data"] as? [String: Any]
        else {
            throw CommunityServiceError.invalidResponse
        }
        return inner
    }

    static func errorFromCallablePayload(_ err: [String: Any]) -> NSError {
        let status = (err["status"] as? String ?? "").uppercased()
        let message = err["message"] as? String ?? "Request failed"
        let domain = "CommunityService"
        switch status {
        case "FAILED_PRECONDITION":
            let trimmedFp = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return NSError(
                domain: domain,
                code: 400,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        trimmedFp.isEmpty ? "This request can’t be completed right now. Try again." : trimmedFp,
                ]
            )
        case "NOT_FOUND":
            // Never assume invite-only copy: brackets use NOT_FOUND for missing game definitions, etc.
            let trimmedNf = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return NSError(
                domain: domain,
                code: 404,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        trimmedNf.isEmpty ? "That invite code is not valid." : trimmedNf,
                ]
            )
        case "ALREADY_EXISTS":
            let trimmedAe = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return NSError(
                domain: domain,
                code: 409,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        trimmedAe.isEmpty ? "You’re already in this league." : trimmedAe,
                ]
            )
        case "INVALID_ARGUMENT":
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return NSError(
                    domain: domain,
                    code: 400,
                    userInfo: [NSLocalizedDescriptionKey: trimmed]
                )
            }
            return NSError(
                domain: domain,
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Check the information you entered and try again."]
            )
        case "UNAUTHENTICATED":
            return NSError(
                domain: domain,
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Sign in again, then try joining."]
            )
        case "PERMISSION_DENIED":
            return NSError(
                domain: domain,
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        default:
            return NSError(
                domain: domain,
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }

    static func mapCallableNetworkError(_ error: Error) -> Error {
        let ns = error as NSError
        if ns.domain == "CommunityService" { return error }
        if ns.domain == NSURLErrorDomain {
            return NSError(
                domain: ns.domain,
                code: ns.code,
                userInfo: [NSLocalizedDescriptionKey: "Network error. Check your connection and try again."]
            )
        }
        return error
    }
}
