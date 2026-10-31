import ApplicationServices
import Core

/// `FieldDocument.walk` over a field's accessibility tree, both its parts through one `TreeReads` (LIN-2388).
enum FieldDocumentReads {
    /// The tree is read only where a part needs it; a failed read fails the parts that needed it.
    static func walk(
        in element: AXUIElement, _ request: FieldDocument.Request, adapter: any EngineAdapter
    ) -> (document: FieldDocument, reads: Discovery.Reads) {
        let budget = FieldDocument.readBudget - 2
        var field: FieldTree?
        let recorder = Discovery.Recorder<AXUIElement>(
            budget: budget, block: { field?.block($0) }, offset: { field?.offset($0, $1) }
        )
        let tree = TreeReads(budget: budget, block: recorder.block, offset: recorder.offset)
        let document = FieldDocument.walk(request, roots: {
            field = FieldTree(element, markers: request.markers, adapter: adapter)
            return field.map { recorder.roots($0.blocks) }
        }, tree: tree)
        return (document, recorder.reads)
    }
}

/// The reads the document walk descends a field's tree by, its nodes through the field's engine adapter.
struct FieldTree {
    let blocks: [AXUIElement]
    let block: (AXUIElement) -> EmptyBlockScan<AXUIElement>.Block?
    let offset: (AXUIElement, _ end: Bool) -> Int?

    init?(_ element: AXUIElement, markers: String, adapter: any EngineAdapter) {
        guard let start = AX.fieldStart(of: element), let blocks = AX.children(of: element) else { return nil }
        // Marker lengths count each U+FFFC before them, plain offsets do not.
        var objects = [0]
        objects.reserveCapacity(markers.utf16.count + 1)
        for unit in markers.utf16 { objects.append(objects[objects.count - 1] + (unit == 0xFFFC ? 1 : 0)) }
        self.blocks = blocks
        block = { adapter.node($0) }
        offset = { node, end in
            guard let length = AX.markerLength(from: start, to: node, end: end, in: element), length >= 0 else { return nil }
            // A table's columns read past the field's text; they sort after it, the rows holding their cells (LIN-1780).
            guard objects.indices.contains(length) else { return length - objects[objects.count - 1] }
            return length - objects[length]
        }
    }

    /// A slot that read, or whose attribute the element lacks; any other failure is a failed read.
    static func absentOrRead(_ reads: AX.AttributeBatch, _ index: Int) -> Bool {
        guard let error = reads.error(index) else { return true }
        return error == .noValue || error == .attributeUnsupported
    }
}
