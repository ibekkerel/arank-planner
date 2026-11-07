import Foundation
var checks = 0
func expect(_ value: Bool, _ name: String) { if !value { fatalError("FAIL: \(name)") }; checks += 1 }
func rejects(_ p: Schedule, _ name: String) { do { _ = try Planner.calculate(p); fatalError("Accepted: \(name)") } catch { checks += 1 } }
var p = Schedule.demo
let r = try Planner.calculate(p)
expect(r.duration == 35,"demo duration")
expect(r.timings["C"]!.float == 5,"parallel float")
expect(r.timings["G"]!.start == 35,"milestone")
for (kind, expected) in [("FS",7),("SS",2),("FF",4),("SF",0)] {
 let p = Schedule(name:"test",activities:[Activity(id:"a",name:"a",duration:5),Activity(id:"b",name:"b",duration:3)],links:[Link(from:"a",to:"b",type:kind,lag:2)],resources:[])
 expect(try Planner.calculate(p).timings["b"]!.start == expected,"\(kind) forward pass")
}
p.links.append(Link(from:"G",to:"A")); rejects(p,"cycle")
p = .demo; p.activities.append(p.activities[0]); rejects(p,"duplicate")
p = .demo; p.links.append(Link(from:"missing",to:"A")); rejects(p,"dangling")
p = .demo; p.calendar.weekdays = []; rejects(p,"empty calendar")
p = .demo; p.startDate = "2026-02-30"; rejects(p,"invalid date")
p = .demo; p.activities[0].productivity = 0; p.activities[0].volume = 10; rejects(p,"zero productivity")
p = .demo; p.activities[0].volume = 10; p.activities[0].productivity = 3; expect(try Planner.calculate(p).timings["A"]!.finish == 4,"productivity ceil")
p = .demo; p.levelResources = false; p.activities[2].resource = "crew"; expect(try Planner.calculate(p).conflicts.count == 1,"resource overload")
p = .demo; expect(Planner.date(5,plan:p) == "2026-11-16","weekend")
p.calendar.holidays = ["2026-11-10"]; expect(Planner.date(5,plan:p) == "2026-11-17","holiday")
p = .demo
let u = URL(fileURLWithPath:CommandLine.arguments[1]); try Planner.save(p,to:u); let loaded = try Planner.load(u); expect(try Planner.calculate(loaded).duration == Planner.calculate(p).duration && loaded.activities.map(\.entityType) == p.activities.map(\.entityType),"roundtrip")
var json = try JSONSerialization.jsonObject(with:Data(contentsOf:u)) as! [String:Any]; json["newUnknown"] = true; try JSONSerialization.data(withJSONObject:json).write(to:u)
do { _ = try Planner.load(u); fatalError("unknown field lost") } catch { checks += 1 }
try Planner.save(Schedule.demo,to:u)
var hierarchy = Schedule(name:"Hierarchy",activities:[
    Activity(id:"root",name:"Phase",duration:0,kind:"summary"),
    Activity(id:"nested",name:"Subphase",duration:0,kind:"summary",parent:"root"),
    Activity(id:"one",name:"Task",duration:4,kind:"task",parent:"nested"),
    Activity(id:"two",name:"Task 2",duration:3,kind:"task",parent:"root"),
    Activity(id:"gate",name:"Milestone",duration:0,kind:"milestone",parent:"root")],links:[Link(from:"one",to:"two"),Link(from:"two",to:"gate")],resources:[])
