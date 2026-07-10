import SwiftUI
import PaisleyCore

// UI-only mappings for the platform-agnostic AgentStatus (defined in PaisleyCore).
// Kept in the app target so the core has no SwiftUI/AppKit dependency and builds
// on Linux. Dracula palette — inlined so this file has no cross-directory deps.
extension AgentStatus {
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
