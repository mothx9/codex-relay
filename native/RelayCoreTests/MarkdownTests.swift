import XCTest
@testable import RelayCore

final class MarkdownTests: XCTestCase {
    func testRichStructureAndNestedInlineFormatting() {
        let blocks = RichDocument.parse("# Title\n\nA **bold** and *italic* `value`.\n\n3. First\n4. Second\n\n> Quote\n\n```cuda\n__global__ void add() {}\n```\n")
        XCTAssertEqual(blocks.map(\.kind), [.heading, .paragraph, .list, .quote, .code])
        XCTAssertTrue(blocks[1].spans.contains { $0.text == "bold" && $0.bold })
        XCTAssertTrue(blocks[1].spans.contains { $0.text == "italic" && $0.italic })
        XCTAssertTrue(blocks[1].spans.contains { $0.text == "value" && $0.code })
        XCTAssertEqual(blocks[2].ordinal, 3)
        XCTAssertEqual(blocks[2].children.count, 2)
        XCTAssertEqual(blocks[4].language, "cuda")
        XCTAssertEqual(blocks[4].text, "__global__ void add() {}\n")
    }
    func testPartialStreamingFenceRemainsVisible() {
        let blocks = RichDocument.parse("Progress\n\n```rust\nfn main() {\n    println!(\"Hi")
        XCTAssertEqual(blocks.last?.kind, .code)
        XCTAssertTrue(blocks.last?.text.contains("fn main()") == true)
        XCTAssertEqual(RichDocument.parse("**unfinished").first?.spans.map(\.text).joined(), "**unfinished")
    }
    func testWebLinksAndLocalPathsAreDistinct() {
        let block = RichDocument.parse("[Docs](https://example.invalid/docs) [Source](/tmp/file.swift) [Other](https://example.invalid/second)")[0]
        XCTAssertEqual(block.spans.compactMap(\.link), ["https://example.invalid/docs", "https://example.invalid/second"])
        XCTAssertNil(RichDocument.webURL("/Users/name/file.swift"))
        XCTAssertNil(RichDocument.webURL("file:///tmp/private"))
        XCTAssertNil(RichDocument.webURL("javascript:alert(1)"))
        XCTAssertNotNil(RichDocument.webURL("https://example.invalid/" + String(repeating: "path/", count: 80)))
        XCTAssertEqual(RichDocument.parse("Visit https://example.invalid/docs")[0].spans.compactMap(\.link), ["https://example.invalid/docs"])
    }
    func testTablesHaveHeaderAndBodyRows() {
        let table = RichDocument.parse("| Name | State |\n| --- | --- |\n| Test | Passed |\n")[0]
        XCTAssertEqual(table.kind, .table)
        XCTAssertEqual(table.children.count, 2)
        XCTAssertEqual(table.children[0].children.count, 2)
        XCTAssertEqual(table.children[1].children[0].spans.map(\.text).joined(), "Test")
    }
    func testCodeHighlightingIsLosslessAndBoundedLexical() {
        for language in ["c", "cpp", "cuda", "rust", "go", "swift", "python", "typescript", "shell", "json", "yaml", "markdown", "unknown"] {
            let code = "// hello\nconst value = \"é\\\"\";\n# line\n42\n"
            let tokens = CodeTokens.tokenize(code, language: language)
            XCTAssertEqual(tokens.map(\.text).joined(), code)
            XCTAssertTrue(tokens.contains { $0.kind == .string })
            XCTAssertTrue(tokens.contains { $0.kind == .number })
        }
        XCTAssertEqual(CodeTokens.tokenize(String(repeating: " ", count: 131072), language: nil).count, 1)
    }
}
