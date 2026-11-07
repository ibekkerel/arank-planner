import SwiftUI
@main struct Check {
 @MainActor static func main() throws {
  let w = Workspace()
  let old = w.result!.duration
  let initial = w.snapshot
  w.setAutomaticCalculation(false)
  w.change { $0.activities[0].duration += 5 }
  precondition(w.needsCalculation && w.result!.duration == old)
  precondition(w.snapshot.calculationBuildCount == 0)
  w.change { $0.activities[1].duration += 3 }
  precondition(w.snapshot.calculationBuildCount == 0 && w.displayedSnapshot === initial)
  precondition(w.recalculate() && !w.needsCalculation && w.result!.duration > old)
  w.change { $0.activities[0].duration += 1 }
  w.setAutomaticCalculation(true)
  precondition(w.automaticCalculation && !w.needsCalculation)
  let saved = w.plan
  w.change { $0.links.append(Link(id:"cycle",from:"G",to:"A",type:"FS",lag:0)) }
  precondition(w.plan == saved && !w.error.isEmpty)
  w.error = ""; w.setAutomaticCalculation(false)
  w.change { $0.activities[0].requestedFinish = "2026-11-09"; $0.activities[0].lockFinish = true }
  precondition(w.needsCalculation)
  w.setAutomaticCalculation(true)
  precondition(!w.automaticCalculation && w.needsCalculation && !w.error.isEmpty)
  print("PASS: manual batch edits, cached display, explicit calculation, auto switch, cycles, failed calculation")
 }
}