let hr = try Planner.calculate(hierarchy)
expect(hr.duration == 7,"summary does not add duration")
expect(hr.timings["root"]!.start == 0 && hr.timings["root"]!.finish == 7,"summary aggregates descendants")
expect(hr.timings["nested"]!.finish == 4,"nested summary")
expect(hr.timings["gate"]!.start == 7 && hr.timings["gate"]!.finish == 7,"explicit milestone")
expect(hierarchy.orderedActivities.map { $0.activity.id } == ["root","nested","one","two","gate"],"hierarchy order")
expect(hierarchy.descendants(of:"nested") == Set(["nested","one"]),"subtree")
var bad = hierarchy; bad.activities[0].parent = "nested"; rejects(bad,"hierarchy cycle")
bad = hierarchy; bad.activities[1].parent = "one"; rejects(bad,"non-summary parent")
bad = hierarchy; bad.activities[1].parent = "absent"; rejects(bad,"missing parent")
bad = hierarchy; bad.activities[4].duration = 2; rejects(bad,"milestone duration")
bad = hierarchy; bad.links.append(Link(from:"root",to:"gate")); rejects(bad,"summary dependency rejected")
bad = hierarchy; bad.activities[0].duration = 2; rejects(bad,"summary own duration rejected")
try Planner.save(hierarchy,to:u)
let reloadedHierarchy = try Planner.load(u); expect(reloadedHierarchy.activities == hierarchy.activities && reloadedHierarchy.links == hierarchy.links,"hierarchy roundtrip")
var future = try JSONSerialization.jsonObject(with:Data(contentsOf:u)) as! [String:Any]; future["version"] = "99"; try JSONSerialization.data(withJSONObject:future).write(to:u)
do { _ = try Planner.load(u); fatalError("accepted future version") } catch { checks += 1 }
var legacy = try JSONSerialization.jsonObject(with:JSONEncoder().encode(Schedule.demo)) as! [String:Any]; legacy["version"] = "0.1"; try JSONSerialization.data(withJSONObject:legacy).write(to:u)
let migrated = try Planner.load(u); expect(migrated.version == "0.6" && migrated.activities.last!.entityType == "milestone","legacy migration")
try Planner.save(Schedule.demo,to:u)
try Planner.save(hierarchy,to:u.deletingLastPathComponent().appendingPathComponent("hierarchy.osched"))
var quantities = Schedule.demo
quantities.activities[0].kind = "task"; quantities.activities[0].volume = 120.5; quantities.activities[0].volumeUnit = "м³"
expect(try Planner.calculate(quantities).duration == 35,"volume alone preserves duration")
quantities.activities[0].productivity = 20
expect(try Planner.calculate(quantities).timings["A"]!.finish == 7,"volume productivity duration")
try Planner.save(quantities,to:u)
let quantitiesLoaded = try Planner.load(u)
expect(quantitiesLoaded.activities[0].volume == 120.5 && quantitiesLoaded.activities[0].volumeUnit == "м³","volume and unit roundtrip")
quantities.activities[0].volume = -1; rejects(quantities,"negative volume")
quantities = Schedule.demo; quantities.activities[0].volumeUnit = "  "; rejects(quantities,"empty unit")
for (a,b,kind) in [(false,false,"SS"),(false,true,"SF"),(true,false,"FS"),(true,true,"FF")] {
 expect(ConnectionEndpoint.dependency(from:ConnectionEndpoint(activityID:"a",finish:a),to:ConnectionEndpoint(activityID:"b",finish:b)) == kind,"drag endpoint type " + kind)
}
try Planner.save(Schedule.demo,to:u)
try Planner.save(quantitiesLoaded,to:u.deletingLastPathComponent().appendingPathComponent("quantities.osched"))
let source = Schedule.demo
let linkedMove = try Planner.move(source,activityID:"B",to:12)
expect(linkedMove.linked && linkedMove.achieved,"linked move achieves requested start")
expect(linkedMove.after.duration == 43,"linked move propagates finish")
expect(linkedMove.after.timings["C"]!.start == 4,"unaffected parallel branch")
expect(linkedMove.proposed.links == source.links && source.activities[1].earliestStart == nil,"move preserves links and original")
let blockedMove = try Planner.move(source,activityID:"B",to:0)
expect(!blockedMove.achieved && blockedMove.after.timings["B"]!.start == 4,"incoming dependency prevents early move")
let isolated = Schedule(name:"Isolated",activities:[Activity(id:"u",name:"Unlinked",duration:3,kind:"task")],links:[],resources:[])
let moved = try Planner.move(isolated,activityID:"u",to:8)
expect(!moved.linked && moved.after.timings["u"]!.start == 8 && moved.after.duration == 11,"unlinked move")
expect(try Planner.move(moved.proposed,activityID:"u",to:2).after.timings["u"]!.start == 2,"move back replaces earliest constraint")
expect(Planner.finishDate(try Planner.calculate(isolated).timings["u"]!,plan:isolated) == "2026-11-11","inclusive finish date")
var production = Schedule(name:"Production",activities:[Activity(id:"work",name:"Concrete",duration:1,resource:"team",units:2,volume:100,volumeUnit:"м³",kind:"task")],links:[],resources:[Resource(id:"team",name:"Concrete crew",capacity:2,dailyRate:100,typeID:"team",productivity:10)])
expect(try Planner.calculate(production).duration == 5,"resource productivity and assignment demand")
expect(try Planner.calculate(production).cost == 1000,"cost uses production duration")
production.activities[0].productivity = 25
expect(try Planner.calculate(production).duration == 4,"explicit activity productivity overrides resource")
production.activities[0].productivity = nil
var invalidProduction = production; invalidProduction.activities[0].volumeUnit = "м²"; rejects(invalidProduction,"output unit mismatch")
invalidProduction = production; invalidProduction.resources[0].typeID = "missing"; rejects(invalidProduction,"missing resource type")
invalidProduction = production; invalidProduction.resources[0].productivity = 0; rejects(invalidProduction,"zero resource productivity")
invalidProduction = production; invalidProduction.typeCatalog = [ResourceType(id:"team",name:"Bad",unitID:"absent",outputUnitID:"m3")]; rejects(invalidProduction,"missing catalog unit")
invalidProduction = production; invalidProduction.unitCatalog = MeasurementUnit.defaults + [MeasurementUnit(name:"Duplicate",symbol:"м³")]; rejects(invalidProduction,"duplicate unit symbol")
invalidProduction = production; invalidProduction.activities[0].earliestStart = -1; rejects(invalidProduction,"negative release")
try Planner.save(moved.proposed,to:u)
let restoredMove = try Planner.load(u)
let restoredCalculation = try Planner.calculate(restoredMove)
expect(restoredMove.activities[0].earliestStart == 8 && restoredCalculation.duration == 11,"move roundtrip")
try Planner.save(production,to:u)
let restoredProduction = try Planner.load(u)
expect(restoredProduction.resources == production.resources && restoredProduction.measurementUnits == production.measurementUnits && restoredProduction.resourceTypes == production.resourceTypes,"catalog and productivity roundtrip")
try Planner.save(production,to:u.deletingLastPathComponent().appendingPathComponent("production.osched"))
try Planner.save(Schedule.demo,to:u)
expect(Planner.projectFinishDate(try Planner.calculate(Schedule.demo),plan:Schedule.demo) == "2026-12-28","project finish includes terminal milestone")
var priorities = Schedule(name:"Priority",activities:[Activity(id:"low",name:"Low",duration:4,resource:"r",kind:"task",priority:100),Activity(id:"high",name:"High",duration:2,resource:"r",kind:"task",priority:900)],links:[],resources:[Resource(id:"r",name:"Crew")])
let priorityResult = try Planner.calculate(priorities)
expect(priorityResult.timings["high"]!.start == 0 && priorityResult.timings["low"]!.start == 2,"priority controls first use of limited resource")
expect(priorityResult.duration == 6 && priorityResult.conflicts.isEmpty,"leveling removes overload")
priorities.levelResources = false
expect(try Planner.calculate(priorities).conflicts.count == 1,"unleveled mode reports overload")
priorities.levelResources = true
priorities.activities[0].requestedStart = "2026-11-13"; priorities.activities[0].lockStart = true
let fixedStartResult = try Planner.calculate(priorities)
expect(fixedStartResult.timings["low"]!.start == 4,"exact fixed start")
priorities.activities[0].requestedFinish = "2026-11-18"; priorities.activities[0].lockFinish = true
expect(try Planner.calculate(priorities).timings["low"]!.finish == 8,"matching fixed start and finish")
var badDates = priorities; badDates.activities[0].requestedFinish = "2026-11-19"; rejects(badDates,"contradictory exact dates")
badDates = priorities; badDates.activities[1].requestedStart = "2026-11-13"; badDates.activities[1].lockStart = true; rejects(badDates,"fixed resource conflict")
badDates = priorities; badDates.links.append(Link(from:"low",to:"high")); badDates.activities[1].requestedStart = "2026-11-09"; badDates.activities[1].lockStart = true; rejects(badDates,"fixed date dependency conflict")
badDates = priorities; badDates.activities[0].requestedStart = "2026-11-14"; rejects(badDates,"weekend date")
badDates = priorities; badDates.activities[1].priority = 1001; rejects(badDates,"invalid priority")
expect(try Planner.offset(for:"2026-11-16",plan:Schedule.demo) == 5,"calendar date to working offset")
var finishOnly = isolated; finishOnly.activities[0].requestedFinish = "2026-11-18"; finishOnly.activities[0].lockFinish = true
let finishOnlyResult = try Planner.calculate(finishOnly)
expect(finishOnlyResult.timings["u"]!.start == 5 && finishOnlyResult.timings["u"]!.finish == 8,"fixed finish schedules start from duration")
let grouped = try Planner.group(Schedule.demo,ids:["A","B"])
let groupID = grouped.activities.first { $0.entityType == "summary" }!.id
expect(grouped.activities.first { $0.id == "A" }!.parent == groupID && grouped.activities.first { $0.id == "B" }!.parent == groupID,"group selected tasks")
let groupedResult = try Planner.calculate(grouped)
expect(grouped.links.map { ($0.from + $0.to + $0.type) } == Schedule.demo.links.map { ($0.from + $0.to + $0.type) } && groupedResult.duration == 35,"group preserves dependencies and schedule")
do { _ = try Planner.group(hierarchy,ids:["one","two"]); fatalError("mixed parent group accepted") } catch { checks += 1 }
let outputDay = Planner.load(resource:production.resources[0],day:0,plan:production,result:try Planner.calculate(production))
expect(outputDay.quantity == 2 && outputDay.output == 20 && outputDay.outputCapacity == 20,"load includes resource productivity and demand")
var partial = production; partial.activities[0].volume = 95
let partialResult = try Planner.calculate(partial)
expect(Planner.load(resource:partial.resources[0],day:4,plan:partial,result:partialResult).output == 15,"last day output limited by remaining volume")
try Planner.save(priorities,to:u)
let priorityRoundtrip = try Planner.load(u)
expect(priorityRoundtrip.activities[0].lockStart == true && priorityRoundtrip.activities[1].priority == 900 && priorityRoundtrip.levelResources == true,"fixed dates priorities roundtrip")
try Planner.save(priorities,to:u.deletingLastPathComponent().appendingPathComponent("priorities.osched"))
try Planner.save(Schedule.demo,to:u)
let leapGrid = CalendarGrid.days(year:2024,month:2)
expect(leapGrid.count == 42 && leapGrid.compactMap { $0 }.count == 29,"leap month grid")
expect(leapGrid[3] == "2024-02-01" && leapGrid[31] == "2024-02-29","Monday first alignment")
expect(CalendarGrid.days(year:2025,month:2).compactMap { $0 }.count == 28,"common February")
expect(CalendarGrid.days(year:2026,month:11)[6] == "2026-11-01","Sunday month start")
expect(CalendarGrid.days(year:2026,month:13).isEmpty,"invalid month")
var scalePlan = Schedule.demo; scalePlan.startDate = "2026-12-30"
let scale = TimelineCalendar(plan:scalePlan,count:5)
expect(scale.dates == ["2026-12-30","2026-12-31","2027-01-01","2027-01-04","2027-01-05"],"timeline working dates")
expect(scale.years.map(\.label) == ["2026","2027"] && scale.years.map(\.count) == [2,3],"timeline year boundary")
expect(scale.months.map(\.label) == ["Декабрь","Январь"] && scale.months[1].start == 2,"timeline month boundary")


