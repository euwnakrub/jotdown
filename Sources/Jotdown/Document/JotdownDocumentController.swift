import AppKit

/// ระบุชนิดเอกสารเองในโค้ด เพื่อให้ทำงานได้แม้ไม่มี Info.plist (swift run)
final class JotdownDocumentController: NSDocumentController {
    override var defaultType: String? { JotTypes.markdown }
    override var documentClassNames: [String] { ["JotdownDocument"] }
    override func documentClass(forType typeName: String) -> AnyClass? { JotdownDocument.self }
    override func typeForContents(of url: URL) throws -> String { JotTypes.markdown }
    override func displayName(forType typeName: String) -> String? { "Markdown" }
}
