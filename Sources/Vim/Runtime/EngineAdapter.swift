import ApplicationServices
import Core

/// One engine's accessibility dialect, read into the neutral nodes and answers the field's snapshot and document take (field
/// model L1); the extension is what an engine without one does, which WebKit and AppKit take as uvim read them before.
public protocol EngineAdapter {
    var engine: Surface.Engine { get }
    /// The offsets a field with children selects in until uvim learns otherwise.
    var startingOffsets: OffsetsAnswer { get }
    /// The field's top-level nodes where a snapshot reads them whole; nil where it counts them.
    func roots(of field: AXUIElement) -> [AXUIElement]?
    /// Whether a snapshot reads the field's DOM classes, which flag ProseMirror's stops.
    var readsFieldClasses: Bool { get }
    /// The field shows nothing but its page's generated text, such as an empty editor's placeholder; a failed read says no.
    func showsOnlyGeneratedText(_ field: AXUIElement, roots: [AXUIElement]?, value: String?) -> Bool
    /// The attribute a node batch adds for `generated(_:at:)`; nil where the engine marks nothing.
    var generatedAttribute: String? { get }
    /// Whether the page generates the node whose batch read `generatedAttribute` at `slot`.
    func generated(_ reads: AX.AttributeBatch, at slot: Int) -> Bool
}

public extension EngineAdapter {
    var startingOffsets: OffsetsAnswer { .value }
    func roots(of field: AXUIElement) -> [AXUIElement]? { nil }
    var readsFieldClasses: Bool { false }
    func showsOnlyGeneratedText(_ field: AXUIElement, roots: [AXUIElement]?, value: String?) -> Bool { false }
    var generatedAttribute: String? { nil }
    func generated(_ reads: AX.AttributeBatch, at slot: Int) -> Bool { false }
}

/// Chromium, Electron's included: rich text selects in text-content offsets, and a node no DOM node backs has a negative id.
public struct ChromiumAdapter: EngineAdapter {
    public init() {}
    public var engine: Surface.Engine { .chromium }
    public var startingOffsets: OffsetsAnswer { .textContent }
    // A paragraph made a quote keeps the text and the count, and only its identity is new.
    public func roots(of field: AXUIElement) -> [AXUIElement]? { AX.children(of: field) }
    public var readsFieldClasses: Bool { true }
    public var generatedAttribute: String? { AX.chromiumNodeIDAttribute }

    public func generated(_ reads: AX.AttributeBatch, at slot: Int) -> Bool {
        // Chromium answers its node id as a string.
        reads.string(slot).flatMap { Int($0) }.map { $0 < 0 } ?? false
    }
}

public struct WebKitAdapter: EngineAdapter {
    public init() {}
    public var engine: Surface.Engine { .webkit }
}

/// `AXValue` is the caret space and every map the identity.
public struct AppKitAdapter: EngineAdapter {
    public init() {}
    public var engine: Surface.Engine { .appkit }
}

public extension Surface.Engine {
    var adapter: any EngineAdapter {
        switch self {
        case .chromium: ChromiumAdapter()
        case .webkit: WebKitAdapter()
        case .appkit: AppKitAdapter()
        }
    }
}

public extension Surface {
    /// A forced binding reads no engine, and reads nothing through it.
    var adapter: any EngineAdapter { engine?.adapter ?? AppKitAdapter() }
}

extension EngineAdapter {
    /// One node of the field's tree, as the document walk reads it; nil on a failed read.
    func node(_ node: AXUIElement) -> EmptyBlockScan<AXUIElement>.Block? {
        let names = [kAXRoleAttribute, kAXSubroleAttribute, kAXChildrenAttribute, "AXDOMClassList", "AXBlockQuoteLevel"]
        let reads = AX.attributes(names + [generatedAttribute].compactMap { $0 }, of: node)
        guard (0..<3).allSatisfy({ FieldTree.absentOrRead(reads, $0) }) else { return nil }
        // The last ones only add Linear's stops and controls and the page's markers, so one that fails reads as none.
        return EmptyBlockScan.Block(
            role: reads.string(0), subrole: reads.string(1), children: reads.elements(2) ?? [],
            classes: reads.strings(3) ?? [], quoteLevel: reads.int(4) ?? 0,
            generated: generatedAttribute != nil && generated(reads, at: names.count)
        )
    }

    /// One node as the generated-text scan reads it; nil on a failed read.
    func textNode(_ node: AXUIElement) -> GeneratedTextScan<AXUIElement>.Read? {
        let names = [kAXRoleAttribute, kAXValueAttribute, kAXChildrenAttribute]
        let reads = AX.attributes(names + [generatedAttribute].compactMap { $0 }, of: node)
        guard reads.string(0) != nil, FieldTree.absentOrRead(reads, 2) else { return nil }
        return GeneratedTextScan.Read(
            role: reads.string(0), generated: generatedAttribute != nil && generated(reads, at: names.count),
            value: reads.string(1), children: reads.elements(2) ?? []
        )
    }
}