var resourceCalendar = ResourceCalendar(id:"rc",name:"Test shifts")
resourceCalendar.week = (1...7).map { ResourceWorkday(weekday:$0,intervals:(2...6).contains($0) ? [WorkInterval(start:540,end:780)] : []) }
expect(resourceCalendar.hours(date:"2026-11-09") == 4,"four-hour Monday")
expect(resourceCalendar.hours(date:"2026-11-14") == 0,"resource weekend")
resourceCalendar.exceptions = [CalendarException(name:"Vacation",from:"2026-11-10",through:"2026-11-11")]
expect(resourceCalendar.hours(date:"2026-11-10") == 0 && resourceCalendar.hours(date:"2026-11-11") == 0,"inclusive vacation")
resourceCalendar.exceptions.append(CalendarException(name:"Extra shift",from:"2026-11-11",through:"2026-11-11",kind:"working",intervals:[WorkInterval(start:540,end:1020)]))
expect(resourceCalendar.hours(date:"2026-11-11") == 8,"last exception overrides vacation")
var calendarPlan = Schedule(name:"Calendar test",activities:[Activity(id:"a",name:"Task",duration:2,resource:"r")],links:[],resources:[Resource(id:"r",name:"Worker",dailyRate:100,calendarID:"rc")],resourceCalendars:[resourceCalendar])
let calendarResult = try Planner.calculate(calendarPlan)
expect(calendarResult.timings["a"]!.start == 0 && calendarResult.timings["a"]!.finish == 4,"duration consumes 16 working hours across vacation")
expect(calendarResult.cost == 200,"cost excludes vacation")
expect(Planner.load(resource:calendarPlan.resources[0],day:1,plan:calendarPlan,result:calendarResult).capacity == 0,"zero capacity during vacation")
expect(Planner.load(resource:calendarPlan.resources[0],day:1,plan:calendarPlan,result:calendarResult).quantity == 0,"zero load during vacation")
calendarPlan.activities.append(Activity(id:"b",name:"Following",duration:1))
calendarPlan.links = [Link(from:"a",to:"b")]
expect(try Planner.calculate(calendarPlan).timings["b"]!.start == 4,"FS follows resource calendar finish")
calendarPlan.links[0].type = "FF"
expect(try Planner.calculate(calendarPlan).timings["b"]!.finish == 4,"FF uses calendar span")
calendarPlan.links[0].type = "SS"
expect(try Planner.calculate(calendarPlan).timings["b"]!.start == 0,"SS with calendar")
calendarPlan.links[0].type = "SF"; calendarPlan.links[0].lag = 3
expect(try Planner.calculate(calendarPlan).timings["b"]!.finish == 3,"SF with calendar")
calendarPlan.links = []; calendarPlan.activities.removeLast()
calendarPlan.activities[0].requestedStart = "2026-11-10"; calendarPlan.activities[0].lockStart = true
rejects(calendarPlan,"fixed start in vacation rejected")
calendarPlan.activities[0].requestedStart = nil; calendarPlan.activities[0].lockStart = nil
calendarPlan.activities[0].requestedFinish = "2026-11-12"; calendarPlan.activities[0].lockFinish = true
expect(try Planner.calculate(calendarPlan).timings["a"]!.finish == 4,"fixed finish with calendar")
calendarPlan.activities[0].requestedStart = "2026-11-09"; calendarPlan.activities[0].lockStart = true
expect(try Planner.calculate(calendarPlan).timings["a"]!.start == 0,"both fixed dates fit real hours")
calendarPlan.activities[0].requestedStart = nil; calendarPlan.activities[0].lockStart = nil
calendarPlan.activities[0].requestedFinish = nil; calendarPlan.activities[0].lockFinish = nil
calendarPlan.resources[0].timeUnit = "hour"; calendarPlan.resources[0].typeID = "team"; calendarPlan.resources[0].productivity = 10
calendarPlan.activities[0].volume = 100; calendarPlan.activities[0].volumeUnit = "м³"
let hourlyResult = try Planner.calculate(calendarPlan)
expect(hourlyResult.timings["a"]!.finish == 3,"hourly productivity uses shifts")
expect(hourlyResult.cost == 1000,"hourly cost uses ten working hours")
expect(Planner.load(resource:calendarPlan.resources[0],day:2,plan:calendarPlan,result:hourlyResult).output == 60,"partial final shift output")
calendarPlan.resources[0].timeUnit = "day"; calendarPlan.resources[0].productivity = 80
expect(try Planner.calculate(calendarPlan).timings["a"]!.finish == 3,"daily productivity scaled from eight hours")
calendarPlan.levelResources = false
expect(try Planner.calculate(calendarPlan).timings["a"]!.finish == 3,"calendar applies without leveling")
calendarPlan.resourceCalendars![0].week[1].intervals = [WorkInterval(start:540,end:800),WorkInterval(start:700,end:900)]
rejects(calendarPlan,"overlapping shifts rejected")
calendarPlan.resourceCalendars = [resourceCalendar]; calendarPlan.resources[0].calendarID = "missing"
rejects(calendarPlan,"unknown resource calendar rejected")
calendarPlan.resources[0].calendarID = "rc"
calendarPlan.resourceCalendars![0].exceptions.append(CalendarException(from:"2026-11-20",through:"2026-11-19"))
rejects(calendarPlan,"reversed vacation rejected")
calendarPlan.resourceCalendars = [resourceCalendar]
try Planner.save(calendarPlan,to:u.deletingLastPathComponent().appendingPathComponent("resource-calendars.osched"))
let calendarReload = try Planner.load(u.deletingLastPathComponent().appendingPathComponent("resource-calendars.osched"))
expect(calendarReload.resourceCalendars == calendarPlan.resourceCalendars && calendarReload.resources[0].calendarID == "rc" && calendarReload.version == "0.6","resource calendar roundtrip")
expect(try WorkInterval.parse("09:00-13:00, 14:00-18:00").count == 2,"parse split shift")


