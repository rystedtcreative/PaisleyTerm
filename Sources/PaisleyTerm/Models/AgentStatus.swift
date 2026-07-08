import Foundation
import SwiftUI

enum AgentStatus: Equatable {
    case inactive
    case idle
    case thinking
    case executing
    case waiting
    case complete
    case error(String)

    var displayName: String {
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

    // Dracula palette — inlined so this file has no cross-directory dependencies.
    var draculaColor: Color {
        switch self {
        case .inactive:  return Color(.sRGB, red: 0.384, green: 0.447, blue: 0.643) // #6272a4
        case .idle:      return Color(.sRGB, red: 0.314, green: 0.980, blue: 0.482) // #50fa7b
        case .thinking:  return Color(.sRGB, red: 0.945, green: 0.980, blue: 0.549) // #f1fa8c
        case .executing: return Color(.sRGB, red: 1.000, green: 0.722, blue: 0.424) // #ffb86c
        case .waiting:   return Color(.sRGB, red: 0.545, green: 0.914, blue: 0.992) // #8be9fd
        case .complete:  return Color(.sRGB, red: 0.314, green: 0.980, blue: 0.482) // #50fa7b
        case .error:     return Color(.sRGB, red: 1.000, green: 0.333, blue: 0.333) // #ff5555
        }
    }

    var sortPriority: Int {
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

    var sfSymbol: String {
        switch self {
        case .inactive:  return "circle.dotted"
        case .idle:      return "sparkle"
        case .thinking:  return "brain"
        case .executing: return "wand.and.stars"
        case .waiting:   return "hand.raised"
        case .complete:  return "checkmark.seal.fill"
        case .error:     return "exclamationmark.triangle.fill"
        }
    }
}

enum AgentType: String, CaseIterable {
    case claudeCode  = "claude"
    case openCode = "opencode"

    var displayName: String {
        switch self {
        case .claudeCode:  return "Claude Code"
        case .openCode: return "OpenCode"
        }
    }

    var launchCommand: String { rawValue }

    var installCommand: String {
        switch self {
        case .claudeCode: return "curl -fsSL https://claude.ai/install.sh | bash"
        case .openCode:   return "curl -fsSL https://opencode.ai/install | bash"
        }
    }

    var pathExportLine: String {
        switch self {
        case .claudeCode: return #"export PATH="$HOME/.local/bin:$PATH""#
        case .openCode:   return #"export PATH="$HOME/.opencode/bin:$PATH""#
        }
    }
}
