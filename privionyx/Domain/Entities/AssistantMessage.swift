import Foundation

struct AssistantMessage: Identifiable, Hashable {
    enum Role: Hashable {
        case assistant
        case user
    }

    let id: UUID
    let role: Role
    let text: String

    init(id: UUID = UUID(), role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }

    var isAssistant: Bool { role == .assistant }
}
