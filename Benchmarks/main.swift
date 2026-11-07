import Foundation
func measure(_ name:String,_ body:()->Void) {
 var times:[Double] = []
 for _ in 0..<3 { let start=Date(); body(); times.append(Date().timeIntervalSince(start)*1000) }
 print("\(name): \(String(format:"%.2f",times.sorted()[1])) ms")
}
var tasks:[Activity] = []
let resources=(0..<20).map { Resource(id:"r\($0)",name:"R\($0)") }
for i in 0..<300 { tasks.append(Activity(id:"t\(i)",name:"Task",duration:4,resource:"r\(i%20)",earliestStart:i)) }
let plan=Schedule(name:"Benchmark",activities:tasks,links:[],resources:resources)
let result=try! Planner.calculate(plan)
measure("calculate_300_tasks") { for _ in 0..<5 { _ = try! Planner.calculate(plan) } }
measure("render_80_result_reads") {
 #if BASELINE
 for _ in 0..<80 { _ = try! Planner.calculate(plan) }
 #else
 let snapshot=ScheduleAnalysis(plan:plan)
 for _ in 0..<80 { _ = try! snapshot.calculation() }
 #endif
}
measure("dates_600_cells") {
 #if BASELINE
 for i in 0..<600 { _ = Planner.date(i,plan:plan) }
 #else
 let snapshot=ScheduleAnalysis(plan:plan)
 for i in 0..<600 { _ = snapshot.date(i) }
 #endif
}
measure("resource_load_20x365") { for resource in resources { _ = Planner.loads(resource:resource,days:365,plan:plan,result:result) } }
