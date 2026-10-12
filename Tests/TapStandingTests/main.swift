precondition(!TapStanding.waiting.attempts(wanted: true, trusted: false), "no attempt before Accessibility: a refused one is final")
precondition(TapStanding.waiting.attempts(wanted: true, trusted: true), "the grant, at launch or later, is what starts the tap")
precondition(!TapStanding.waiting.attempts(wanted: false, trusted: true), "a hub with no handler holds no tap")
precondition(!TapStanding.refused.attempts(wanted: true, trusted: true), "a refusal is final for the process")
precondition(!TapStanding.installed.attempts(wanted: true, trusted: true))

precondition(TapStanding.refused.handsOver(startedTrusted: false), "refused after a launch without Accessibility: a new process gets the tap")
precondition(!TapStanding.refused.handsOver(startedTrusted: true), "refused with Accessibility from launch: another process would be refused too")
precondition(!TapStanding.waiting.handsOver(startedTrusted: false), "nothing to hand over before the grant")
precondition(!TapStanding.installed.handsOver(startedTrusted: false), "a tap that came in place stays")

print("Tap standing tests passed")
