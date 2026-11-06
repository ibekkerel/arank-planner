import Foundation

struct Activity: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var duration: Int
    var progress: Double = 0
    var resource: String = ""
    var units: Double = 1
    var volume: Double? = nil
    var productivity: Double? = nil
    var volumeUnit: String? = nil
    var ifcGlobalIds: [String] = []
    var kind: String? = nil
    var parent: String? = nil
    var earliestStart: Int? = nil
    var requestedStart: String? = nil
    var requestedFinish: String? = nil
    var lockStart: Bool? = nil
    var lockFinish: Bool? = nil
    var priority: Int? = nil
    var entityType: String { kind ?? (duration == 0 ? "milestone" : "task") }
    var effectiveDuration: Int { if entityType != "task" { return 0 }; if let v = volume, let p = productivity, p > 0 { return Int(ceil(v / p)) }; return duration }
}
struct Link: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var from: String
    var to: String
    var type: String = "FS"
    var lag: Int = 0
}
struct Resource: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var capacity: Double = 1
    var dailyRate: Double = 0
    var typeID: String? = nil
    var productivity: Double? = nil
}
struct MeasurementUnit: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var symbol: String
    static let defaults = [MeasurementUnit(id:"m3",name:"Кубический метр",symbol:"м³"),MeasurementUnit(id:"m2",name:"Квадратный метр",symbol:"м²"),MeasurementUnit(id:"m",name:"Метр",symbol:"м"),MeasurementUnit(id:"piece",name:"Штука",symbol:"шт."),MeasurementUnit(id:"person",name:"Человек",symbol:"чел."),MeasurementUnit(id:"machine",name:"Машина",symbol:"маш."),MeasurementUnit(id:"team",name:"Бригада",symbol:"бриг."),MeasurementUnit(id:"ton",name:"Тонна",symbol:"т")]
}
struct ResourceType: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var unitID: String
    var outputUnitID: String
    static let defaults = [ResourceType(id:"labor",name:"Трудовой ресурс",unitID:"person",outputUnitID:"piece"),ResourceType(id:"equipment",name:"Механизм",unitID:"machine",outputUnitID:"m3"),ResourceType(id:"team",name:"Бригада",unitID:"team",outputUnitID:"m3")]
}
struct WorkCalendar: Codable, Equatable {
    var timezone: String = "Europe/Moscow"
    var weekdays: [Int] = [2,3,4,5,6]
    var holidays: [String] = []
}
struct BaselineItem: Codable, Equatable { var start: Int; var finish: Int }
struct Schedule: Codable, Equatable {
    var format: String = "OpenSchedule"
    var version: String = "0.5"
    var id: String = UUID().uuidString
    var name: String
    var startDate: String = "2026-11-09"
    var currency: String = "RUB"
    var calendar = WorkCalendar()
    var activities: [Activity]
    var links: [Link]
    var resources: [Resource]
    var baseline: [String:BaselineItem] = [:]
    var unitCatalog: [MeasurementUnit]? = nil
    var typeCatalog: [ResourceType]? = nil
    var levelResources: Bool? = true
    static var demo: Schedule {
        Schedule(name: "Строительство · корпус А", activities: [
            Activity(id:"A",name:"Подготовка площадки",duration:4,progress:100,resource:"crew"),
            Activity(id:"B",name:"Земляные работы",duration:6,progress:40,resource:"crew"),
            Activity(id:"C",name:"Закупка конструкций",duration:9,progress:20,resource:"supply"),
            Activity(id:"D",name:"Фундамент",duration:8,resource:"crew"),
            Activity(id:"E",name:"Монтаж каркаса",duration:10,resource:"crew"),
            Activity(id:"F",name:"Инженерные системы",duration:7,resource:"mep"),
            Activity(id:"G",name:"Приёмка",duration:0)],
            links:[Link(from:"A",to:"B"),Link(from:"A",to:"C"),Link(from:"B",to:"D"),Link(from:"D",to:"E"),Link(from:"C",to:"E"),Link(from:"E",to:"F"),Link(from:"F",to:"G")],
            resources:[Resource(id:"crew",name:"Строительная бригада",dailyRate:45000),Resource(id:"supply",name:"Снабжение",dailyRate:18000),Resource(id:"mep",name:"Инженерная бригада",dailyRate:38000)])
    }
}
struct Timing { var start: Int; var finish: Int; var lateStart: Int; var float: Int }
struct Calculation { var timings: [String:Timing]; var duration: Int; var conflicts: [String]; var cost: Double }
enum PlanError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let s) = self { return s }; return nil }
}
struct Planner {
    static func calculate(_ plan: Schedule) throws -> Calculation {
        guard plan.format == "OpenSchedule", ["0.1","0.2","0.3","0.4","0.5"].contains(plan.version) else { throw PlanError.invalid("Неподдерживаемый формат или версия") }
        guard !plan.calendar.weekdays.isEmpty, Set(plan.calendar.weekdays).count == plan.calendar.weekdays.count, plan.calendar.weekdays.allSatisfy({(1...7).contains($0)}), TimeZone(identifier: plan.calendar.timezone) != nil else { throw PlanError.invalid("Неверный рабочий календарь") }
        guard validDate(plan.startDate), plan.calendar.holidays.allSatisfy(validDate) else { throw PlanError.invalid("Дата должна иметь вид ГГГГ-ММ-ДД") }
        let ids = plan.activities.map(\.id)
        guard Set(ids).count == ids.count, ids.allSatisfy({ !$0.isEmpty }) else { throw PlanError.invalid("Идентификаторы работ должны быть непустыми и уникальными") }
        guard Set(plan.resources.map(\.id)).count == plan.resources.count, plan.resources.allSatisfy({ !$0.id.isEmpty && $0.capacity.isFinite && $0.capacity > 0 && $0.dailyRate.isFinite && $0.dailyRate >= 0 }) else { throw PlanError.invalid("Неверные ресурсы") }
        let catalog = plan.measurementUnits, types = plan.resourceTypes
        guard Set(catalog.map(\.id)).count == catalog.count, Set(catalog.map(\.symbol)).count == catalog.count, catalog.allSatisfy({ !$0.id.isEmpty && !$0.name.trimmingCharacters(in:.whitespaces).isEmpty && !$0.symbol.trimmingCharacters(in:.whitespaces).isEmpty }) else { throw PlanError.invalid("Единицы измерения должны иметь уникальные коды и обозначения") }
        guard Set(types.map(\.id)).count == types.count, types.allSatisfy({ !$0.id.isEmpty && !$0.name.trimmingCharacters(in:.whitespaces).isEmpty }) else { throw PlanError.invalid("Неверные типы ресурсов") }
        for type in types { guard catalog.contains(where:{ $0.id == type.unitID }), catalog.contains(where:{ $0.id == type.outputUnitID }) else { throw PlanError.invalid("Тип ресурса ссылается на отсутствующую единицу измерения") } }
        for resource in plan.resources {
            if let id = resource.typeID { guard types.contains(where:{ $0.id == id }) else { throw PlanError.invalid("Неизвестный тип ресурса") } }
            if let value = resource.productivity { guard value.isFinite, value > 0, resource.typeID != nil else { throw PlanError.invalid("Для производительности ресурса нужны тип и значение > 0") } }
        }
        let resources = Dictionary(uniqueKeysWithValues: plan.resources.map { ($0.id,$0) })
        for a in plan.activities {
            guard a.duration >= 0, a.duration <= 100000, a.progress.isFinite, (0...100).contains(a.progress), a.units.isFinite, a.units > 0, a.resource.isEmpty || resources[a.resource] != nil else { throw PlanError.invalid("Неверные параметры работы \(a.id)") }
            if let v = a.volume { guard v.isFinite, v >= 0 else { throw PlanError.invalid("Объём должен быть неотрицательным числом") } }
            if let p = a.productivity { guard let v = a.volume, p.isFinite, p > 0, v/p <= 100000 else { throw PlanError.invalid("Для производительности нужен объём; производительность > 0, длительность ≤ 100000") } }
            if let unit = a.volumeUnit, unit.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { throw PlanError.invalid("Единица измерения не должна быть пустой строкой") }
            if let bound = a.earliestStart { guard (0...100000).contains(bound), a.entityType != "summary" else { throw PlanError.invalid("Неверная граница начала задачи") } }
            if let unit = a.volumeUnit { guard catalog.contains(where:{ $0.symbol == unit }) else { throw PlanError.invalid("Добавьте единицу «\(unit)» в справочник") } }
            if a.volume != nil, a.productivity == nil, let r = resources[a.resource], r.productivity != nil {
                let rate = r.productivity! * a.units
                guard rate.isFinite, rate > 0 else { throw PlanError.invalid("Производительность назначения должна быть конечной и положительной") }
                let type = types.first { $0.id == r.typeID }
                let output = catalog.first { $0.id == type?.outputUnitID }
                guard a.volumeUnit == output?.symbol else { throw PlanError.invalid("Единица объёма задачи \(a.id) должна совпадать с единицей выработки ресурса") }
            }
            guard (0...1000).contains(a.priority ?? 500) else { throw PlanError.invalid("Приоритет должен быть от 0 до 1000; большее число — раньше") }
            if a.entityType == "summary", a.requestedStart != nil || a.requestedFinish != nil || a.lockStart == true || a.lockFinish == true { throw PlanError.invalid("Даты суммарной задачи вычисляются по вложенным задачам") }
            if a.lockStart == true && a.requestedStart == nil || a.lockFinish == true && a.requestedFinish == nil { throw PlanError.invalid("Сначала назначьте фиксируемую дату") }
            guard plan.duration(of:a) <= 100000 else { throw PlanError.invalid("Расчётная длительность превышает 100000 рабочих дней") }

        }
        guard Set(plan.links.map(\.id)).count == plan.links.count else { throw PlanError.invalid("Повторяющиеся идентификаторы связей") }
        let tasks = Dictionary(uniqueKeysWithValues: plan.activities.map { ($0.id,$0) })
        for a in plan.activities {
            guard ["task","milestone","summary"].contains(a.entityType) else { throw PlanError.invalid("Неизвестный тип задачи") }
            if a.entityType != "task" && (!a.resource.isEmpty || a.volume != nil || a.productivity != nil || a.volumeUnit != nil || a.duration != 0) { throw PlanError.invalid("Веха и суммарная задача не имеют собственной длительности, объёма или назначений") }
            var visited: Set<String> = [a.id]; var parent = a.parent
            while let id = parent {
                guard let node = tasks[id], node.entityType == "summary", !visited.contains(id) else { throw PlanError.invalid("Неверная иерархия: родитель должен быть суммарной задачей; циклы запрещены") }
                visited.insert(id); parent = node.parent
            }
        }
        let executableIDs = ids.filter { tasks[$0]!.entityType != "summary" }
        var indegree = Dictionary(uniqueKeysWithValues: executableIDs.map { ($0,0) })
        var outgoing: [String:[Link]] = [:]
        for l in plan.links {
            guard tasks[l.from] != nil, tasks[l.to] != nil, l.from != l.to, ["FS","SS","FF","SF"].contains(l.type), (-100000...100000).contains(l.lag) else { throw PlanError.invalid("Неверная связь \(l.from) → \(l.to)") }
            guard tasks[l.from]!.entityType != "summary", tasks[l.to]!.entityType != "summary" else { throw PlanError.invalid("Связывайте задачи или вехи внутри суммарной задачи") }
            indegree[l.to,default:0] += 1
            outgoing[l.from,default:[]].append(l)
        }
        var queue = executableIDs.filter { indegree[$0] == 0 }; var order: [String] = []; var index = 0
        while index < queue.count {
            let id = queue[index]; index += 1; order.append(id)
            for l in outgoing[id,default:[]] { indegree[l.to]! -= 1; if indegree[l.to] == 0 { queue.append(l.to) } }
        }
        guard order.count == executableIDs.count else { throw PlanError.invalid("Обнаружен цикл зависимостей. Удалите замыкающую связь.") }
        func weight(_ l: Link) -> Int {
            let a = plan.duration(of:tasks[l.from]!), b = plan.duration(of:tasks[l.to]!)
            switch l.type { case "SS": return l.lag; case "FF": return a - b + l.lag; case "SF": return -b + l.lag; default: return a + l.lag }
        }
        var lower:[String:Int] = [:], upper:[String:Int] = [:], exact:[String:Int] = [:]
        let horizon = 1000000
        for id in executableIDs {
            let task = tasks[id]!, duration = plan.duration(of:tasks[id]!)
            var lo = task.earliestStart ?? 0, hi = Int.max/4
            if let date = task.requestedStart {
                let day = try offset(for:date,plan:plan); lo = max(lo,day)
                if task.lockStart == true { hi = min(hi,day); exact[id] = day }
            }
            if let date = task.requestedFinish {
                let day = try offset(for:date,plan:plan) + (duration > 0 ? 1 : 0) - duration
                guard day >= 0 else { throw PlanError.invalid("Окончание задачи \(id) раньше допустимого для её длительности") }
                lo = max(lo,day)
                if task.lockFinish == true { hi = min(hi,day); if let fixed = exact[id], fixed != day { throw PlanError.invalid("Фиксированные начало и окончание задачи \(id) не соответствуют длительности") }; exact[id] = day }
            }
            guard lo <= hi else { throw PlanError.invalid("Противоречивые условия дат задачи \(id)") }
            lower[id] = lo; upper[id] = hi
        }
        for id in order { for link in outgoing[id,default:[]] { lower[link.to] = max(lower[link.to]!,lower[id]!+weight(link)) } }
        for id in order.reversed() { for link in outgoing[id,default:[]] { upper[id] = min(upper[id]!,upper[link.to]!-weight(link)) } }
        for id in executableIDs where lower[id]! > upper[id]! { throw PlanError.invalid("Связи противоречат фиксированной дате: \(id). Изменение не применено.") }
        var early = lower
        if plan.levelResources ?? true {
            struct Reservation { let id:String; let start:Int; let finish:Int; let units:Double }
            var reservations:[String:[Reservation]] = [:]
            for id in executableIDs {
                let task = tasks[id]!
                if let fixed = exact[id], !task.resource.isEmpty, plan.duration(of:task) > 0 { reservations[task.resource,default:[]].append(Reservation(id:id,start:fixed,finish:fixed+plan.duration(of:task),units:task.units)) }
            }
            func feasible(_ id:String,_ start:Int) -> Bool {
                let task = tasks[id]!, duration = plan.duration(of:tasks[id]!)
                guard duration > 0, let resource = resources[task.resource] else { return true }
                var events:[Int:Double] = [start:task.units,start+duration:-task.units]
                for entry in reservations[task.resource,default:[]] where entry.id != id && entry.start < start+duration && entry.finish > start {
                    events[max(start,entry.start),default:0] += entry.units; events[min(start+duration,entry.finish),default:0] -= entry.units
                }
                var load = 0.0
                for day in events.keys.sorted() { load += events[day]!; if load > resource.capacity + 0.000001 { return false } }
                return true
            }
            var remaining = Set(executableIDs), scheduled = Set<String>()
            let originalIndex = Dictionary(uniqueKeysWithValues:executableIDs.enumerated().map { ($0.element,$0.offset) })
            let incoming = Dictionary(grouping:plan.links,by: \.to)
            while !remaining.isEmpty {
                let ready = remaining.filter { id in incoming[id,default:[]].allSatisfy { scheduled.contains($0.from) } }.sorted { a,b in
                    let deadlineA = upper[a]! <= horizon ? upper[a]! : Int.max, deadlineB = upper[b]! <= horizon ? upper[b]! : Int.max
                    if deadlineA != deadlineB { return deadlineA < deadlineB }
                    if (tasks[a]!.priority ?? 500) != (tasks[b]!.priority ?? 500) { return (tasks[a]!.priority ?? 500) > (tasks[b]!.priority ?? 500) }
                    return originalIndex[a]! < originalIndex[b]!
                }
                guard let id = ready.first else { throw PlanError.invalid("Не удалось выбрать следующую задачу") }
                let task = tasks[id]!, duration = plan.duration(of:tasks[id]!)
                if !task.resource.isEmpty, duration > 0, task.units > resources[task.resource]!.capacity + 0.000001 { throw PlanError.invalid("Потребность задачи \(id) превышает доступность ресурса") }
                var start = lower[id]!
                for link in incoming[id,default:[]] { start = max(start,early[link.from]!+weight(link)) }
                if let fixed = exact[id] { start = max(start,fixed) }
                while !feasible(id,start) {
                    guard exact[id] == nil else { throw PlanError.invalid("Фиксированная дата задачи \(id) вызывает конфликт ресурса") }
                    guard let next = reservations[task.resource,default:[]].filter({ $0.finish > start && $0.start < start+duration }).map(\.finish).min() else { throw PlanError.invalid("Не найден доступный интервал ресурса") }
                    start = next
                }
                guard start <= upper[id]!, start <= horizon else { throw PlanError.invalid("Не найдено расписание для \(id) в пределах фиксированных дат. Измените приоритеты, доступность или ограничения.") }
                early[id] = start
                if exact[id] == nil, !task.resource.isEmpty, duration > 0 { reservations[task.resource,default:[]].append(Reservation(id:id,start:start,finish:start+duration,units:task.units)) }
                remaining.remove(id); scheduled.insert(id)
            }
        }
        let end = executableIDs.map { early[$0]! + plan.duration(of:tasks[$0]!) }.max() ?? 0
        var late = Dictionary(uniqueKeysWithValues:executableIDs.map { ($0,min(end-plan.duration(of:tasks[$0]!),upper[$0]!)) })
        for id in order.reversed() { for link in outgoing[id,default:[]] { late[id] = min(late[id]!,late[link.to]!-weight(link)) } }
        var timings: [String:Timing] = [:]
        for id in executableIDs { timings[id] = Timing(start:early[id]!,finish:early[id]! + plan.duration(of:tasks[id]!),lateStart:late[id]!,float:late[id]! - early[id]!) }
        func aggregate(_ id: String) -> Timing {
            if let t = timings[id] { return t }
            let children = plan.activities.filter { $0.parent == id }.map { aggregate($0.id) }
            let start = children.map(\.start).min() ?? 0, finish = children.map(\.finish).max() ?? 0
            let reserve = children.map(\.float).min() ?? 0
            let t = Timing(start:start,finish:finish,lateStart:start + reserve,float:reserve)
            timings[id] = t; return t
        }
        for a in plan.activities where a.entityType == "summary" { _ = aggregate(a.id) }
        var conflicts: [String] = []
        for r in plan.resources {
            var events: [Int:Double] = [:]
            for a in plan.activities where a.resource == r.id && plan.duration(of:a) > 0 { let t = timings[a.id]!; events[t.start,default:0] += a.units; events[t.finish,default:0] -= a.units }
            var load = 0.0; var peak = 0.0
            for day in events.keys.sorted() { load += events[day]!; peak = max(peak,load) }
            if peak > r.capacity + 0.000001 { conflicts.append("\(r.name): пик \(String(format:"%.1f",peak)) при доступности \(String(format:"%.1f",r.capacity))") }
        }
        let cost = plan.activities.reduce(0.0) { $0 + Double(plan.duration(of:$1)) * $1.units * (resources[$1.resource]?.dailyRate ?? 0) }
        return Calculation(timings:timings,duration:end,conflicts:conflicts,cost:cost)
    }
    static func validDate(_ value: String) -> Bool {
        let f = DateFormatter(); f.locale = Locale(identifier:"en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT:0); f.dateFormat = "yyyy-MM-dd"; f.isLenient = false
        guard let d = f.date(from:value) else { return false }; return f.string(from:d) == value
    }
    static func date(_ offset: Int, plan: Schedule) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier:"en_US_POSIX"); f.timeZone = TimeZone(identifier:plan.calendar.timezone); f.dateFormat = "yyyy-MM-dd"
        var c = Calendar(identifier:.gregorian); c.timeZone = f.timeZone
        guard var d = f.date(from:plan.startDate) else { return "—" }
        func working(_ d: Date) -> Bool { plan.calendar.weekdays.contains(c.component(.weekday,from:d)) && !plan.calendar.holidays.contains(f.string(from:d)) }
        while !working(d) { d = c.date(byAdding:.day,value:1,to:d)! }
        for _ in 0..<max(0,offset) { repeat { d = c.date(byAdding:.day,value:1,to:d)! } while !working(d) }
        return f.string(from:d)
    }
    static func load(_ url: URL) throws -> Schedule {
        let data = try Data(contentsOf:url)
        // Unknown fields must not be silently dropped by this version.
        let root = try JSONSerialization.jsonObject(with:data) as? [String:Any] ?? [:]
        func check(_ object: [String:Any], allowed: Set<String>) throws { let unknown = Set(object.keys).subtracting(allowed); if !unknown.isEmpty { throw PlanError.invalid("Неизвестные поля: \(unknown.sorted().joined(separator:", ")). Файл не изменён.") } }
        try check(root,allowed:["format","version","id","name","startDate","currency","calendar","activities","links","resources","baseline","unitCatalog","typeCatalog","levelResources"])
        for (key,fields) in [("activities",Set(["id","name","duration","progress","resource","units","volume","productivity","ifcGlobalIds","kind","parent","volumeUnit","earliestStart","requestedStart","requestedFinish","lockStart","lockFinish","priority"])),("links",Set(["id","from","to","type","lag"])),("resources",Set(["id","name","capacity","dailyRate","typeID","productivity"])),("unitCatalog",Set(["id","name","symbol"])),("typeCatalog",Set(["id","name","unitID","outputUnitID"]))] {
            for obj in root[key] as? [[String:Any]] ?? [] { try check(obj,allowed:fields) }
        }
        if let calendar = root["calendar"] as? [String:Any] { try check(calendar,allowed:["timezone","weekdays","holidays"]) }
        if let baseline = root["baseline"] as? [String:[String:Any]] { for obj in baseline.values { try check(obj,allowed:["start","finish"]) } }
        var p = try JSONDecoder().decode(Schedule.self,from:data)
        guard p.format == "OpenSchedule", ["0.1","0.2","0.3","0.4","0.5"].contains(p.version) else { throw PlanError.invalid("Неподдерживаемый формат или версия") }
        for i in p.activities.indices { if p.activities[i].kind == nil { p.activities[i].kind = p.activities[i].duration == 0 ? "milestone" : "task" } }
        p.version = "0.5"
        if p.unitCatalog == nil {
            var units = MeasurementUnit.defaults
            for symbol in p.activities.compactMap(\.volumeUnit) where !units.contains(where:{ $0.symbol == symbol }) { units.append(MeasurementUnit(name:symbol,symbol:symbol)) }
            p.unitCatalog = units
        }
        _ = try calculate(p); return p
    }
    static func save(_ plan: Schedule, to url: URL) throws {
        _ = try calculate(plan)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]
        var normalized = plan; normalized.version = "0.5"
        for i in normalized.activities.indices { normalized.activities[i].kind = normalized.activities[i].entityType }
        normalized.unitCatalog = plan.measurementUnits; normalized.typeCatalog = plan.resourceTypes; normalized.levelResources = plan.levelResources ?? true
        try encoder.encode(normalized).write(to:url,options:.atomic)
    }
}

