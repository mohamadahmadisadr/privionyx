import Foundation

enum ReceiptLineItemCoder {
    static func encode(_ items: [ReceiptLineItem]) -> String? {
        guard items.isEmpty == false,
              let data = try? JSONEncoder().encode(items),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        return text
    }

    static func decode(from text: String?) -> [ReceiptLineItem] {
        guard let text,
              let data = text.data(using: .utf8),
              let items = try? JSONDecoder().decode([ReceiptLineItem].self, from: data) else {
            return []
        }

        return items
    }
}