let cachedLoads = Planner.loads(resource:calendarReload.resources[0],days:5,plan:calendarReload,result:try Planner.calculate(calendarReload))
expect(cachedLoads[1].capacity == 0 && cachedLoads[2].output == 60,"batch load profile agrees")
var projectHoliday = calendarReload; projectHoliday.calendar.holidays = ["2026-11-11"]
expect(try Planner.calculate(projectHoliday).timings["a"]!.finish == 4,"project holiday also removes resource working override")
var weekendOnly = calendarReload
weekendOnly.resourceCalendars![0].week = (1...7).map { ResourceWorkday(weekday:$0,intervals:[1,7].contains($0) ? [WorkInterval()] : []) }
weekendOnly.resourceCalendars![0].exceptions = []
rejects(weekendOnly,"disjoint weekly calendars rejected")
var priorityCalendar = calendarReload; priorityCalendar.levelResources = true
priorityCalendar.activities[0].priority = 100
priorityCalendar.activities.append(Activity(id:"urgent",name:"Urgent",duration:1,resource:"r",priority:900))
let priorityCalendarResult = try Planner.calculate(priorityCalendar)
expect(priorityCalendarResult.timings["urgent"]!.start == 0 && priorityCalendarResult.timings["a"]!.start >= priorityCalendarResult.timings["urgent"]!.finish,"priority respected with shifts")


