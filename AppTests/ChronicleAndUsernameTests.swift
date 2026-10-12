import XCTest
@testable import Blindbandit

final class ChronicleAndUsernameTests: XCTestCase {
    func testArticleDeepLinks() {
        XCTAssertEqual(ChronicleDeepLink.articleURL(from: URL(string: "mrblindbandit://article/the-foundation-is-active")!)?.absoluteString,
                       "https://mrblindbandit.net/publications/the-foundation-is-active/")
        XCTAssertEqual(ChronicleDeepLink.articleURL(from: URL(string: "https://mrblindbandit.net/publications/abc-1/")!)?.absoluteString,
                       "https://mrblindbandit.net/publications/abc-1/")
        XCTAssertNil(ChronicleDeepLink.articleURL(from: URL(string: "https://example.org/publications/x/")!))
    }

    func testArticleParserKeepsHeadingsAndParagraphs() {
        let html = "<nav>skip</nav><article><h1>Title &amp; More</h1><p>First <b>para</b>.</p><h2>Part</h2><li>Item</li></article>"
        let blocks = ChronicleArticleParser.blocks(fromHTML: html)
        XCTAssertEqual(blocks.map(\.kind), [.heading(1), .paragraph, .heading(2), .bullet])
        XCTAssertEqual(String(blocks[0].text.characters), "Title & More")
    }

    func testSitePayloadUnwrapsDataEnvelope() throws {
        let json = #"{"success":true,"data":{"username":"abc","valid":true,"available":true,"reason":null}}"#
        let a = try JSONDecoder().decode(UsernameAPI.Availability.self, from: UsernameAPI.payload(Data(json.utf8)))
        XCTAssertTrue(a.available)
    }

    func testUsernameFormat() {
        XCTAssertTrue(UsernameAPI.isValidFormat("mr_blind.bandit"))
        XCTAssertFalse(UsernameAPI.isValidFormat("ab"))
        XCTAssertEqual(UsernameAPI.normalize(" @MrBlind "), "mrblind")
    }
}
