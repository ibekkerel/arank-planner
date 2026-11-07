import Foundation
let input = URL(fileURLWithPath:CommandLine.arguments[1])
let output = URL(fileURLWithPath:CommandLine.arguments[2])
let plan = try Planner.load(input)
let baseline = try Planner.calculate(plan)
var metrics:[[String:Any]] = []
var assertions = 0
func require(_ value:Bool,_ message:String) { precondition(value,message); assertions += 1 }
func validate(_ p:Schedule,_ result:Calculation) {
    require(result.timings.count == p.activities.count,"every activity calculated")
    require(result.conflicts.isEmpty,"resource capacity")
    for link in p.links {
        let a=result.timings[link.from]!,b=result.timings[link.to]!
        let source=link.type.first == "F" ? a.finish : a.start
        let destination=link.type.last == "F" ? b.finish : b.start
        require(destination >= source+link.lag,"dependency \(link.id)")
    }
}
func measure(_ name:String,repeats:Int=3,_ operation:() throws -> Void) rethrows {
    var times:[Double] = []
    for _ in 0..<repeats { let start=Date();try operation();times.append(Date().timeIntervalSince(start)*1000) }
    times.sort()
    metrics.append(["operation":name,"median_ms":times[times.count/2],"min_ms":times.first!,"max_ms":times.last!,"repeats":repeats])
    print("\(name): \(String(format:"%.2f",times[times.count/2])) ms"); fflush(stdout)
}
require(plan.activities.count == 1500,"exactly 1500 WBS elements")
validate(plan,baseline)
let path = Dictionary(grouping:plan.links,by:\.from)
var visited:Set<String> = ["G-START"], stack=["G-START"]
while let id=stack.popLast() { for link in path[id,default:[]] where visited.insert(link.to).inserted { stack.append(link.to) } }
require(plan.activities.filter { $0.entityType != "summary" }.allSatisfy { visited.contains($0.id) },"every executable reachable from project start")
try measure("open_parse_and_validate") { _ = try Planner.load(input) }
try measure("full_resource_calendar_calculation",repeats:5) { _ = try Planner.calculate(plan) }
measure("prepare_all_dates_scale_and_loads") {
    let analysis=ScheduleAnalysis(plan:plan,calculation:baseline)
    _ = analysis.timeline(baseline.duration+3)
    for timing in baseline.timings.values { _ = analysis.date(timing.start);_ = analysis.date(timing.finish) }
    for resource in plan.resources { _ = analysis.loads(resource,days:baseline.duration+3) }
}
let warmed = ScheduleAnalysis(plan:plan,calculation:baseline)
try measure("cached_result_reads_3000") { for _ in 0..<3000 { _ = try warmed.calculation() } }
var scenarios:[[String:Any]] = []
func edit(_ name:String,_ body:(inout Schedule)->Void) throws {
    var changed=plan;body(&changed)
    var answer:Calculation?
    try measure(name) { let result=try Planner.calculate(changed);let analysis=ScheduleAnalysis(plan:changed,calculation:result);_ = analysis.timeline(result.duration+3);for resource in changed.resources.prefix(4) { _ = analysis.loads(resource,days:result.duration+3) };answer=result }
    let result=answer!; validate(changed,result)
    let changedDates=plan.activities.filter { let a=baseline.timings[$0.id]!,b=result.timings[$0.id]!;return a.start != b.start || a.finish != b.finish }.count
    scenarios.append(["operation":name,"changed_date_rows":changedDates,"duration_days":result.duration,"finish":Planner.projectFinishDate(result,plan:changed),"cost_rub":result.cost,"conflicts":result.conflicts.count])
}
try edit("edit_manufacturing_duration_plus_10d") { p in let i=p.activities.firstIndex { $0.id == "P04.03.03" }!;p.activities[i].duration += 10 }
try edit("edit_concrete_volume_plus_20pct") { p in let i=p.activities.firstIndex { $0.id == "P06.01.04" }!;p.activities[i].volume! *= 1.2 }
try edit("edit_RKD_priority_1000") { p in let i=p.activities.firstIndex { $0.id == "P03.09.01" }!;p.activities[i].priority = 1000 }
try edit("edit_station_contractor_capacity_6_to_3") { p in let i=p.resources.firstIndex { $0.id == "M06" }!;p.resources[i].capacity = 3 }
try edit("edit_design_productivity_plus_10pct") { p in let i=p.resources.firstIndex { $0.id == "D02" }!;p.resources[i].productivity! *= 1.1 }
let vacationStart=Planner.date(baseline.timings["P03.01.01"]!.start,plan:plan), vacationEnd=Planner.date(baseline.timings["P03.01.01"]!.start+5,plan:plan)
try edit("edit_shared_design_calendar_vacation") { p in let i=p.resourceCalendars!.firstIndex { $0.id == "ENG" }!;p.resourceCalendars![i].exceptions.append(CalendarException(id:"BENCH-VAC",name:"Тестовый отпуск",from:vacationStart,through:vacationEnd)) }
try edit("add_cross_package_finish_start_link") { p in p.links.append(Link(id:"BENCH-LINK",from:"P08.07.M",to:"P09.01.06")) }
try measure("preview_linked_task_move_plus_10d") { let proposal=try Planner.move(plan,activityID:"P04.03.03",to:baseline.timings["P04.03.03"]!.start+10,before:baseline);require(proposal.achieved,"move accepted at requested date");validate(proposal.proposed,proposal.after) }
let report:[String:Any] = ["project":plan.name,"version":"SILA-1500 benchmark v1","elements":plan.activities.count,"tasks":plan.activities.filter { $0.entityType == "task" }.count,"summaries":plan.activities.filter { $0.entityType == "summary" }.count,"milestones":plan.activities.filter { $0.entityType == "milestone" }.count,"resources":plan.resources.count,"links":plan.links.count,"duration_working_days":baseline.duration,"start":Planner.date(0,plan:plan),"finish":Planner.projectFinishDate(baseline,plan:plan),"cost_rub":baseline.cost,"conflicts":baseline.conflicts.count,"checks":assertions,"metrics":metrics,"scenarios":scenarios,"note":"Optimized Swift build. Median/min/max of repeated engine operations; editing includes timeline and first four resource profiles. Not UI FPS or keyboard-to-screen latency. All durations, capacities and costs are training assumptions."]
try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]).write(to:output)
print("Checks: \(assertions); report \(output.path)")
