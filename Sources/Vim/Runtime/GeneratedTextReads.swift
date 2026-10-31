import ApplicationServices
import Core

/// Text a page generates in a field, read over AX (LIN-1930); `GeneratedTextScan` has the rules.
extension ChromiumAdapter {
    public func showsOnlyGeneratedText(_ field: AXUIElement, roots known: [AXUIElement]?, value: String?) -> Bool {
        guard value.map(GeneratedText.mayFill) ?? true, let roots = known ?? scannableRoots(of: field), !roots.isEmpty else {
            return false
        }
        var scan = GeneratedTextScan<AXUIElement>(budget: GeneratedText.readBudget, read: textNode)
        guard let texts = scan.run(roots: roots), let value = value ?? AX.value(of: field) else { return false }
        return GeneratedText.fills(value, with: texts)
    }

    /// Unread past the scan's budget, as every root costs it a read: a long document's roots are counted, not fetched.
    private func scannableRoots(of field: AXUIElement) -> [AXUIElement]? {
        guard let count = AX.childCount(of: field), count <= GeneratedText.readBudget else { return nil }
        return AX.children(of: field)
    }
}

extension EngineAdapter {
    /// The page generates all of `run`, in plain offsets, as a fresh read of the tree there finds; a failed read says no (LIN-2370).
    func generates(_ run: Range<Int>, in field: AXUIElement) -> Bool {
        guard let markers = AX.markerText(of: field), let tree = FieldTree(field, markers: markers, adapter: self) else {
            return false
        }
        var scan = GeneratedTextScan<AXUIElement>(budget: GeneratedText.runBudget, read: textNode)
        return scan.generates(run, in: tree.blocks, offset: tree.offset)
    }
}