let cachedAnalysis = ScheduleAnalysis(plan:Schedule.demo)
for _ in 0..<20 { _ = try cachedAnalysis.calculation() }
expect(cachedAnalysis.calculationBuildCount == 1,"one calculation per immutable revision")
let seededAnalysis = ScheduleAnalysis(plan:Schedule.demo,calculation:try Planner.calculate(.demo))
_ = try seededAnalysis.calculation()
expect(seededAnalysis.calculationBuildCount == 0,"validated result reused without recalculation")
var changedRevision = Schedule.demo; changedRevision.activities[0].duration = 8
let changedAnalysis = ScheduleAnalysis(plan:changedRevision)
expect(try changedAnalysis.calculation().duration != cachedAnalysis.calculation().duration,"new project revision gets fresh calculation")
expect(cachedAnalysis.calculationBuildCount == 1 && changedAnalysis.calculationBuildCount == 1,"revisions do not share stale results")
var invalidRevision = Schedule.demo; invalidRevision.activities[0].duration = -1
let failedAnalysis = ScheduleAnalysis(plan:invalidRevision)
for _ in 0..<2 { do { _ = try failedAnalysis.calculation(); fatalError("cached invalid revision accepted") } catch {} }
expect(failedAnalysis.calculationBuildCount == 1,"failed revision is also cached")
for day in 0..<30 { expect(cachedAnalysis.date(day) == Planner.date(day,plan:.demo),"cached date agrees with reference") }
expect(cachedAnalysis.timeline(40).dates == TimelineCalendar(plan:.demo,count:40).dates,"cached header calendar agrees")
for plan in [partial,calendarReload,Schedule.demo] {
 let calculated = try Planner.calculate(plan)
 for resource in plan.resources {
  let days = calculated.duration+5
  let loads = Planner.loads(resource:resource,days:days,plan:plan,result:calculated)
  for day in 0..<days {
   let reference = Planner.load(resource:resource,day:day,plan:plan,result:calculated), actual = loads[day]
   expect(abs(actual.quantity-reference.quantity) < 0.000001 && abs(actual.output-reference.output) < 0.000001 && actual.capacity == reference.capacity,"batch load matches day-by-day reference")
  }
 }
}
var deepHierarchy:[Activity] = []
for i in 0..<1000 { deepHierarchy.append(Activity(id:"s\(i)",name:"Summary",duration:0,kind:"summary",parent:i == 0 ? nil : "s\(i-1)")) }
let deepRows = Schedule(name:"Deep",activities:deepHierarchy,links:[],resources:[]).orderedActivities
expect(deepRows.count == 1000 && deepRows.last?.depth == 999,"iterative hierarchy preserves depth without recursive expansion")
print("PASS: \(checks) checks")
