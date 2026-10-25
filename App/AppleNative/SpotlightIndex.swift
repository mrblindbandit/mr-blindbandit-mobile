import CoreSpotlight
import UniformTypeIdentifiers

@MainActor
enum SpotlightIndex {
    static func indexChat(id: String, title: String, snippet: String) {
        let item = CSSearchableItem(
            uniqueIdentifier: "chat:\(id)",
            domainIdentifier: "net.mrblindbandit.app.chats",
            attributeSet: attrs(title: title, content: snippet, keywords: ["chat", "message", title])
        )
        CSSearchableIndex.default().indexSearchableItems([item]) { _ in }
    }

    static func indexPerson(handle: String, displayName: String) {
        let item = CSSearchableItem(
            uniqueIdentifier: "person:\(handle)",
            domainIdentifier: "net.mrblindbandit.app.people",
            attributeSet: attrs(title: displayName.isEmpty ? "@\(handle)" : displayName, content: "@\(handle)", keywords: [handle, displayName, "call", "message"])
        )
        CSSearchableIndex.default().indexSearchableItems([item]) { _ in }
    }

    static func indexBite(id: String, author: String, body: String) {
        let item = CSSearchableItem(
            uniqueIdentifier: "bite:\(id)",
            domainIdentifier: "net.mrblindbandit.app.bites",
            attributeSet: attrs(title: "Bite by \(author)", content: body, keywords: ["bite", "feed", author])
        )
        CSSearchableIndex.default().indexSearchableItems([item]) { _ in }
    }

    static func remove(ids: [String]) {
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: ids) { _ in }
    }

    private static func attrs(title: String, content: String, keywords: [String]) -> CSSearchableItemAttributeSet {
        let set = CSSearchableItemAttributeSet(contentType: .text)
        set.title = title
        set.contentDescription = String(content.prefix(200))
        set.keywords = keywords.filter { !$0.isEmpty }
        set.creator = "Blind Bandit"
        return set
    }
}
