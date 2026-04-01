import Foundation

/// Filters and flags dangerous commands from remote input.
/// All remote input requires Mac-side confirmation for safety.
struct DangerousCommandFilter: Sendable {
    /// High-risk patterns that always require explicit confirmation
    private static let highRiskPatterns: [String] = [
        "rm -rf",
        "rm -r /",
        "sudo rm",
        "mkfs",
        "dd if=",
        "> /dev/",
        "chmod -R 777",
        "curl | sh",
        "curl | bash",
        "wget | sh",
        ":(){:|:&};:",       // fork bomb
        "shutdown",
        "reboot",
        "halt",
    ]

    /// Check if a command is high-risk
    static func isDangerous(_ input: String) -> Bool {
        let lowered = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return highRiskPatterns.contains { lowered.contains($0) }
    }

    /// Get reason why command was flagged
    static func flagReason(_ input: String) -> String? {
        let lowered = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for pattern in highRiskPatterns {
            if lowered.contains(pattern) {
                return "Contains high-risk command: \(pattern)"
            }
        }
        return nil
    }
}
