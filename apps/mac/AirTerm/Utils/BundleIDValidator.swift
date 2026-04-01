import Foundation
import AppKit

/// Validates that AX API operations only target known terminal applications.
/// Prevents reading from or writing to non-terminal windows (security boundary).
struct BundleIDValidator: Sendable {

    /// Allowed terminal bundle IDs for AX API read/write
    private static let allowedBundleIds: Set<String> = ProcessMonitor.terminalBundleIds

    /// Check if a bundle ID is an allowed terminal application
    static func isAllowed(_ bundleId: String) -> Bool {
        allowedBundleIds.contains(bundleId)
    }

    /// Validate before reading from a window
    static func validateRead(bundleId: String) -> Result<Void, ValidationError> {
        guard isAllowed(bundleId) else {
            return .failure(.disallowedApplication(bundleId))
        }
        return .success(())
    }

    /// Validate before writing/injecting input to a window
    static func validateWrite(bundleId: String) -> Result<Void, ValidationError> {
        guard isAllowed(bundleId) else {
            return .failure(.disallowedApplication(bundleId))
        }
        return .success(())
    }

    /// Validate a running application by its PID
    static func validatePid(_ pid: pid_t) -> Result<String, ValidationError> {
        guard let app = NSRunningApplication(processIdentifier: pid),
              let bundleId = app.bundleIdentifier else {
            return .failure(.unknownProcess(pid))
        }

        guard isAllowed(bundleId) else {
            return .failure(.disallowedApplication(bundleId))
        }

        return .success(bundleId)
    }

    enum ValidationError: Error, LocalizedError {
        case disallowedApplication(String)
        case unknownProcess(pid_t)

        var errorDescription: String? {
            switch self {
            case .disallowedApplication(let id):
                return "Application '\(id)' is not in the terminal whitelist"
            case .unknownProcess(let pid):
                return "Cannot determine bundle ID for PID \(pid)"
            }
        }
    }
}
