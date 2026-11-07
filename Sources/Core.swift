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
    var calendarID: String? = nil
    var timeUnit: String? = nil
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
    var version: String = "0.6"
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
    var resourceCalendars: [ResourceCalendar]? = nil
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
    static func calculate(_ plan: Schedule, applyResourceCalendars: Bool = true, validationOnly: Bool = false) throws -> Calculation {
        guard plan.format == "OpenSchedule", ["0.1","0.2","0.3","0.4","0.5","0.6"].contains(plan.version) else { throw PlanError.invalid("Неподдерживаемый формат или версия") }
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
        try ResourceCalendar.validate(plan)
        let resources = Dictionary(uniqueKeysWithValues: plan.resources.map { ($0.id,$0) })
        let durations = Dictionary(uniqueKeysWithValues:plan.activities.map { ($0.id,plan.duration(of:$0)) })
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
            guard durations[a.id]! <= 100000 else { throw PlanError.invalid("Расчётная длительность превышает 100000 рабочих дней") }

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
        if validationOnly { return Calculation(timings:[:],duration:0,conflicts:[],cost:0) }
        if applyResourceCalendars && plan.resources.contains(where:{ $0.calendarID != nil || $0.timeUnit == "hour" }) {
            return try CalendarScheduler.calculate(plan)
        }
        func weight(_ l: Link) -> Int {
            let a = durations[l.from]!, b = durations[l.to]!
            switch l.type { case "SS": return l.lag; case "FF": return a - b + l.lag; case "SF": return -b + l.lag; default: return a + l.lag }
        }
        var lower:[String:Int] = [:], upper:[String:Int] = [:], exact:[String:Int] = [:]
        let horizon = 1000000
        for id in executableIDs {
            let task = tasks[id]!, duration = durations[id]!
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
                if let fixed = exact[id], !task.resource.isEmpty, durations[task.id]! > 0 { reservations[task.resource,default:[]].append(Reservation(id:id,start:fixed,finish:fixed+durations[task.id]!,units:task.units)) }
            }
            func feasible(_ id:String,_ start:Int) -> Bool {
                let task = tasks[id]!, duration = durations[id]!
                guard duration > 0, let resource = resources[task.resource] else { return true }
                var events:[Int:Double] = [start:task.units,start+duration:-task.units]
                for entry in reservations[task.resource,default:[]] where entry.id != id && entry.start < start+duration && entry.finish > start {
                    events[max(start,entry.start),default:0] += entry.units; events[min(start+duration,entry.finish),default:0] -= entry.units
                }
                var load = 0.0
                for day in events.keys.sorted() { load += events[day]!; if load > resource.capacity + 0.000001 { return false } }
                return true
            }
            let originalIndex = Dictionary(uniqueKeysWithValues:executableIDs.enumerated().map { ($0.element,$0.offset) })
            let incoming = Dictionary(grouping:plan.links,by: \.to)
            var pendingParents = Dictionary(uniqueKeysWithValues:executableIDs.map { ($0,incoming[$0,default:[]].count) })
            var ready = ReadyTaskQueue { a,b in
                let deadlineA = upper[a]! <= horizon ? upper[a]! : Int.max, deadlineB = upper[b]! <= horizon ? upper[b]! : Int.max
                if deadlineA != deadlineB { return deadlineA < deadlineB }
                if (tasks[a]!.priority ?? 500) != (tasks[b]!.priority ?? 500) { return (tasks[a]!.priority ?? 500) > (tasks[b]!.priority ?? 500) }
                return originalIndex[a]! < originalIndex[b]!
            }
            for id in executableIDs where pendingParents[id] == 0 { ready.insert(id) }
            var scheduledCount = 0
            while scheduledCount < executableIDs.count {
                guard let id = ready.pop() else { throw PlanError.invalid("Не удалось выбрать следующую задачу") }
                let task = tasks[id]!, duration = durations[id]!
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
                scheduledCount += 1
                for link in outgoing[id,default:[]] {
                    pendingParents[link.to]! -= 1
                    if pendingParents[link.to] == 0 { ready.insert(link.to) }
                }
            }
        }
        let end = executableIDs.map { early[$0]! + durations[$0]! }.max() ?? 0
        var late = Dictionary(uniqueKeysWithValues:executableIDs.map { ($0,min(end-durations[$0]!,upper[$0]!)) })
        for id in order.reversed() { for link in outgoing[id,default:[]] { late[id] = min(late[id]!,late[link.to]!-weight(link)) } }
        var timings: [String:Timing] = [:]
        for id in executableIDs { timings[id] = Timing(start:early[id]!,finish:early[id]! + durations[id]!,lateStart:late[id]!,float:late[id]! - early[id]!) }
        let childrenByParent = Dictionary(grouping:plan.activities,by:{ $0.parent ?? "" })
        func aggregate(_ id: String) -> Timing {
            if let t = timings[id] { return t }
            let children = childrenByParent[id,default:[]].map { aggregate($0.id) }
            let start = children.map(\.start).min() ?? 0, finish = children.map(\.finish).max() ?? 0
            let reserve = children.map(\.float).min() ?? 0
            let t = Timing(start:start,finish:finish,lateStart:start + reserve,float:reserve)
            timings[id] = t; return t
        }
        for a in plan.activities where a.entityType == "summary" { _ = aggregate(a.id) }
        var conflicts: [String] = []
        for r in plan.resources {
            var events: [Int:Double] = [:]
            for a in plan.activities where a.resource == r.id && durations[a.id]! > 0 { let t = timings[a.id]!; events[t.start,default:0] += a.units; events[t.finish,default:0] -= a.units }
            var load = 0.0; var peak = 0.0
            for day in events.keys.sorted() { load += events[day]!; peak = max(peak,load) }
            if peak > r.capacity + 0.000001 { conflicts.append("\(r.name): пик \(String(format:"%.1f",peak)) при доступности \(String(format:"%.1f",r.capacity))") }
        }
        let cost = plan.activities.reduce(0.0) { $0 + Double(durations[$1.id]!) * $1.units * (resources[$1.resource]?.dailyRate ?? 0) }
        return Calculation(timings:timings,duration:end,conflicts:conflicts,cost:cost)
    }
    static func validDate(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45 else { return false }
        for index in [0,1,2,3,5,6,8,9] where !(48...57).contains(bytes[index]) { return false }
        let year = Int(bytes[0]-48)*1000+Int(bytes[1]-48)*100+Int(bytes[2]-48)*10+Int(bytes[3]-48)
        let month = Int(bytes[5]-48)*10+Int(bytes[6]-48), day = Int(bytes[8]-48)*10+Int(bytes[9]-48)
        guard year > 0, (1...12).contains(month) else { return false }
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        let limits = [31,leap ? 29 : 28,31,30,31,30,31,31,30,31,30,31]
        return day >= 1 && day <= limits[month-1]
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
        try check(root,allowed:["format","version","id","name","startDate","currency","calendar","activities","links","resources","baseline","unitCatalog","typeCatalog","levelResources","resourceCalendars"])
        for (key,fields) in [("activities",Set(["id","name","duration","progress","resource","units","volume","productivity","ifcGlobalIds","kind","parent","volumeUnit","earliestStart","requestedStart","requestedFinish","lockStart","lockFinish","priority"])),("links",Set(["id","from","to","type","lag"])),("resources",Set(["id","name","capacity","dailyRate","typeID","productivity","calendarID","timeUnit"])),("unitCatalog",Set(["id","name","symbol"])),("typeCatalog",Set(["id","name","unitID","outputUnitID"]))] {
            for obj in root[key] as? [[String:Any]] ?? [] { try check(obj,allowed:fields) }
        }
        for obj in root["resourceCalendars"] as? [[String:Any]] ?? [] {
            try check(obj,allowed:["id","name","week","exceptions"])
            for day in obj["week"] as? [[String:Any]] ?? [] {
                try check(day,allowed:["weekday","intervals"])
                for interval in day["intervals"] as? [[String:Any]] ?? [] { try check(interval,allowed:["start","end"]) }
            }
            for exception in obj["exceptions"] as? [[String:Any]] ?? [] {
                try check(exception,allowed:["id","name","from","through","kind","intervals"])
                for interval in exception["intervals"] as? [[String:Any]] ?? [] { try check(interval,allowed:["start","end"]) }
            }
        }
        if let calendar = root["calendar"] as? [String:Any] { try check(calendar,allowed:["timezone","weekdays","holidays"]) }
        if let baseline = root["baseline"] as? [String:[String:Any]] { for obj in baseline.values { try check(obj,allowed:["start","finish"]) } }
        var p = try JSONDecoder().decode(Schedule.self,from:data)
        guard p.format == "OpenSchedule", ["0.1","0.2","0.3","0.4","0.5","0.6"].contains(p.version) else { throw PlanError.invalid("Неподдерживаемый формат или версия") }
        for i in p.activities.indices { if p.activities[i].kind == nil { p.activities[i].kind = p.activities[i].duration == 0 ? "milestone" : "task" } }
        p.version = "0.6"
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
        var normalized = plan; normalized.version = "0.6"
        for i in normalized.activities.indices { normalized.activities[i].kind = normalized.activities[i].entityType }
        normalized.unitCatalog = plan.measurementUnits; normalized.typeCatalog = plan.resourceTypes; normalized.levelResources = plan.levelResources ?? true
        try encoder.encode(normalized).write(to:url,options:.atomic)
    }
}