extension Schedule {
    func children(of parent: String?) -> [Activity] { activities.filter { $0.parent == parent } }
    var orderedActivities: [(activity:Activity,depth:Int)] {
        func walk(_ parent: String?, _ depth: Int) -> [(Activity,Int)] { children(of:parent).flatMap { [($0,depth)] + walk($0.id,depth+1) } }
        return walk(nil,0)
    }
    func descendants(of id: String) -> Set<String> { var result: Set<String> = [id]; for a in children(of:id) { result.formUnion(descendants(of:a.id)) }; return result }
}
enum EntityKind {
    static let values = ["task","milestone","summary"]
    static func title(_ value: String) -> String { switch value { case "milestone": return "Веха"; case "summary": return "Суммарная"; default: return "Задача" } }
    static func icon(_ value: String) -> String { switch value { case "milestone": return "diamond.fill"; case "summary": return "folder.fill"; default: return "rectangle.fill" } }
}
enum DependencyKind {
    static let values = ["FS","SS","FF","SF"]
    static func title(_ value: String) -> String { switch value { case "SS": return "СС · Старт–Старт"; case "FF": return "ФФ · Финиш–Финиш"; case "SF": return "СФ · Старт–Финиш"; default: return "ФС · Финиш–Старт" } }
}

struct ConnectionEndpoint: Equatable {
    let activityID: String
    let finish: Bool
    static func dependency(from: ConnectionEndpoint, to: ConnectionEndpoint) -> String {
        (from.finish ? "F" : "S") + (to.finish ? "F" : "S")
    }
}

