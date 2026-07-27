import Foundation

struct AssistantMessage: Identifiable, Hashable {
    enum Role: Hashable {
        case assistant
        case user
    }

    /// The receipts a reply is talking about, rendered under it as cards the user can open.
    ///
    /// Holds identifiers rather than receipts so the transcript can't go stale: a receipt
    /// edited or deleted after the answer was written is re-read from the store on every
    /// render, so a card either shows current figures or quietly disappears.
    struct ReceiptMatches: Hashable {
        let ids: [UUID]
        /// What the search understood — "Starbucks · this month".
        let caption: String
        /// Matches beyond the ones listed, if the search found more than it shows.
        let hiddenCount: Int

        init(ids: [UUID], caption: String, hiddenCount: Int = 0) {
            self.ids = ids
            self.caption = caption
            self.hiddenCount = hiddenCount
        }
    }

    let id: UUID
    let role: Role
    let text: String
    let matchedReceipts: ReceiptMatches?

    init(id: UUID = UUID(), role: Role, text: String, matchedReceipts: ReceiptMatches? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.matchedReceipts = matchedReceipts
    }

    var isAssistant: Bool { role == .assistant }
}