extension Schedule {
    func children(of parent: String?) -> [Activity] { activities.filter { $0.parent == parent } }
    var orderedActivities: [(activity:Activity,depth:Int)] {
        let groups = Dictionary(grouping:activities,by:{ $0.parent ?? "" })
        var result:[(activity:Activity,depth:Int)] = []
        var stack = groups["",default:[]].reversed().map { ($0,0) }
        while let (activity,depth) = stack.popLast() {
            result.append((activity,depth))
            for child in groups[activity.id,default:[]].reversed() { stack.append((child,depth+1)) }
        }
        return result
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
        else if let resource = resources.first(where:{ $0.id == activity.resource }), let productivity = resource.productivity { rate = productivity * activity.units * (resource.timeUnit == "hour" ? 8 : 1) }
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
    static func move(_ plan:Schedule, activityID:String, to start:Int,before:Calculation? = nil) throws -> MoveProposal {
        guard let index = plan.activities.firstIndex(where:{ $0.id == activityID }), plan.activities[index].entityType != "summary", (0...100000).contains(start) else { throw PlanError.invalid("Перемещать можно задачи и вехи в пределах шкалы проекта") }
        guard plan.activities[index].lockStart != true, plan.activities[index].lockFinish != true else { throw PlanError.invalid("Дата задачи зафиксирована. Снимите флажок фиксации перед переносом.") }
        var proposed = plan; proposed.activities[index].earliestStart = start; proposed.activities[index].requestedStart = nil; proposed.activities[index].requestedFinish = nil
        return MoveProposal(original:plan,proposed:proposed,activityID:activityID,requestedStart:start,before:try before ?? calculate(plan),after:try calculate(proposed))
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
    static func group(_ plan:Schedule,ids:Set<String>,name:String = "Новая суммарная задача", deferCalculation:Bool = false) throws -> Schedule {
        let roots = plan.activities.filter { task in ids.contains(task.id) && !plan.activities.contains(where:{ ids.contains($0.id) && $0.id != task.id && plan.descendants(of:$0.id).contains(task.id) }) }
        guard roots.count >= 2 else { throw PlanError.invalid("Выберите минимум две задачи одного уровня") }
        guard roots.allSatisfy({ $0.parent == roots[0].parent }) else { throw PlanError.invalid("Для объединения выберите задачи с одним родителем") }
        var result = plan; let id = UUID().uuidString
        let indices = roots.compactMap { root in plan.activities.firstIndex { $0.id == root.id } }
        for i in indices { result.activities[i].parent = id }
        result.activities.insert(Activity(id:id,name:name,duration:0,kind:"summary",parent:roots[0].parent),at:indices.min()!)
        _ = try calculate(result,validationOnly:deferCalculation); return result
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
        if plan.resources.contains(where:{ $0.calendarID != nil || $0.timeUnit == "hour" }) { return CalendarScheduler.load(resource:resource,day:day,plan:plan,result:result) }
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
    init(plan:Schedule,count:Int,axis:ResourceAvailability? = nil) {
        let axis = axis ?? ResourceAvailability(plan)
        let names = ["Январь","Февраль","Март","Апрель","Май","Июнь","Июль","Август","Сентябрь","Октябрь","Ноябрь","Декабрь"]
        var dates:[String] = [], years:[TimelineBand] = [], months:[TimelineBand] = []
        for index in 0..<max(0,count) {
            let date = axis.date(index), year = String(date.prefix(4)), month = names[(Int(date.dropFirst(5).prefix(2)) ?? 1)-1]
            if years.last?.label == year { years[years.count-1].count += 1 } else { years.append(TimelineBand(start:index,count:1,label:year)) }
            if months.last?.label == month && dates.last?.prefix(4) == date.prefix(4) { months[months.count-1].count += 1 } else { months.append(TimelineBand(start:index,count:1,label:month)) }
            dates.append(date)
        }
        self.dates = dates; self.years = years; self.months = months
    }
}

struct WorkInterval:Codable,Equatable {
    var start:Int = 540
    var end:Int = 1020
    static func parse(_ text:String) throws -> [WorkInterval] {
        if text.trimmingCharacters(in:.whitespaces).isEmpty { return [] }
        func minute(_ value:Substring) throws -> Int {
            let parts = value.trimmingCharacters(in:.whitespaces).split(separator:":")
            guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), (0...24).contains(h), (0...59).contains(m), h < 24 || m == 0 else { throw PlanError.invalid("Время: ЧЧ:ММ, например 09:00-13:00, 14:00-18:00") }
            return h*60+m
        }
        return try text.replacingOccurrences(of:"–",with:"-").split(separator:",").map { part in
            let pair = part.split(separator:"-"); guard pair.count == 2 else { throw PlanError.invalid("Интервал: 09:00-18:00") }
            return WorkInterval(start:try minute(pair[0]),end:try minute(pair[1]))
        }
    }
    static func text(_ intervals:[WorkInterval]) -> String { intervals.map { String(format:"%02d:%02d-%02d:%02d",$0.start/60,$0.start%60,$0.end/60,$0.end%60) }.joined(separator:", ") }
}
struct ResourceWorkday:Codable,Equatable {
    var weekday:Int
    var intervals:[WorkInterval]
}
struct CalendarException:Codable,Identifiable,Equatable {
    var id:String = UUID().uuidString
    var name:String = "Исключение"
    var from:String
    var through:String
    var kind:String = "vacation"
    var intervals:[WorkInterval] = []
}
struct ResourceCalendar:Codable,Identifiable,Equatable {
    var id:String = UUID().uuidString
    var name:String = "Новый календарь"
    var week:[ResourceWorkday] = (1...7).map { ResourceWorkday(weekday:$0,intervals:(2...6).contains($0) ? [WorkInterval(start:540,end:780),WorkInterval(start:840,end:1080)] : []) }
    var exceptions:[CalendarException] = []
    func hours(date:String) -> Double {
        let parts = date.split(separator:"-").compactMap { Int($0) }
        var c = Calendar(identifier:.gregorian); c.timeZone = TimeZone(secondsFromGMT:0)!
        guard parts.count == 3, let d = c.date(from:DateComponents(year:parts[0],month:parts[1],day:parts[2])) else { return 0 }
        let intervals:[WorkInterval]
        if let exception = exceptions.last(where:{ $0.from <= date && date <= $0.through }) { intervals = exception.kind == "working" ? exception.intervals : [] }
        else { intervals = week.first { $0.weekday == c.component(.weekday,from:d) }?.intervals ?? [] }
        return Double(intervals.reduce(0) { $0 + $1.end-$1.start })/60
    }
    static func validate(_ plan:Schedule) throws {
        let calendars = plan.resourceCalendars ?? []
        guard Set(calendars.map(\.id)).count == calendars.count else { throw PlanError.invalid("Повторяющиеся коды календарей") }
        func validateIntervals(_ intervals:[WorkInterval]) throws {
            var previous = 0
            for i in intervals.sorted(by:{ $0.start < $1.start }) {
                guard i.start >= previous, i.start >= 0, i.end <= 1440, i.end > i.start else { throw PlanError.invalid("Рабочие интервалы должны быть в пределах суток и не пересекаться") }
                previous = i.end
            }
        }
        for calendar in calendars {
            guard !calendar.id.isEmpty, !calendar.name.trimmingCharacters(in:.whitespaces).isEmpty, calendar.week.count == 7, Set(calendar.week.map(\.weekday)) == Set(1...7), calendar.week.contains(where:{ !$0.intervals.isEmpty }) else { throw PlanError.invalid("Задайте название календаря и хотя бы один рабочий день недели") }
            for day in calendar.week { try validateIntervals(day.intervals) }
            guard Set(calendar.exceptions.map(\.id)).count == calendar.exceptions.count else { throw PlanError.invalid("Повторяющиеся исключения календаря") }
            for exception in calendar.exceptions {
                guard Planner.validDate(exception.from), Planner.validDate(exception.through), exception.from <= exception.through, ["vacation","holiday","off","working"].contains(exception.kind) else { throw PlanError.invalid("Проверьте период и тип исключения календаря") }
                try validateIntervals(exception.intervals)
                if exception.kind == "working" && exception.intervals.isEmpty { throw PlanError.invalid("Для рабочего исключения задайте часы") }
            }
        }
        for resource in plan.resources {
            guard resource.timeUnit == nil || ["day","hour"].contains(resource.timeUnit!) else { throw PlanError.invalid("Учёт ресурса: день или час") }
            if let id = resource.calendarID, !calendars.contains(where:{ $0.id == id }) { throw PlanError.invalid("Календарь ресурса не найден") }
        }
    }
}

// The scheduling axis remains project working days. Shifts determine usable hours
// inside each axis day; non-project-working dates never acquire capacity.
final class ResourceAvailability {
    let plan:Schedule
    private var dates:[String] = []
    private var calendarHours:[String:[Int:Double]] = [:]
    private let formatter:DateFormatter
    private var calendar:Calendar
    private var current:Date
    init(_ plan:Schedule) {
        self.plan = plan
        formatter = DateFormatter(); formatter.locale = Locale(identifier:"en_US_POSIX"); formatter.timeZone = TimeZone(identifier:plan.calendar.timezone); formatter.dateFormat = "yyyy-MM-dd"
        calendar = Calendar(identifier:.gregorian); calendar.timeZone = formatter.timeZone
        current = formatter.date(from:plan.startDate)!
    }
    func date(_ day:Int) -> String {
        while dates.count <= day {
            let text = formatter.string(from:current)
            if plan.calendar.weekdays.contains(calendar.component(.weekday,from:current)) && !plan.calendar.holidays.contains(text) { dates.append(text) }
            current = calendar.date(byAdding:.day,value:1,to:current)!
        }
        return dates[day]
    }
    func hours(_ resource:Resource,day:Int) -> Double {
        guard let id = resource.calendarID, let resourceCalendar = plan.resourceCalendars?.first(where:{ $0.id == id }) else { return 8 }
        if let value = calendarHours[id]?[day] { return value }
        let value = resourceCalendar.hours(date:date(day))
        calendarHours[id,default:[:]][day] = value
        return value
    }
}
struct CalendarWorkDay {
    let day:Int
    let hours:Double
    let output:Double
}
enum CalendarScheduler {
    static func work(_ task:Activity,resource:Resource,start:Int,availability:ResourceAvailability) throws -> [CalendarWorkDay] {
        guard task.entityType == "task" else { return [] }
        if let calendar = availability.plan.resourceCalendars?.first(where:{ $0.id == resource.calendarID }),
           !calendar.week.contains(where:{ availability.plan.calendar.weekdays.contains($0.weekday) && !$0.intervals.isEmpty }),
           !calendar.exceptions.contains(where:{ $0.kind == "working" }) { throw PlanError.invalid("У календарей проекта и ресурса \(resource.name) нет общих рабочих дней") }
        let outputRate = task.productivity.map { $0/8 } ?? resource.productivity.map { $0 * task.units / (resource.timeUnit == "hour" ? 1 : 8) }
        let byVolume = task.volume != nil && outputRate != nil
        var remaining = byVolume ? task.volume! : Double(task.duration)*8
        if remaining <= 0 { return [] }
        var days:[CalendarWorkDay] = [], day = start
        while remaining > 0.0000001 {
            guard day-start < 100000, day <= 200000 else { throw PlanError.invalid("Не найдено рабочее время ресурса для задачи \(task.id) в пределах 100000 дней") }
            let hours = availability.hours(resource,day:day)
            let rate = byVolume ? outputRate! : 1
            if hours > 0 {
                let used = min(hours,remaining/rate)
                days.append(CalendarWorkDay(day:day,hours:used,output:byVolume ? used*rate : 0)); remaining -= used*rate
            }
            day += 1
        }
        return days
    }
    static func calculate(_ plan:Schedule) throws -> Calculation {
        let availability = ResourceAvailability(plan)
        let resources = Dictionary(uniqueKeysWithValues:plan.resources.map { ($0.id,$0) })
        var profiles:[String:[Int:[CalendarWorkDay]]] = [:]
        func profile(_ task:Activity,start:Int) throws -> [CalendarWorkDay] {
            if let value = profiles[task.id]?[start] { return value }
            let value = try work(task,resource:resources[task.resource]!,start:start,availability:availability)
            profiles[task.id,default:[:]][start] = value
            return value
        }
        var staged = plan
        // Materialise each calendar span into the existing checked date/link solver.
        // Re-run until all spans and starts agree; reject rather than return a stale plan.
        for i in staged.activities.indices { staged.activities[i].requestedFinish = nil; staged.activities[i].lockFinish = nil }
        var result = try Planner.calculate(staged,applyResourceCalendars:false)
        for _ in 0..<128 {
            var next = plan
            for index in next.activities.indices {
                let task = plan.activities[index]
                guard task.entityType == "task", let resource = resources[task.resource] else { continue }
                var oldStart = result.timings[task.id]!.start
                if task.lockFinish == true, let finish = task.requestedFinish {
                    let end = try Planner.offset(for:finish,plan:plan)
                    guard availability.hours(resource,day:end) > 0 else { throw PlanError.invalid("Фиксированное окончание задачи \(task.id) попадает на нерабочий день ресурса") }
                    let hourlyRate = task.productivity.map { $0/8 } ?? resource.productivity.map { $0*task.units/(resource.timeUnit == "hour" ? 1 : 8) }
                    var remaining = task.volume != nil && hourlyRate != nil ? task.volume! : Double(task.duration)*8
                    var day = end
                    while remaining > 0.0000001 && day >= 0 {
                        remaining -= availability.hours(resource,day:day) * (task.volume != nil && hourlyRate != nil ? hourlyRate! : 1)
                        oldStart = day; day -= 1
                    }
                    guard remaining <= 0.0000001 else { throw PlanError.invalid("Недостаточно рабочего времени до фиксированного окончания задачи \(task.id)") }
                }
                let profile = try profile(task,start:oldStart)
                guard let first = profile.first, let last = profile.last else { continue }
                // Use plain duration to avoid applying volume conversion a second time.
                next.activities[index].volume = nil; next.activities[index].productivity = nil
                next.activities[index].duration = last.day-first.day+1
                next.activities[index].earliestStart = max(task.earliestStart ?? 0,first.day)
            }
            let candidate = try Planner.calculate(next,applyResourceCalendars:false)
            var consistent = true
            for task in plan.activities where task.entityType == "task" {
                guard resources[task.resource] != nil, let timing = candidate.timings[task.id] else { continue }
                let profile = try profile(task,start:timing.start)
                if let first = profile.first, let last = profile.last, first.day != timing.start || last.day+1 != timing.finish { consistent = false; break }
            }
            if consistent {
                var answer = candidate
                answer.cost = 0
                for task in plan.activities {
                    guard let resource = resources[task.resource], let timing = answer.timings[task.id] else { continue }
                    let profile = try profile(task,start:timing.start)
                    let hours = profile.reduce(0) { $0+$1.hours }
                    answer.cost += hours * task.units * resource.dailyRate / (resource.timeUnit == "hour" ? 1 : 8)
                }
                return answer
            }
            result = candidate; staged = next
        }
        throw PlanError.invalid("Календари и ограничения не сошлись. Проверьте фиксированные даты, связи и доступность ресурсов.")
    }
    static func load(resource:Resource,day:Int,plan:Schedule,result:Calculation) -> ResourceDay {
        let availability = ResourceAvailability(plan)
        let hours = availability.hours(resource,day:day)
        var quantity = 0.0, output = 0.0
        for task in plan.activities where task.resource == resource.id {
            guard let timing = result.timings[task.id], timing.start <= day, day < timing.finish,
                  let profile = try? work(task,resource:resource,start:timing.start,availability:availability),
                  let item = profile.first(where:{ $0.day == day }) else { continue }
            quantity += task.units; output += item.output
        }
        let factor = resource.timeUnit == "hour" ? hours : hours/8
        return ResourceDay(quantity:quantity,capacity:hours > 0 ? resource.capacity : 0,output:output,outputCapacity:resource.productivity.map { $0*resource.capacity*factor })
    }
}

extension Planner {
    static func loads(resource:Resource,days:Int,plan:Schedule,result:Calculation,availability:ResourceAvailability? = nil) -> [ResourceDay] {
        guard days > 0 else { return [] }
        guard plan.resources.contains(where:{ $0.calendarID != nil || $0.timeUnit == "hour" }) else {
            var quantity = Array(repeating:0.0,count:days+1), output = quantity
            let type = plan.resourceTypes.first { $0.id == resource.typeID }
            let symbol = plan.measurementUnits.first { $0.id == type?.outputUnitID }?.symbol
            for task in plan.activities where task.resource == resource.id {
                guard let timing = result.timings[task.id] else { continue }
                let start = max(0,timing.start), end = min(days,timing.finish)
                guard start < end else { continue }
                quantity[start] += task.units; quantity[end] -= task.units
                if let volume = task.volume, task.volumeUnit == symbol, let rate = task.productivity ?? resource.productivity.map({ $0*task.units }), rate > 0 {
                    let fullDays = min(end-start,max(0,Int(floor(volume/rate))-max(0,start-timing.start)))
                    if fullDays > 0 { output[start] += rate; output[start+fullDays] -= rate }
                    let partialDay = timing.start+Int(floor(volume/rate)), remainder = volume-rate*floor(volume/rate)
                    if partialDay >= start && partialDay < end && remainder > 0 { output[partialDay] += remainder; output[partialDay+1] -= remainder }
                }
            }
            var used = 0.0, produced = 0.0
            return (0..<days).map { day in
                used += quantity[day]; produced += output[day]
                return ResourceDay(quantity:abs(used) < 0.000000001 ? 0 : used,capacity:resource.capacity,output:abs(produced) < 0.000000001 ? 0 : produced,outputCapacity:resource.productivity.map { $0*resource.capacity })
            }
        }
        let availability = availability ?? ResourceAvailability(plan)
        var quantity = Array(repeating:0.0,count:days), output = quantity
        for task in plan.activities where task.resource == resource.id {
            guard let timing = result.timings[task.id], let profile = try? CalendarScheduler.work(task,resource:resource,start:timing.start,availability:availability) else { continue }
            for item in profile where item.day < days { quantity[item.day] += task.units; output[item.day] += item.output }
        }
        return (0..<days).map { day in
            let hours = availability.hours(resource,day:day)
            return ResourceDay(quantity:quantity[day],capacity:hours > 0 ? resource.capacity : 0,output:output[day],outputCapacity:resource.productivity.map { $0*resource.capacity*(resource.timeUnit == "hour" ? hours : hours/8) })
        }
    }
}

// An immutable project revision owns its derived data. UI-only changes reuse it;
// replacing the project discards the entire snapshot, including failed results.
final class ScheduleAnalysis {
    let plan:Schedule
    private var calculated:Result<Calculation,Error>?
    private var axis:ResourceAvailability?
    private var scales:[Int:TimelineCalendar] = [:]
    private var loadProfiles:[String:(Int,[ResourceDay])] = [:]
    private var ordered:[(activity:Activity,depth:Int)]?
    private var parentOptions:[String:[Activity]] = [:]
    private(set) var calculationBuildCount = 0
    init(plan:Schedule,calculation:Calculation? = nil) {
        self.plan = plan
        if let calculation { calculated = .success(calculation) }
    }
    func calculation() throws -> Calculation {
        if let calculated { return try calculated.get() }
        calculationBuildCount += 1
        let value = Result { try Planner.calculate(plan) }; calculated = value
        return try value.get()
    }
    private var dateAxis:ResourceAvailability {
        if let axis { return axis }
        let value = ResourceAvailability(plan); axis = value; return value
    }
    func date(_ day:Int) -> String { dateAxis.date(max(0,day)) }
    func timeline(_ count:Int) -> TimelineCalendar {
        if let value = scales[count] { return value }
        let value = TimelineCalendar(plan:plan,count:count,axis:dateAxis)
        scales = [count:value]; return value
    }
    var orderedActivities:[(activity:Activity,depth:Int)] {
        if let ordered { return ordered }
        let value = plan.orderedActivities; ordered = value; return value
    }
    func parentChoices(for id:String) -> [Activity] {
        if let options = parentOptions[id] { return options }
        let excluded = plan.descendants(of:id)
        let options = plan.activities.filter { $0.entityType == "summary" && !excluded.contains($0.id) }
        parentOptions[id] = options
        return options
    }
    func loads(_ resource:Resource,days:Int) -> [ResourceDay] {
        if let entry = loadProfiles[resource.id], entry.0 == days { return entry.1 }
        guard let result = try? calculation() else { return [] }
        let value = Planner.loads(resource:resource,days:days,plan:plan,result:result,availability:dateAxis)
        loadProfiles[resource.id] = (days,value); return value
    }
}

private struct ReadyTaskQueue {
    private var heap:[String] = []
    let precedes:(String,String)->Bool
    init(precedes:@escaping(String,String)->Bool) { self.precedes = precedes }
    mutating func insert(_ id:String) {
        heap.append(id); var child = heap.count-1
        while child > 0 {
            let parent = (child-1)/2
            guard precedes(heap[child],heap[parent]) else { break }
            heap.swapAt(child,parent); child = parent
        }
    }
    mutating func pop() -> String? {
        guard !heap.isEmpty else { return nil }
        if heap.count == 1 { return heap.removeLast() }
        let first = heap[0]; heap[0] = heap.removeLast(); var parent = 0
        while parent*2+1 < heap.count {
            let left = parent*2+1, right = left+1
            let child = right < heap.count && precedes(heap[right],heap[left]) ? right : left
            guard precedes(heap[child],heap[parent]) else { break }
            heap.swapAt(child,parent); parent = child
        }
        return first
    }
}