extension Schedule {
    var measurementUnits: [MeasurementUnit] { unitCatalog ?? MeasurementUnit.defaults }
    var resourceTypes: [ResourceType] { typeCatalog ?? ResourceType.defaults }
    func duration(of activity:Activity) -> Int {
        guard activity.entityType == "task" else { return 0 }
        guard let volume = activity.volume else { return activity.duration }
        let rate: Double?
        if let explicit = activity.productivity { rate = explicit }
        else if let resource = resources.first(where:{ $0.id == activity.resource }), let productivity = resource.productivity { rate = productivity * activity.units }
        else { rate = nil }
        guard let rate, rate.isFinite, rate > 0 else { return activity.duration }
        let value = ceil(volume/rate)
        return value.isFinite && value >= 0 && value <= 100000 ? Int(value) : 100001
    }
}
struct MoveProposal: Identifiable {
    var id = UUID()
    let original: Schedule
    let proposed: Schedule
    let activityID: String
    let requestedStart: Int
    let before: Calculation
    let after: Calculation
    var changedIDs: [String] { original.activities.filter { let a = before.timings[$0.id], b = after.timings[$0.id]; return a?.start != b?.start || a?.finish != b?.finish }.map(\.id) }
    var impactedIDs: [String] { original.activities.filter { let a = before.timings[$0.id], b = after.timings[$0.id]; return a?.start != b?.start || a?.finish != b?.finish || a?.float != b?.float }.map(\.id) }
    var linked: Bool { original.links.contains { $0.from == activityID || $0.to == activityID } }
    var achieved: Bool { after.timings[activityID]?.start == requestedStart }
}
extension Planner {
    static func move(_ plan:Schedule, activityID:String, to start:Int) throws -> MoveProposal {
        guard let index = plan.activities.firstIndex(where:{ $0.id == activityID }), plan.activities[index].entityType != "summary", (0...100000).contains(start) else { throw PlanError.invalid("Перемещать можно задачи и вехи в пределах шкалы проекта") }
        guard plan.activities[index].lockStart != true, plan.activities[index].lockFinish != true else { throw PlanError.invalid("Дата задачи зафиксирована. Снимите флажок фиксации перед переносом.") }
        var proposed = plan; proposed.activities[index].earliestStart = start; proposed.activities[index].requestedStart = nil; proposed.activities[index].requestedFinish = nil
        return MoveProposal(original:plan,proposed:proposed,activityID:activityID,requestedStart:start,before:try calculate(plan),after:try calculate(proposed))
    }
    static func finishDate(_ timing:Timing, plan:Schedule) -> String { date(timing.finish > timing.start ? timing.finish-1 : timing.finish,plan:plan) }
    static func projectFinishDate(_ calculation:Calculation, plan:Schedule) -> String {
        let last = calculation.timings.values.map { $0.finish > $0.start ? $0.finish-1 : $0.finish }.max() ?? 0
        return date(last,plan:plan)
    }
}

