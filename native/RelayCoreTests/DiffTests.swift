import XCTest
@testable import RelayCore
final class DiffTests: XCTestCase {
    func testHunksFilesAndReliableLineNumbers() {
        let patch = "diff --git a/src/a.c b/src/a.c\n--- a/src/a.c\n+++ b/src/a.c\n@@ -4,2 +4,2 @@\n same\n-old\n+new\ndiff --git a/old b/old\n--- a/old\n+++ /dev/null\n@@ -1 +0,0 @@\n-gone"
        let files = PatchDocument.parse(patch)
        XCTAssertEqual(files.map(\.path), ["src/a.c", "old"])
        XCTAssertEqual(files[0].additions, 1); XCTAssertEqual(files[0].deletions, 1)
        let addition = files[0].lines.first { $0.kind == .addition }
        XCTAssertEqual(addition?.new, 5); XCTAssertNil(addition?.old)
        XCTAssertEqual(files[1].lines.last?.old, 1)
    }
    func testPlainFileContentsAreNotMisclassifiedAsPatch() {
        let files = PatchDocument.parse("# Readme\n- first item\n+ literal plus", path: "README.md")
        XCTAssertEqual(files.first?.additions, 0)
        XCTAssertEqual(files.first?.deletions, 0)
    }
    func testPartialDiffDoesNotInventLineNumbers() {
        let files = PatchDocument.parse("+incomplete\n", path: "kernel.cu")
        XCTAssertEqual(files.first?.path, "kernel.cu")
        XCTAssertNil(files.first?.lines.first?.new)
        XCTAssertEqual(files.first?.lines.first?.text, "+incomplete")
    }
    func testChangeOverviewUsesLatestPatchWithoutDoubleCounting() {
        var file = Activity(id: "edit", kind: "fileChange", text: "Changed")
        file.files = [ChangedFile(path: "a.c", kind: "modify", previousPath: nil, patch: nil)]
        XCTAssertEqual(ChangeOverview.describe([file]), "1 file changed")
        let old = Activity(id: "old", kind: "diff", text: "--- a/a.c\n+++ b/a.c\n@@ -1 +1 @@\n-old\n+intermediate")
        let latest = Activity(id: "new", kind: "diff", text: "--- a/a.c\n+++ b/a.c\n@@ -1 +1,2 @@\n-old\n+new\n+second")
        XCTAssertEqual(ChangeOverview.describe([file, old, latest]), "1 file changed · +2 −1")
    }
}
