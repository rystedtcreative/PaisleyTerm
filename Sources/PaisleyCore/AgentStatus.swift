import Foundation

/// Live state of a coding agent, inferred from its terminal output.
///
/// Platform-agnostic: the SwiftUI `Color` / SF Symbol mappings live in the
/// macOS app target as an extension so this type has no UI dependency and
/// compiles on Linux.
public enum AgentStatus: Equatable {
    case inactive
    case idle
    case thinking
    case executing
    case waiting
    case complete
    case error(String)

    public var displayName: String {
        switch self {
        case .inactive:  return "inactive"
        case .idle:      return "idle"
        case .thinking:  return "thinking"
        case .executing: return "executing"
        case .waiting:   return "waiting"
        case .complete:  return "complete"
        case .error:     return "error"
        }
    }

    public var sortPriority: Int {
        switch self {
        case .thinking:  return 0
        case .executing: return 1
        case .waiting:   return 2
        case .idle:      return 3
        case .complete:  return 4
        case .error:     return 5
        case .inactive:  return 6
        }
    }
}

public enum AgentType: String, CaseIterable {
    case claudeCode  = "claude"
    case openCode = "opencode"

    public var displayName: String {
        switch self {
        case .claudeCode:  return "Claude Code"
        case .openCode: return "OpenCode"
        }
    }

    public var launchCommand: String { rawValue }

    public var installCommand: String {
        switch self {
        case .claudeCode: return "curl -fsSL https://claude.ai/install.sh | bash"
        case .openCode:   return "curl -fsSL https://opencode.ai/install | bash"
        }
    }

    public var pathExportLine: String {
        switch self {
        case .claudeCode: return #"export PATH="$HOME/.local/bin:$PATH""#
        case .openCode:   return #"export PATH="$HOME/.opencode/bin:$PATH""#
        }
    }
}