extension Planner {
    static func offset(for value:String,plan:Schedule) throws -> Int {
        guard validDate(value) else { throw PlanError.invalid("Дата должна иметь вид ГГГГ-ММ-ДД") }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier:"en_US_POSIX"); formatter.timeZone = TimeZone(identifier:plan.calendar.timezone); formatter.dateFormat = "yyyy-MM-dd"
        var calendar = Calendar(identifier:.gregorian); calendar.timeZone = formatter.timeZone
        let target = formatter.date(from:value)!
        guard plan.calendar.weekdays.contains(calendar.component(.weekday,from:target)), !plan.calendar.holidays.contains(value) else { throw PlanError.invalid("Выберите рабочий день календаря проекта") }
        var current = formatter.date(from:date(0,plan:plan))!; var count = 0
        guard target >= current else { throw PlanError.invalid("Дата раньше начала проекта") }
        while current < target {
            current = calendar.date(byAdding:.day,value:1,to:current)!
            if plan.calendar.weekdays.contains(calendar.component(.weekday,from:current)), !plan.calendar.holidays.contains(formatter.string(from:current)) { count += 1 }
            guard count <= 100000 else { throw PlanError.invalid("Дата слишком далеко от начала проекта") }
        }
        return count
    }
    static func group(_ plan:Schedule,ids:Set<String>,name:String = "Новая суммарная задача") throws -> Schedule {
        let roots = plan.activities.filter { task in ids.contains(task.id) && !plan.activities.contains(where:{ ids.contains($0.id) && $0.id != task.id && plan.descendants(of:$0.id).contains(task.id) }) }
        guard roots.count >= 2 else { throw PlanError.invalid("Выберите минимум две задачи одного уровня") }
        guard roots.allSatisfy({ $0.parent == roots[0].parent }) else { throw PlanError.invalid("Для объединения выберите задачи с одним родителем") }
        var result = plan; let id = UUID().uuidString
        let indices = roots.compactMap { root in plan.activities.firstIndex { $0.id == root.id } }
        for i in indices { result.activities[i].parent = id }
        result.activities.insert(Activity(id:id,name:name,duration:0,kind:"summary",parent:roots[0].parent),at:indices.min()!)
        _ = try calculate(result); return result
    }
}
struct ResourceDay {
    let quantity:Double
    let capacity:Double
    let output:Double
    let outputCapacity:Double?
}
extension Planner {
    static func load(resource:Resource,day:Int,plan:Schedule,result:Calculation) -> ResourceDay {
        var quantity = 0.0, output = 0.0
        let type = plan.resourceTypes.first { $0.id == resource.typeID }
        let symbol = plan.measurementUnits.first { $0.id == type?.outputUnitID }?.symbol
        for task in plan.activities where task.resource == resource.id {
            guard let timing = result.timings[task.id], timing.start <= day, day < timing.finish else { continue }
            quantity += task.units
            if let volume = task.volume, task.volumeUnit == symbol, let rate = task.productivity ?? resource.productivity.map({ $0 * task.units }) {
                output += min(rate,max(0,volume-rate*Double(day-timing.start)))
            }
        }
        return ResourceDay(quantity:quantity,capacity:resource.capacity,output:output,outputCapacity:resource.productivity.map { $0*resource.capacity })
    }
}

