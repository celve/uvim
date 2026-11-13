import AppKit

// A private named pasteboard, never the user's: what the fork's clipboard sync
// counts as a copy from another app, beside the register paste's loan.

@MainActor
func run() {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    pasteboard.clearContents()
    pasteboard.setString("before uvim", forType: .string)

    let sync = ClipboardSync(pasteboard)
    let loan = PasteboardLoan(pasteboard)
    loan.onWrite = { sync.acknowledge() }

    precondition(sync.takeExternalText() == nil, "what was there at launch is not a new copy")

    sync.publish("yanked\n")
    precondition(pasteboard.string(forType: .string) == "yanked\n", "a yank reaches the clipboard")
    precondition(sync.takeExternalText() == nil, "uvim's own yank is not a copy from another app")

    pasteboard.clearContents()
    pasteboard.setString("from Safari", forType: .string)
    precondition(sync.takeExternalText() == "from Safari", "a copy elsewhere is seen")
    precondition(sync.takeExternalText() == nil, "and seen once")

    loan.put("REG")
    precondition(sync.takeExternalText() == nil, "the loan's put is uvim's own")
    loan.restore()
    precondition(pasteboard.string(forType: .string) == "from Safari")
    precondition(sync.takeExternalText() == nil, "the loan's give-back is uvim's own")

    // A yank while a paste is on loan: the yank is newer, so the loan must not give the old text back.
    loan.put("REG")
    sync.publish("newer yank")
    loan.restore()
    precondition(pasteboard.string(forType: .string) == "newer yank", "a yank outlives an open loan")
    precondition(sync.takeExternalText() == nil)

    pasteboard.clearContents()
    pasteboard.setString("borrowed", forType: .string)
    pasteboard.setData(Data(), forType: PasteboardLoan.transient)
    precondition(sync.takeExternalText() == nil, "another tool's transient paste is not a copy")

    pasteboard.clearContents()
    pasteboard.setData(Data([1, 2, 3]), forType: .png)
    precondition(sync.takeExternalText() == nil, "an image is not text p could put")
}

MainActor.assumeIsolated { run() }
print("Clipboard sync tests passed")
