import Foundation
let path = CommandLine.arguments[1]
let plan = try Planner.load(URL(fileURLWithPath:path))
let sample = Array(plan.orderedActivities.prefix(20))
func measure(_ body:()->Void)->Double { let t = Date(); body(); return Date().timeIntervalSince(t)*1000 }
var old:[[String]] = []
let before = measure { for row in sample { old.append(plan.activities.filter { $0.entityType == "summary" && !plan.descendants(of:row.activity.id).contains($0.id) }.map(\.id)) } }
let snapshot = ScheduleAnalysis(plan:plan)
var fresh:[[String]] = []
let after = measure { for row in sample { fresh.append(snapshot.parentChoices(for:row.activity.id).map(\.id)) } }
precondition(old == fresh)
let cached = measure { for _ in 0..<100 { for row in sample { _ = snapshot.parentChoices(for:row.activity.id) } } }
print("20 row parent lists before: \(before) ms; after: \(after) ms; 2000 cached reads: \(cached) ms")
let root = plan.orderedActivities[0].activity.id
precondition(!snapshot.parentChoices(for:root).contains(where:{$0.id==root}))
print("PASS: identical parent choices; root and descendants excluded")