// Monday-first Gregorian calendar grid. Dates remain ISO strings in the project file.
enum CalendarGrid {
    static func days(year:Int,month:Int) -> [String?] {
        var calendar = Calendar(identifier:.gregorian); calendar.timeZone = TimeZone(secondsFromGMT:0)!
        guard (1...9999).contains(year), (1...12).contains(month), let first = calendar.date(from:DateComponents(year:year,month:month,day:1)), let count = calendar.range(of:.day,in:.month,for:first)?.count else { return [] }
        let offset = (calendar.component(.weekday,from:first)+5)%7
        return (0..<42).map { index in let day = index-offset+1; return (1...count).contains(day) ? String(format:"%04d-%02d-%02d",year,month,day) : nil }
    }
}

struct TimelineBand:Identifiable {
    var id:Int { start }
    let start:Int
    var count:Int
    let label:String
}
struct TimelineCalendar {
    let dates:[String]
    let years:[TimelineBand]
    let months:[TimelineBand]
    init(plan:Schedule,count:Int) {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier:"en_US_POSIX"); formatter.timeZone = TimeZone(identifier:plan.calendar.timezone); formatter.dateFormat = "yyyy-MM-dd"
        var calendar = Calendar(identifier:.gregorian); calendar.timeZone = formatter.timeZone
        var current = formatter.date(from:plan.startDate)!
        let names = ["Январь","Февраль","Март","Апрель","Май","Июнь","Июль","Август","Сентябрь","Октябрь","Ноябрь","Декабрь"]
        var dates:[String] = [], years:[TimelineBand] = [], months:[TimelineBand] = []
        for index in 0..<max(0,count) {
            while !plan.calendar.weekdays.contains(calendar.component(.weekday,from:current)) || plan.calendar.holidays.contains(formatter.string(from:current)) { current = calendar.date(byAdding:.day,value:1,to:current)! }
            let date = formatter.string(from:current), year = String(date.prefix(4)), month = names[calendar.component(.month,from:current)-1]
            if years.last?.label == year { years[years.count-1].count += 1 } else { years.append(TimelineBand(start:index,count:1,label:year)) }
            if months.last?.label == month && dates.last?.prefix(4) == date.prefix(4) { months[months.count-1].count += 1 } else { months.append(TimelineBand(start:index,count:1,label:month)) }
            dates.append(date); current = calendar.date(byAdding:.day,value:1,to:current)!
        }
        self.dates = dates; self.years = years; self.months = months
    }
}
