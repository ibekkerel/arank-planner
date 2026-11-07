import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor final class Workspace: ObservableObject {
    @Published var plan = Schedule.demo { didSet { analysis = nil } }
    @Published var selection: String? = "A"
    @Published var selectedIDs: Set<String> = []
    @Published var propertyActivity: Activity?
    @Published var error = ""
    @Published var url: URL?
    @Published var dirty = false
    @Published var pendingMove: MoveProposal?
    private var analysis:ScheduleAnalysis?
    var snapshot:ScheduleAnalysis {
        if let analysis { return analysis }
        let value = ScheduleAnalysis(plan:plan); analysis = value; return value
    }
    var result: Calculation? { try? snapshot.calculation() }
    func install(_ next:Schedule,calculation:Calculation) { plan = next; analysis = ScheduleAnalysis(plan:next,calculation:calculation) }
    func date(_ offset:Int) -> String { snapshot.date(offset) }
    func change(_ body: (inout Schedule) -> Void) {
        var next = plan; body(&next)
        guard next != plan else { return }
        do { let result = try Planner.calculate(next); install(next,calculation:result); dirty = true } catch { self.error = error.localizedDescription }
    }
    func save(asNew: Bool = false) -> Bool {
        var target = asNew ? nil : url
        if target == nil {
            let p = NSSavePanel(); p.nameFieldStringValue = plan.name; p.allowedContentTypes = [UTType(filenameExtension:"osched") ?? .json]
            guard p.runModal() == .OK, let chosen = p.url else { return false }; target = chosen
        }
        do { try Planner.save(plan,to:target!); url = target; dirty = false; return true } catch { self.error = error.localizedDescription; return false }
    }
    func canReplace() -> Bool {
        guard dirty else { return true }
        let a = NSAlert(); a.messageText = "Сохранить изменения?"; a.informativeText = "В проекте есть несохранённые изменения."; a.addButton(withTitle:"Сохранить"); a.addButton(withTitle:"Отмена"); a.addButton(withTitle:"Не сохранять")
        let answer = a.runModal(); if answer == .alertFirstButtonReturn { return save() }; return answer == .alertThirdButtonReturn
    }
    func open() {
        guard canReplace() else { return }
        let p = NSOpenPanel(); p.allowedContentTypes = [UTType(filenameExtension:"osched") ?? .json,.json]
        guard p.runModal() == .OK, let u = p.url else { return }
        do { plan = try Planner.load(u); url = u; dirty = false; selection = plan.activities.first?.id; selectedIDs = [] } catch { self.error = error.localizedDescription }
    }
    func select(_ id:String,order:[String]) {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.shift), let anchor = selection, let a = order.firstIndex(of:anchor), let b = order.firstIndex(of:id) { selectedIDs.formUnion(order[min(a,b)...max(a,b)]) }
        else if modifiers.contains(.command) { if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) } }
        else { selectedIDs = [id] }
        selection = id
    }
    func delete(_ id:String) {
        let roots = selectedIDs.contains(id) ? selectedIDs : [id]
        var ids = Set<String>(); for root in roots { ids.formUnion(plan.descendants(of:root)) }
        change { p in p.activities.removeAll { ids.contains($0.id) }; p.links.removeAll { ids.contains($0.from) || ids.contains($0.to) }; for key in ids { p.baseline.removeValue(forKey:key) } }
        selectedIDs.subtract(ids); if let current = selection, ids.contains(current) { selection = nil }
    }
    func groupSelection() {
        do { let oldIDs = Set(plan.activities.map(\.id)); plan = try Planner.group(plan,ids:selectedIDs); dirty = true; selection = plan.activities.first { !oldIDs.contains($0.id) }?.id; selectedIDs = Set(selection.map { [$0] } ?? []) }
        catch { self.error = error.localizedDescription }
    }
    func move(_ id:String,to start:Int) {
        do {
            let proposal = try Planner.move(plan,activityID:id,to:start,before:result)
            if proposal.before.timings[id]?.start == start { return }
            if proposal.linked { pendingMove = proposal }
            else { install(proposal.proposed,calculation:proposal.after); dirty = true }
        } catch { self.error = error.localizedDescription }
    }
    func baseline() { guard let r = result else { return }; change { p in p.baseline = r.timings.mapValues { BaselineItem(start:$0.start,finish:$0.finish) } } }
}
final class Lifecycle: NSObject, NSApplicationDelegate {
    var workspace: Workspace?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { MainActor.assumeIsolated { workspace?.canReplace() == false ? .terminateCancel : .terminateNow } }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
@main struct ArankPlannerApp: App {
    @NSApplicationDelegateAdaptor(Lifecycle.self) var delegate
    @StateObject private var w = Workspace()
    var body: some Scene {
        WindowGroup("Arank Planner") { MainView().environmentObject(w).frame(minWidth:1120,minHeight:720).onAppear { delegate.workspace = w; NSApplication.shared.setActivationPolicy(.regular); NSApplication.shared.activate(ignoringOtherApps:true) } }
        .commands {
            CommandGroup(replacing:.newItem) { Button("Новый проект") { if w.canReplace() { w.plan = Schedule(name:"Новый проект",activities:[],links:[],resources:[]); w.url = nil; w.selection = nil; w.selectedIDs = []; w.dirty = false } }.keyboardShortcut("n"); Button("Открыть…") { w.open() }.keyboardShortcut("o") }
            CommandGroup(replacing:.saveItem) { Button("Сохранить") { _ = w.save() }.keyboardShortcut("s"); Button("Сохранить как…") { _ = w.save(asNew:true) }.keyboardShortcut("s",modifiers:[.command,.shift]) }
        }
    }
}
struct MainView: View {
    @EnvironmentObject var w: Workspace
    @State var tab = "График"
    @State var properties: Activity?
    @State var showResourceLoad = true
    @State var showLinks = false
    @State var showMetrics = false
    @State var fit = true
    @AppStorage("planner.zoom") var zoom = 24.0
    @State var showScaleSettings = false
    @State var canvasScrollX:CGFloat = 0
    @State var collapsed: Set<String> = []
    @State var connectionDrag: ConnectionDrag?
    @AppStorage("planner.visibleColumns") var visibleColumnIDs = "code,name,duration,start,finish,progress"
    @AppStorage("planner.tableWidth") var preferredTableWidth = 560.0
    @State var columnOffset = 0.0
    @State var dividerStart: Double?
    var visibleColumns: Set<String> { Set(visibleColumnIDs.split(separator:",").map(String.init)).union(["select","name","menu"]) }
    var contentWidth: CGFloat { ScheduleColumn.all.filter { visibleColumns.contains($0.id) }.reduce(0) { $0 + $1.width } }
    func setColumn(_ id:String,_ visible:Bool) {
        var ids = visibleColumns
        if visible { ids.insert(id) } else { ids.remove(id) }
        visibleColumnIDs = ids.sorted().joined(separator:","); columnOffset = 0
    }

    var rows: [(activity:Activity,depth:Int)] {
        var hiddenDepth:Int?
        return w.snapshot.orderedActivities.filter { entry in
            if let depth = hiddenDepth, entry.depth > depth { return false }
            hiddenDepth = collapsed.contains(entry.activity.id) ? entry.depth : nil
            return true
        }
    }
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:14) {
                Label("Arank Planner",systemImage:"point.3.connected.trianglepath.dotted").font(.headline).foregroundStyle(.teal)
                Divider().frame(height:20)
                Text(w.plan.name + (w.dirty ? " •" : "")).font(.headline).lineLimit(1)
                Spacer()
                Picker("Раздел",selection:$tab) { Text("График").tag("График"); Text("Ресурсы").tag("Ресурсы"); Text("Справочники").tag("Справочники"); Text("Проект").tag("Параметры") }.pickerStyle(.segmented).frame(width:400).labelsHidden()
                Button { w.open() } label: { Image(systemName:"folder") }.help("Открыть проект ⌘O")
                Button { _ = w.save() } label: { Image(systemName:"square.and.arrow.down") }.help("Сохранить ⌘S")
            }.padding(.horizontal,16).padding(.vertical,10)
            Divider()
            if tab == "График" {
                ScrollView(.horizontal) {
                    HStack(alignment:.top,spacing:18) {
                        ribbonGroup("Создание") {
                            Button("Задача",systemImage:"plus.rectangle") { add("task") }
                            Button("Веха",systemImage:"diamond") { add("milestone") }
                            Button("Суммарная",systemImage:"folder.badge.plus") { add("summary") }
                            Button("Объединить (\(w.selectedIDs.count))") { w.groupSelection() }.disabled(w.selectedIDs.count < 2)
                        }
                        Divider().frame(height:54)
                        ribbonGroup("Расчёт") {
                            Toggle("По ресурсам",isOn:Binding(get:{ w.plan.levelResources ?? true },set:{ enabled in w.change { $0.levelResources = enabled } })).toggleStyle(.checkbox)
                            Button("Базовый план") { w.baseline() }
                            Button("Связи",systemImage:"arrow.triangle.branch") { showLinks.toggle() }
                        }
                        Divider().frame(height:54)
                        ribbonGroup("Вид") {
                            Menu {
                                Button("Раскрыть всё") { collapsed.removeAll() }
                                Button("Свернуть всё") {
                                    collapsed = Set(w.snapshot.orderedActivities.filter { $0.activity.entityType == "summary" }.map { $0.activity.id })
                                }
                                Divider()
                                ForEach(1...max(1,(w.snapshot.orderedActivities.map { $0.depth }.max() ?? 0)+1),id:\.self) { level in
                                    Button("Показать до уровня \(level)") {
                                        collapsed = Set(w.snapshot.orderedActivities.filter { $0.activity.entityType == "summary" && $0.depth >= level-1 }.map { $0.activity.id })
                                    }
                                }
                            } label: { Label("Уровни",systemImage:"list.bullet.indent") }
                            .help("Раскрытие и сворачивание иерархии задач; корневые строки — уровень 1")
                            Menu {
                                ForEach(ScheduleColumn.all.filter { !["select","name","menu"].contains($0.id) }) { field in
                                    Toggle(field.title,isOn:Binding(get:{ visibleColumns.contains(field.id) },set:{ setColumn(field.id,$0) }))
                                }
                                Divider()
                                Button("Основные поля") { visibleColumnIDs = "code,name,duration,start,finish,progress"; columnOffset = 0 }
                                Button("Все поля") { visibleColumnIDs = ScheduleColumn.all.map(\.id).joined(separator:","); columnOffset = 0 }
                            } label: { Label("Поля таблицы",systemImage:"tablecells") }
                            Button("Загрузка") { showResourceLoad.toggle() }
                            Button("Показатели") { showMetrics.toggle() }
                            Button { NSApplication.shared.keyWindow?.toggleFullScreen(nil) } label: { Image(systemName:"arrow.up.left.and.arrow.down.right") }.help("На весь экран")
                        }
                        Divider().frame(height:54)
                        ribbonGroup("Масштаб и таблица") {
                            Button { showScaleSettings.toggle() } label: { Label("Масштаб",systemImage:"magnifyingglass") }
                                .popover(isPresented:$showScaleSettings) { GraphScaleSettings(fit:$fit,zoom:$zoom) }
                            Button { fit = false; zoom = max(2,zoom/1.25) } label: { Image(systemName:"minus.magnifyingglass") }.help("Уменьшить график")
                            Button { fit = false; zoom = min(160,zoom*1.25) } label: { Image(systemName:"plus.magnifyingglass") }.help("Увеличить график")
                            Text("Таблица").font(.caption)
                            Slider(value:$preferredTableWidth,in:300...900).frame(width:110).help("Ширина табличной части; также потяните разделитель у графика")
                        }
                    }.padding(.horizontal,16).padding(.vertical,8)
                }.fixedSize(horizontal:false,vertical:true).background(Color(nsColor:.controlBackgroundColor))
                if showMetrics, let r = w.result {
                    HStack { Metric(title:"ДЛИТЕЛЬНОСТЬ",value:"\(r.duration) раб. дн."); Metric(title:"ЗАТРАТЫ",value:"\(r.cost.formatted(.number.precision(.fractionLength(0)))) \(w.plan.currency)"); Metric(title:"ПЕРЕГРУЗКИ",value:"\(r.conflicts.count)") }.padding(10)
                }
                Divider()
                GeometryReader { geo in
                    let result = w.result
                    let days = max(10,(result?.duration ?? 0) + 3)
                    let tableWidth = min(CGFloat(preferredTableWidth),geo.size.width * 0.65)
                    let dayWidth = fit ? max(0.25,(geo.size.width-tableWidth)/CGFloat(days)) : zoom
                    let chartWidth = max(geo.size.width-tableWidth,CGFloat(days)*dayWidth)
                    VStack(spacing:0) {
                    ScrollView([.horizontal,.vertical]) {
                        LazyVStack(alignment:.leading,spacing:0) {
                            header(days:days,dayWidth:dayWidth,chartWidth:chartWidth,tableWidth:tableWidth)
                            ForEach(rows,id:\.activity.id) { row in
                                HStack(spacing:0) {
                                    TaskTableRow(activity:row.activity,depth:row.depth,visibleColumns:visibleColumns,collapsed:collapsed.contains(row.activity.id),toggleCollapse:{ if collapsed.contains(row.activity.id) { collapsed.remove(row.activity.id) } else { collapsed.insert(row.activity.id) } }).frame(width:contentWidth).offset(x:-min(columnOffset,max(0,contentWidth-tableWidth))).frame(width:tableWidth,alignment:.leading).clipped()
                                    GanttRow(activity:row.activity,timing:result?.timings[row.activity.id],baseline:w.plan.baseline[row.activity.id],width:chartWidth,dayWidth:dayWidth,onDrag:{ finish,value in
                                        connectionDrag = ConnectionDrag(source:ConnectionEndpoint(activityID:row.activity.id,finish:finish),start:value.startLocation,point:value.location)
                                    },onDrop:{ finish,value in
                                        defer { connectionDrag = nil }
                                        let index = Int(floor((value.location.y-TimelineHeader.height)/39))
                                        guard index >= 0, index < rows.count else { return }
                                        let target = rows[index].activity
                                        guard target.id != row.activity.id, target.entityType != "summary", let t = result?.timings[target.id] else { return }
                                        let x = value.location.x-tableWidth
                                        let start = CGFloat(t.start)*dayWidth, end = CGFloat(t.finish)*dayWidth
                                        guard x >= start-22, x <= end+22 else { return }
                                        let link = Link(from:row.activity.id,to:target.id)
                                        guard !w.plan.links.contains(where:{ $0.from == link.from && $0.to == link.to && $0.type == link.type && $0.lag == link.lag }) else { return }
                                        w.change { $0.links.append(link) }
                                    },onMove:{ start in w.move(row.activity.id,to:start) })
                                }.frame(height:38).background(w.selectedIDs.contains(row.activity.id) || w.selection == row.activity.id ? Color.teal.opacity(0.10) : Color(nsColor:.textBackgroundColor)).contentShape(Rectangle()).onTapGesture { w.select(row.activity.id,order:rows.map { $0.activity.id }) }
                                .background { NativeTaskMenu(properties:{ properties = row.activity },select:{ w.selectedIDs.insert(row.activity.id); w.selection = row.activity.id },delete:{ w.delete(row.activity.id) },group:w.selectedIDs.count > 1 ? { w.groupSelection() } : nil).frame(maxWidth:.infinity,maxHeight:.infinity) }
                                .contextMenu {
                                    Button("Свойства…") { properties = row.activity }
                                    Button("Выбрать задачу") { w.selectedIDs.insert(row.activity.id); w.selection = row.activity.id }
                                    if w.selectedIDs.count > 1 { Button("Объединить выбранные в суммарную") { w.groupSelection() } }
                                    Divider()
                                    Button(w.selectedIDs.contains(row.activity.id) && w.selectedIDs.count > 1 ? "Удалить выбранные задачи" : "Удалить",role:.destructive) { w.delete(row.activity.id) }
                                }
                                Divider()
                            }
                            Button { add("task") } label: { HStack { Image(systemName:"plus"); Text("Новая задача — введите название в строке таблицы"); Spacer() }.padding(.horizontal,16).frame(height:38) }.buttonStyle(.plain).foregroundStyle(.secondary)
                            // Fill the remaining viewport with the same grid instead of centering its contents.
                            ZStack(alignment:.topLeading) {
                                Color(nsColor:.textBackgroundColor)
                                Path { path in
                                    let height = max(0,geo.size.height - (TimelineHeader.height+40) - CGFloat(rows.count)*39)
                                    for y in stride(from:CGFloat(0),through:height,by:39) { path.move(to:CGPoint(x:0,y:y)); path.addLine(to:CGPoint(x:tableWidth+chartWidth,y:y)) }
                                    for d in 0...days { let x = tableWidth+CGFloat(d)*dayWidth; path.move(to:CGPoint(x:x,y:0)); path.addLine(to:CGPoint(x:x,y:height)) }
                                }.stroke(Color.secondary.opacity(0.10),lineWidth:1)
                            }.frame(height:max(0,geo.size.height - (TimelineHeader.height+40) - CGFloat(rows.count)*39 - (showResourceLoad ? 228 : 0)))
                        }.frame(width:tableWidth+chartWidth,alignment:.topLeading)
                        .background { HorizontalScrollObserver { canvasScrollX = -$0 } }
                        .coordinateSpace(name:"scheduleCanvas")
                        .overlay(alignment:.topLeading) {
                            ConnectionLines(links:w.plan.links,rows:rows.map(\.activity),timings:result?.timings ?? [:],tableWidth:tableWidth,dayWidth:dayWidth,drag:connectionDrag).allowsHitTesting(false)
                        }
                    }.coordinateSpace(name:"scheduleViewport")
                    .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
                    .overlay(alignment:.topLeading) {
                        Rectangle().fill(Color.teal.opacity(0.4)).frame(width:5).contentShape(Rectangle()).offset(x:tableWidth+canvasScrollX-3)
                            .help("Перетащите, чтобы изменить ширину таблицы")
                            .gesture(DragGesture().onChanged { value in
                                if dividerStart == nil { dividerStart = Double(tableWidth) }
                                preferredTableWidth = min(max(300,(dividerStart ?? 560)+value.translation.width),min(900,geo.size.width*0.65))
                            }.onEnded { _ in dividerStart = nil })
                    }
                    .safeAreaInset(edge:.bottom,spacing:0) {
                        if contentWidth > tableWidth {
                            HStack { Text("Поля таблицы").font(.caption); Slider(value:$columnOffset,in:0...max(1,contentWidth-tableWidth)).accessibilityLabel("Прокрутка полей таблицы") }.padding(.horizontal,8).frame(width:tableWidth,height:25).background(Color(nsColor:.controlBackgroundColor)).frame(maxWidth:.infinity,alignment:.leading)
                        }
                    }
                    if showResourceLoad, let result {
                        HStack { Label("Загрузка ресурсов",systemImage:"chart.bar.xaxis").font(.caption.bold()); Spacer(); Button("Скрыть",systemImage:"xmark") { showResourceLoad = false } }.padding(.horizontal,10).frame(height:28).background(Color(nsColor:.controlBackgroundColor))
                        ResourceLoadPanel(plan:w.plan,result:result,tableWidth:tableWidth,dayWidth:dayWidth,chartWidth:chartWidth,days:days)
                            .offset(x:canvasScrollX).frame(width:geo.size.width,height:200,alignment:.leading).clipped()
                    }
                    }
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
                if showLinks { Divider(); LinksPanel().frame(height:200).padding(.horizontal,16).padding(.vertical,8) }
                Divider()
                HStack { Text("\(w.plan.activities.filter { $0.entityType == "task" }.count) задач · \(w.plan.activities.filter { $0.entityType == "milestone" }.count) вех · \(w.plan.activities.filter { $0.entityType == "summary" }.count) суммарных · \(w.plan.resources.count) ресурсов"); Spacer(); Text("Связь: потяните кружок на краю полосы к другой задаче · Enter — применить") }.font(.caption).foregroundStyle(.secondary).padding(.horizontal,16).padding(.vertical,6)
            } else {
                ScrollView { if tab == "Ресурсы" { ResourceView() } else if tab == "Справочники" { CatalogView() } else { SettingsView() } }.padding(20).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        .background { TaskKeyboardHandler(enabled:tab == "График" && !w.selectedIDs.isEmpty) { if let id = w.selectedIDs.first { w.delete(id) } } }
        .onChange(of:w.selectedIDs) { _,ids in if !ids.isEmpty { NSApplication.shared.keyWindow?.makeFirstResponder(nil) } }
        .alert("Не удалось выполнить действие",isPresented:Binding(get:{ !w.error.isEmpty },set:{ if !$0 { w.error = "" } })) { Button("OK") { w.error = "" } } message: { Text(w.error) }
        .sheet(item:$w.pendingMove) { proposal in MoveConfirmation(proposal:proposal) }
        .sheet(item:$properties) { activity in TaskProperties(activity:activity) }
        .sheet(item:$w.propertyActivity) { activity in TaskProperties(activity:activity) }
    }
    func add(_ kind: String) {
        let numbers = Set(w.plan.activities.map(\.id)); var n = w.plan.activities.count+1
        while numbers.contains("T\(n)") { n += 1 }
        let id = "T\(n)"
        let selected = w.plan.activities.first { $0.id == w.selection }
        let parent = selected?.entityType == "summary" ? selected?.id : selected?.parent
        w.change { $0.activities.append(Activity(id:id,name:"Новая \(kind == "milestone" ? "веха" : kind == "summary" ? "суммарная задача" : "задача")",duration:kind == "task" ? 1 : 0,kind:kind,parent:parent)) }
        w.selection = id
    }
    func ribbonGroup<Content:View>(_ title:String,@ViewBuilder content:()->Content) -> some View {
        VStack(alignment:.leading,spacing:8) { HStack(spacing:8,content:content).frame(height:28); Text(title).font(.caption2).foregroundStyle(.secondary) }
    }
    func header(days:Int,dayWidth:CGFloat,chartWidth:CGFloat,tableWidth:CGFloat) -> some View {
        HStack(alignment:.bottom,spacing:0) {
            HStack(spacing:0) {
                ForEach(ScheduleColumn.all.filter { visibleColumns.contains($0.id) }) { field in
                    Text(field.title).font(.caption.bold()).frame(width:field.width,alignment:.leading)
                }
            }.frame(width:contentWidth,height:32,alignment:.leading).offset(x:-min(columnOffset,max(0,contentWidth-tableWidth))).frame(width:tableWidth,alignment:.leading).clipped()
            TimelineHeader(scale:w.snapshot.timeline(days),dayWidth:dayWidth).frame(width:chartWidth,alignment:.leading)
        }.frame(height:TimelineHeader.height).background(Color(nsColor:.controlBackgroundColor))
    }
}
struct Metric: View { let title:String; let value:String; var body: some View { HStack { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).bold() }.frame(maxWidth:.infinity,alignment:.leading) } }
struct TaskTableRow: View {
    @EnvironmentObject var w: Workspace
    let activity: Activity
    let depth: Int
    let visibleColumns: Set<String>
    let collapsed: Bool
    let toggleCollapse: () -> Void
    @State private var name = ""
    @State private var days = ""
    @State private var progress = ""
    @State private var volume = ""
    @State private var volumeUnit = ""
    @State private var priority = "500"
    @State private var demand = "1"
    @FocusState private var editing: Bool
    func update(_ body: (inout Activity) -> Void) { w.change { plan in if let i = plan.activities.firstIndex(where:{ $0.id == activity.id }) { body(&plan.activities[i]) } } }
    func sync() { name = activity.name; days = String(w.plan.duration(of:activity)); progress = String(Int(activity.progress)); volume = activity.volume.map { $0.formatted(.number.locale(Locale(identifier:"ru_RU")).grouping(.never)) } ?? ""; volumeUnit = activity.volumeUnit ?? ""; priority = String(activity.priority ?? 500); demand = String(activity.units) }
    func commit() {
        guard !name.trimmingCharacters(in:.whitespaces).isEmpty, let d = Int(days), let p = Double(progress), let rank = Int(priority), let quantity = Double(demand.replacingOccurrences(of:",",with:".")) else { w.error = "Введите название, целое число дней и процент выполнения"; sync(); return }
        let cleanVolume = volume.replacingOccurrences(of:",",with:".").trimmingCharacters(in:.whitespaces)
        guard cleanVolume.isEmpty || (Double(cleanVolume).map { $0.isFinite && $0 >= 0 } ?? false) else { w.error = "Объём должен быть неотрицательным числом"; return }
        update { a in a.name = name; a.duration = activity.entityType == "task" ? d : 0; a.progress = p; a.priority = rank; a.units = quantity
            if a.entityType == "task" { a.volume = Double(cleanVolume); a.volumeUnit = volumeUnit.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? nil : volumeUnit.trimmingCharacters(in:.whitespacesAndNewlines); if a.volume == nil { a.productivity = nil } }
        }
    }
    var body: some View {
        HStack(spacing:0) {
            Toggle("Выбрать \(activity.id)",isOn:Binding(get:{ w.selectedIDs.contains(activity.id) },set:{ value in if value { w.selectedIDs.insert(activity.id); w.selection = activity.id } else { w.selectedIDs.remove(activity.id) } })).labelsHidden().toggleStyle(.checkbox).frame(width:26).optionalColumn(visibleColumns.contains("select"))
            Text(activity.id).font(.caption.monospaced()).lineLimit(1).frame(width:45,alignment:.leading).optionalColumn(visibleColumns.contains("code"))
            Picker("Тип",selection:Binding(get:{ activity.entityType },set:{ kind in
                update { a in a.kind = kind; if kind != "task" { a.duration = 0; a.resource = ""; a.volume = nil; a.productivity = nil; a.volumeUnit = nil; a.earliestStart = nil; a.requestedStart = nil; a.requestedFinish = nil; a.lockStart = nil; a.lockFinish = nil } else if a.duration == 0 { a.duration = 1 } }
            })) { ForEach(EntityKind.values,id:\.self) { Text(EntityKind.title($0)).tag($0) } }.labelsHidden().frame(width:95).optionalColumn(visibleColumns.contains("kind"))
            HStack(spacing:3) {
                if activity.entityType == "summary" { Button(action:toggleCollapse) { Image(systemName:collapsed ? "chevron.right" : "chevron.down").font(.caption2) }.buttonStyle(.plain) }
                Image(systemName:EntityKind.icon(activity.entityType)).font(.system(size:9)).foregroundStyle(activity.entityType == "summary" ? Color.primary : .teal)
                TextField("Название",text:$name).textFieldStyle(.plain).fontWeight(activity.entityType == "summary" ? .semibold : .regular).focused($editing).onSubmit { commit() }
            }.padding(.leading,CGFloat(min(depth,8))*10).frame(width:210,alignment:.leading).optionalColumn(visibleColumns.contains("name"))
            Group {
                if activity.entityType == "task" { TextField("Длительность",text:$days).textFieldStyle(.plain).focused($editing).onSubmit { commit() }.help(activity.productivity == nil ? "Длительность в рабочих днях" : "Длительность задана объёмом и производительностью").disabled(activity.productivity != nil || (activity.volume != nil && w.plan.resources.first(where:{ $0.id == activity.resource })?.productivity != nil)) }
                else { Text(activity.entityType == "summary" ? String((w.result?.timings[activity.id]?.finish ?? 0)-(w.result?.timings[activity.id]?.start ?? 0)) : "0").foregroundStyle(.secondary) }
            }.frame(width:100).optionalColumn(visibleColumns.contains("duration"))
            TaskDateCell(activity:activity,finish:false).frame(width:125).optionalColumn(visibleColumns.contains("start"))
            TaskDateCell(activity:activity,finish:true).frame(width:125).optionalColumn(visibleColumns.contains("finish"))
            TextField("Объём",text:$volume).textFieldStyle(.plain).focused($editing).onSubmit { commit() }.frame(width:75).optionalColumn(visibleColumns.contains("volume")).disabled(activity.entityType != "task")
            Picker("Единица объёма",selection:Binding(get:{ activity.volumeUnit ?? "" },set:{ value in update { $0.volumeUnit = value.isEmpty ? nil : value } })) { Text("—").tag(""); ForEach(w.plan.measurementUnits) { Text($0.symbol).tag($0.symbol) } }.labelsHidden().frame(width:65).optionalColumn(visibleColumns.contains("unit")).disabled(activity.entityType != "task")
            Picker("Родитель",selection:Binding(get:{ activity.parent ?? "" },set:{ parent in update { $0.parent = parent.isEmpty ? nil : parent } })) {
                Text("—").tag(""); ForEach(w.plan.activities.filter { $0.entityType == "summary" && !w.plan.descendants(of:activity.id).contains($0.id) }) { Text($0.name).tag($0.id) }
            }.labelsHidden().frame(width:100).optionalColumn(visibleColumns.contains("parent"))
            Picker("Ресурс",selection:Binding(get:{ activity.resource },set:{ id in update { $0.resource = id } })) { Text("—").tag(""); ForEach(w.plan.resources) { Text($0.name).tag($0.id) } }.labelsHidden().frame(width:125).optionalColumn(visibleColumns.contains("resource")).disabled(activity.entityType != "task")
            TextField("Приоритет",text:$priority).textFieldStyle(.plain).focused($editing).onSubmit { commit() }.frame(width:70).optionalColumn(visibleColumns.contains("priority")).disabled(activity.entityType == "summary").help("0–1000; большее число — раньше при конкуренции за ресурс")
            TextField("Потребность",text:$demand).textFieldStyle(.plain).focused($editing).onSubmit { commit() }.frame(width:50).optionalColumn(visibleColumns.contains("demand")).disabled(activity.entityType != "task")
            TextField("%",text:$progress).textFieldStyle(.plain).focused($editing).onSubmit { commit() }.frame(width:45).optionalColumn(visibleColumns.contains("progress")).disabled(activity.entityType == "summary")
            Menu {
                Button("Свойства…") { w.propertyActivity = activity }
                if activity.earliestStart != nil || activity.requestedStart != nil || activity.requestedFinish != nil { Button("Снять условия дат") { update { $0.earliestStart = nil; $0.requestedStart = nil; $0.requestedFinish = nil; $0.lockStart = false; $0.lockFinish = false } } }
                Button("Удалить",role:.destructive) { w.delete(activity.id) }
            } label: { Image(systemName:"ellipsis") }.menuStyle(.borderlessButton).frame(width:40).optionalColumn(visibleColumns.contains("menu"))

            Spacer(minLength:0)
        }.onAppear { sync() }.onChange(of:w.selectedIDs) { _,ids in if !ids.isEmpty { editing = false } }.onChange(of:activity) { _,_ in sync() }.onChange(of:editing) { old,new in if old && !new { commit() } }
    }
}
struct GanttRow: View {
    let activity:Activity
    let timing:Timing?
    let baseline:BaselineItem?
    let width:CGFloat
    let dayWidth:CGFloat
    let onDrag: (Bool,DragGesture.Value) -> Void
    let onDrop: (Bool,DragGesture.Value) -> Void
    let onMove: (Int) -> Void
    @State private var moveDelta: CGFloat = 0
    var body: some View {
        ZStack(alignment:.leading) {
            Path { p in for i in stride(from:0,through:max(0,Int(width/dayWidth)),by:max(1,Int(ceil(6/dayWidth)))) { p.move(to:CGPoint(x:CGFloat(i)*dayWidth,y:0)); p.addLine(to:CGPoint(x:CGFloat(i)*dayWidth,y:38)) } }.stroke(Color.secondary.opacity(0.12),lineWidth:1)
            if let b = baseline { Rectangle().fill(Color.secondary.opacity(0.4)).frame(width:max(3,CGFloat(b.finish-b.start)*dayWidth),height:3).offset(x:CGFloat(b.start)*dayWidth,y:13) }
            if let t = timing {
                let length = max(3,CGFloat(t.finish-t.start)*dayWidth-2)
                if activity.entityType == "milestone" { Rectangle().fill(t.float == 0 ? Color.orange : .teal).frame(width:10,height:10).rotationEffect(.degrees(45)).offset(x:CGFloat(t.start)*dayWidth+moveDelta).gesture(moveGesture(timing:t)) }
                else if activity.entityType == "summary" {
                    Path { p in p.move(to:CGPoint(x:0,y:23)); p.addLine(to:CGPoint(x:0,y:13)); p.addLine(to:CGPoint(x:length,y:13)); p.addLine(to:CGPoint(x:length,y:23)) }.stroke(Color.primary,lineWidth:3).offset(x:CGFloat(t.start)*dayWidth)
                } else { RoundedRectangle(cornerRadius:3).fill(t.float == 0 ? Color.orange.opacity(0.8) : Color.teal.opacity(0.8)).frame(width:length,height:18).overlay(alignment:.leading) { RoundedRectangle(cornerRadius:3).fill(.black.opacity(0.17)).frame(width:length*activity.progress/100,height:18) }.offset(x:CGFloat(t.start)*dayWidth+moveDelta).gesture(moveGesture(timing:t)) }
            }
            if let t = timing, activity.entityType != "summary" {
                endpoint(finish:false).offset(x:max(0,CGFloat(t.start)*dayWidth - (activity.entityType == "milestone" ? 7 : 0)))
                endpoint(finish:true).offset(x:CGFloat(t.finish)*dayWidth + (activity.entityType == "milestone" ? 7 : 0))
            }
        }.frame(width:width,height:38).clipped()
    }
    func moveGesture(timing:Timing) -> some Gesture {
        DragGesture(minimumDistance:4).onChanged { value in moveDelta = CGFloat(max(-timing.start,Int((value.translation.width/dayWidth).rounded())))*dayWidth }.onEnded { value in
            let target = max(0,timing.start+Int((value.translation.width/dayWidth).rounded())); moveDelta = 0; onMove(target)
        }
    }
    func endpoint(finish:Bool) -> some View {
        Circle().fill(Color(nsColor:.textBackgroundColor)).overlay { Circle().stroke(Color.teal,lineWidth:1.5) }.frame(width:8,height:8)
            .frame(width:18,height:30).contentShape(Rectangle()).offset(x:-4)
            .help("\(finish ? "Финиш" : "Старт") \(activity.name): перетащите к краю другой задачи")
            .accessibilityLabel("\(finish ? "Финиш" : "Старт") задачи \(activity.id), создание связи")
            .highPriorityGesture(DragGesture(minimumDistance:3,coordinateSpace:.named("scheduleCanvas")).onChanged { onDrag(finish,$0) }.onEnded { onDrop(finish,$0) })
    }
}
struct LinksPanel: View {
    @EnvironmentObject var w: Workspace
    @State var from = ""
    @State var to = ""
    @State var type = "FS"
    @State var lag = "0"
    var choices:[Activity] { w.plan.activities.filter { $0.entityType != "summary" } }
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            HStack { Text("Связи задач").font(.headline); Text("Положительный лаг — задержка, отрицательный — опережение; рабочие дни").font(.caption).foregroundStyle(.secondary); Spacer() }
            HStack {
                Picker("Предшественник",selection:$from) { Text("Выберите…").tag(""); ForEach(choices) { Text("\($0.id) · \($0.name)").tag($0.id) } }.frame(maxWidth:330)
                Picker("Последователь",selection:$to) { Text("Выберите…").tag(""); ForEach(choices) { Text("\($0.id) · \($0.name)").tag($0.id) } }.frame(maxWidth:330)
                Picker("Тип",selection:$type) { ForEach(DependencyKind.values,id:\.self) { Text(DependencyKind.title($0)).tag($0) } }.frame(width:230)
                TextField("Лаг",text:$lag).frame(width:60)
                Button("Добавить") { guard let n = Int(lag) else { w.error = "Лаг должен быть целым числом"; return }; w.change { $0.links.append(Link(from:from,to:to,type:type,lag:n)) } }.disabled(from.isEmpty || to.isEmpty)
            }
            ScrollView {
                LazyVStack(spacing:4) { ForEach(w.plan.links) { link in ExistingLinkRow(link:link) } }
            }
        }.onAppear { to = w.selection ?? "" }.onChange(of:w.selection) { _,id in if let id, choices.contains(where:{ $0.id == id }) { to = id } }
    }
}
struct ExistingLinkRow: View {
    @EnvironmentObject var w: Workspace
    let link:Link
    @State var lag = ""
    var body: some View {
        HStack {
            Text("\(link.from) → \(link.to)").font(.caption.monospaced()).frame(width:140,alignment:.leading)
            Picker("Тип связи",selection:Binding(get:{ link.type },set:{ value in w.change { p in if let i = p.links.firstIndex(where:{ $0.id == link.id }) { p.links[i].type = value } } })) { ForEach(DependencyKind.values,id:\.self) { Text(DependencyKind.title($0)).tag($0) } }.labelsHidden().frame(width:230)
            TextField("Лаг",text:$lag).frame(width:70).onSubmit { guard let n = Int(lag) else { w.error = "Лаг должен быть целым числом"; return }; w.change { p in if let i = p.links.firstIndex(where:{ $0.id == link.id }) { p.links[i].lag = n } } }
            Text("раб. дн.").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button { w.change { $0.links.removeAll { $0.id == link.id } } } label: { Image(systemName:"trash") }.buttonStyle(.plain)
        }.onAppear { lag = String(link.lag) }.onChange(of:link.lag) { _,n in lag = String(n) }
    }
}

struct ResourceView: View {
    @EnvironmentObject var w: Workspace
    @State var calendarDraft:ResourceCalendar?
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack { Text("Ресурсы").font(.title2.bold()); Spacer(); Button("Добавить ресурс",systemImage:"plus") { w.change { $0.resources.append(Resource(id:UUID().uuidString,name:"Новый ресурс")) } } }
            Text("Выберите для ресурса календарь и период учёта: день или час. Производительность и ставка относятся к выбранному периоду. Дневная норма соответствует 8 часам.").foregroundStyle(.secondary)
            HStack { Text("Название").frame(width:200,alignment:.leading); Text("Тип").frame(width:180,alignment:.leading); Text("Доступно").frame(width:80); Text("Ед. учёта").frame(width:70); Text("Выработка / период").frame(width:130); Text("Ед. выработки").frame(width:100); Text("Ставка / период").frame(width:110) }.font(.caption.bold())
            ForEach(w.plan.resources) { resource in ResourceEditorRow(resource:resource) }
            Divider()
            if let result = w.result { if result.conflicts.isEmpty { Label("Перегрузок нет",systemImage:"checkmark.circle").foregroundStyle(.teal) } else { ForEach(result.conflicts,id:\.self) { Text($0).foregroundStyle(.orange) } } }
            Text("Рабочее время ресурса пересекается с календарём проекта. Чтобы учитывать субботу или воскресенье, включите их и в календарь проекта. Почасовая выработка учитывает часы смен, а даты начала и окончания пока рассчитываются с точностью до рабочего дня.").font(.callout).foregroundStyle(.secondary)
            Divider()
            HStack { Text("Календари ресурсов").font(.title3.bold()); Spacer(); Button("Новый календарь",systemImage:"calendar.badge.plus") { calendarDraft = ResourceCalendar() } }
            ForEach(w.plan.resourceCalendars ?? []) { calendar in
                HStack { Text(calendar.name).bold(); Text("Исключений: \(calendar.exceptions.count)").foregroundStyle(.secondary); Spacer(); Button("Настроить") { calendarDraft = calendar }; Button("Удалить",role:.destructive) {
                    if w.plan.resources.contains(where:{ $0.calendarID == calendar.id }) { w.error = "Сначала снимите назначения календаря с ресурсов" }
                    else { w.change { $0.resourceCalendars?.removeAll { $0.id == calendar.id } } }
                } }
            }
        }.sheet(item:$calendarDraft) { calendar in ResourceCalendarEditor(calendar:calendar) }
    }
}
struct ResourceEditorRow: View {
    @EnvironmentObject var w: Workspace
    let resource:Resource
    @State var name = ""; @State var capacity = ""; @State var productivity = ""; @State var rate = ""
    var type:ResourceType? { w.plan.resourceTypes.first { $0.id == resource.typeID } }
    func symbol(_ id:String?) -> String { w.plan.measurementUnits.first { $0.id == id }?.symbol ?? "—" }
    func sync() { name = resource.name; capacity = String(resource.capacity); productivity = resource.productivity.map { String($0) } ?? ""; rate = String(resource.dailyRate) }
    func commit() {
        let text = productivity.replacingOccurrences(of:",",with:".")
        guard !name.isEmpty, let c = Double(capacity.replacingOccurrences(of:",",with:".")), let r = Double(rate.replacingOccurrences(of:",",with:".")), text.isEmpty || Double(text) != nil else { w.error = "Проверьте параметры ресурса"; return }
        w.change { p in if let i = p.resources.firstIndex(where:{ $0.id == resource.id }) { p.resources[i].name = name; p.resources[i].capacity = c; p.resources[i].dailyRate = r; p.resources[i].productivity = Double(text) } }
    }
    var body: some View {
        VStack(alignment:.leading,spacing:6) {
        HStack {
            TextField("Название",text:$name).frame(width:200).onSubmit { commit() }
            Picker("Тип ресурса",selection:Binding(get:{ resource.typeID ?? "" },set:{ value in w.change { p in if let i = p.resources.firstIndex(where:{ $0.id == resource.id }) { p.resources[i].typeID = value.isEmpty ? nil : value; if value.isEmpty { p.resources[i].productivity = nil } } } })) { Text("Не задан").tag(""); ForEach(w.plan.resourceTypes) { Text($0.name).tag($0.id) } }.labelsHidden().frame(width:180)
            TextField("Доступно",text:$capacity).frame(width:80).onSubmit { commit() }
            Text(symbol(type?.unitID)).frame(width:70)
            TextField("Производительность",text:$productivity).frame(width:130).disabled(type == nil).onSubmit { commit() }
            Text(symbol(type?.outputUnitID)+(resource.timeUnit == "hour" ? "/ч" : "/дн.")).frame(width:100)
            TextField("Ставка",text:$rate).frame(width:110).onSubmit { commit() }
            Button(role:.destructive) { if w.plan.activities.contains(where:{ $0.resource == resource.id }) { w.error = "Сначала снимите назначения этого ресурса" } else { w.change { $0.resources.removeAll { $0.id == resource.id } } } } label: { Image(systemName:"trash") }
        }
        HStack {
            Picker("Календарь ресурса",selection:Binding(get:{ resource.calendarID ?? "" },set:{ value in w.change { p in if let i = p.resources.firstIndex(where:{ $0.id == resource.id }) { p.resources[i].calendarID = value.isEmpty ? nil : value } } })) {
                Text("Календарь проекта · 8 ч/день").tag("")
                ForEach(w.plan.resourceCalendars ?? []) { Text($0.name).tag($0.id) }
            }.frame(width:430)
            Picker("Учёт выработки и ставки",selection:Binding(get:{ resource.timeUnit ?? "day" },set:{ value in w.change { p in if let i = p.resources.firstIndex(where:{ $0.id == resource.id }) { p.resources[i].timeUnit = value } } })) { Text("За день (8 ч)").tag("day"); Text("За час").tag("hour") }.frame(width:350)
        }.font(.caption)
        Divider()
        }.onAppear { sync() }.onChange(of:resource) { _,_ in sync() }
    }
}
struct SettingsView: View {
    @EnvironmentObject var w: Workspace
    @State var name = ""; @State var start = ""; @State var holidays = ""
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            Text("Параметры проекта").font(.headline)
            TextField("Название",text:$name); TextField("Начало, ГГГГ-ММ-ДД",text:$start)
            HStack { Text("Рабочие дни проекта:"); ForEach(Array(zip([2,3,4,5,6,7,1],["Пн","Вт","Ср","Чт","Пт","Сб","Вс"])),id:\.0) { day,title in
                Toggle(title,isOn:Binding(get:{ w.plan.calendar.weekdays.contains(day) },set:{ enabled in w.change { plan in if enabled { plan.calendar.weekdays.append(day); plan.calendar.weekdays.sort() } else { plan.calendar.weekdays.removeAll { $0 == day } } } })).toggleStyle(.checkbox)
            } }
            Text("Часовой пояс: \(w.plan.calendar.timezone). Изменение календаря проекта сдвигает шкалу рабочих дней; проверьте фиксированные даты.").foregroundStyle(.secondary)
            TextField("Нерабочие даты через запятую",text:$holidays)
            Button("Применить") { w.change { $0.name = name; $0.startDate = start; $0.calendar.holidays = holidays.split(separator:",").map { $0.trimmingCharacters(in:.whitespaces) } } }
            Divider()
            Text("Формат .osched").font(.title3.bold()); Text("Открытый JSON с версией схемы, стабильными идентификаторами, четырьмя типами связей, ресурсами, календарём, базовым планом и ссылками на IFC GlobalId.")
            Text("Это независимый прототип. Импорт Spider Project / MSPDI / XER и IFC пока не реализован. Для обмена рекомендуется будущий адаптер Microsoft Project XML с отчётом о потерях.").foregroundStyle(.secondary)
        }.frame(maxWidth:650,alignment:.leading).onAppear { name = w.plan.name; start = w.plan.startDate; holidays = w.plan.calendar.holidays.joined(separator:", ") }
    }
}

struct ConnectionDrag {
    let source: ConnectionEndpoint
    let start: CGPoint
    let point: CGPoint
}
struct ConnectionLines: View {
    let links:[Link]
    let rows:[Activity]
    let timings:[String:Timing]
    let tableWidth:CGFloat
    let dayWidth:CGFloat
    let drag:ConnectionDrag?
    var body: some View {
        Canvas { context,size in
            let positions = Dictionary(uniqueKeysWithValues:rows.enumerated().map { ($0.element.id,$0.offset) })
            for link in links {
                guard let a = timings[link.from], let b = timings[link.to], let i = positions[link.from], let j = positions[link.to] else { continue }
                let fromFinish = link.type.first == "F", toFinish = link.type.last == "F"
                let x1 = tableWidth + CGFloat(fromFinish ? a.finish : a.start)*dayWidth
                let x2 = tableWidth + CGFloat(toFinish ? b.finish : b.start)*dayWidth
                let y1 = TimelineHeader.height + CGFloat(i)*39 + 19, y2 = TimelineHeader.height + CGFloat(j)*39 + 19
                let escape1 = x1 + (fromFinish ? 13 : -13), escape2 = x2 + (toFinish ? 13 : -13)
                let middleY = (y1+y2)/2
                var p = Path(); p.move(to:CGPoint(x:x1,y:y1)); p.addLine(to:CGPoint(x:escape1,y:y1)); p.addLine(to:CGPoint(x:escape1,y:middleY)); p.addLine(to:CGPoint(x:escape2,y:middleY)); p.addLine(to:CGPoint(x:escape2,y:y2)); p.addLine(to:CGPoint(x:x2,y:y2))
                context.stroke(p,with:.color(.secondary.opacity(0.65)),lineWidth:1)
                var arrow = Path(); let direction: CGFloat = toFinish ? 1 : -1
                arrow.move(to:CGPoint(x:x2+direction*5,y:y2-3)); arrow.addLine(to:CGPoint(x:x2,y:y2)); arrow.addLine(to:CGPoint(x:x2+direction*5,y:y2+3))
                context.stroke(arrow,with:.color(.secondary),lineWidth:1)
            }
            if let drag {
                var line = Path(); line.move(to:drag.start); line.addLine(to:drag.point)
                context.stroke(line,with:.color(.teal),style:StrokeStyle(lineWidth:2,dash:[5,3]))
                let circle = Path(ellipseIn:CGRect(x:drag.point.x-5,y:drag.point.y-5,width:10,height:10))
                context.stroke(circle,with:.color(.teal),lineWidth:2)
            }
        }
    }
}
struct MoveConfirmation: View {
    @EnvironmentObject var w: Workspace
    @Environment(\.dismiss) var dismiss
    let proposal:MoveProposal
    @State var error = ""
    func name(_ id:String) -> String { proposal.original.activities.first { $0.id == id }?.name ?? id }
    func dates(_ timing:Timing?,_ plan:Schedule) -> String { guard let timing else { return "—" }; return "\(Planner.date(timing.start,plan:plan)) — \(Planner.finishDate(timing,plan:plan))" }
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            Text("Подтвердить перенос задачи?").font(.title2.bold())
            Text(name(proposal.activityID)).font(.headline)
            Text("Запрошено начало: \(Planner.date(proposal.requestedStart,plan:proposal.proposed))")
            Text("Все связи и задержки сохранятся. Будет задано условие «начать не раньше» выбранного дня.").font(.callout).foregroundStyle(.secondary)
            if !proposal.achieved { Text("Связи не позволяют начать в выбранный день. Доступное начало: \(Planner.date(proposal.after.timings[proposal.activityID]?.start ?? 0,plan:proposal.proposed)). Для более раннего начала сначала измените предшествующие работы или связи.").foregroundStyle(.orange) }
            Text("Окончание проекта: \(Planner.projectFinishDate(proposal.before,plan:proposal.original)) → \(Planner.projectFinishDate(proposal.after,plan:proposal.proposed))")
            Text("Длительность: \(proposal.before.duration) → \(proposal.after.duration) раб. дн. · Перегрузки: \(proposal.before.conflicts.count) → \(proposal.after.conflicts.count)")
            Text("Изменение дат: \(proposal.changedIDs.count) элементов, включая суммарные задачи").font(.headline)
            Text("Изменение дат или резервов: \(proposal.impactedIDs.count) элементов").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment:.leading,spacing:9) {
                    ForEach(proposal.impactedIDs,id:\.self) { id in VStack(alignment:.leading,spacing:2) { Text("\(id) · \(name(id))").bold(); Text("\(dates(proposal.before.timings[id],proposal.original)) → \(dates(proposal.after.timings[id],proposal.proposed))").font(.caption); Text("Резерв по связям: \(proposal.before.timings[id]?.float ?? 0) → \(proposal.after.timings[id]?.float ?? 0) раб. дн.").font(.caption).foregroundStyle(.secondary) } }
                    ForEach(proposal.after.conflicts,id:\.self) { Text($0).foregroundStyle(.orange).font(.caption) }
                }
            }.frame(height:220)
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
            HStack { Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Применить перенос") {
                guard w.plan == proposal.original else { error = "График изменился после расчёта. Отмените перенос и повторите его."; return }
                w.install(proposal.proposed,calculation:proposal.after); w.dirty = true; dismiss()
            }.buttonStyle(.borderedProminent).disabled(!proposal.achieved).keyboardShortcut(.defaultAction) }
        }.padding(26).frame(width:660)
    }
}
struct CatalogView: View {
    @EnvironmentObject var w: Workspace
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack { Text("Единицы измерения").font(.title2.bold()); Spacer(); Button("Добавить единицу") { w.change { p in var units = p.measurementUnits; var n = units.count+1; while units.contains(where:{ $0.symbol == "ед\(n)" }) { n += 1 }; units.append(MeasurementUnit(name:"Новая единица \(n)",symbol:"ед\(n)")); p.unitCatalog = units } } }
            Text("Название и обозначение редактируются в строке; Enter применяет изменения. Обозначение используется в объёмах задач.").foregroundStyle(.secondary).font(.callout)
            ForEach(w.plan.measurementUnits) { UnitEditorRow(unit:$0) }
            Divider()
            HStack { Text("Типы ресурсов").font(.title2.bold()); Spacer(); Button("Добавить тип") { guard let unit = w.plan.measurementUnits.first else { return }; w.change { p in var types = p.resourceTypes; types.append(ResourceType(name:"Новый тип",unitID:unit.id,outputUnitID:unit.id)); p.typeCatalog = types } }.disabled(w.plan.measurementUnits.isEmpty) }
            Text("Единица учёта определяет количество ресурса. Единица выработки определяет размерность его производительности за рабочий день.").font(.callout).foregroundStyle(.secondary)
            HStack { Text("Название типа").frame(width:240,alignment:.leading); Text("Единица учёта").frame(width:190); Text("Единица выработки").frame(width:190) }.font(.caption.bold())
            ForEach(w.plan.resourceTypes) { TypeEditorRow(type:$0) }
        }.frame(maxWidth:1000,alignment:.leading)
    }
}
struct UnitEditorRow: View {
    @EnvironmentObject var w: Workspace
    let unit:MeasurementUnit
    @State var name = ""; @State var symbol = ""
    func commit() { w.change { p in var units = p.measurementUnits; if let i = units.firstIndex(where:{ $0.id == unit.id }) { units[i].name = name.trimmingCharacters(in:.whitespaces); units[i].symbol = symbol.trimmingCharacters(in:.whitespaces); for j in p.activities.indices where p.activities[j].volumeUnit == unit.symbol { p.activities[j].volumeUnit = units[i].symbol }; p.unitCatalog = units } } }
    var body: some View {
        HStack {
            TextField("Название единицы",text:$name).frame(width:300).onSubmit { commit() }
            TextField("Обозначение",text:$symbol).frame(width:120).onSubmit { commit() }
            Button(role:.destructive) {
                if w.plan.resourceTypes.contains(where:{ $0.unitID == unit.id || $0.outputUnitID == unit.id }) || w.plan.activities.contains(where:{ $0.volumeUnit == unit.symbol }) { w.error = "Единица используется в типе ресурса или задаче" }
                else { w.change { p in p.unitCatalog = p.measurementUnits.filter { $0.id != unit.id } } }
            } label: { Image(systemName:"trash") }
        }.onAppear { name = unit.name; symbol = unit.symbol }.onChange(of:unit) { _,value in name = value.name; symbol = value.symbol }
    }
}
struct TypeEditorRow: View {
    @EnvironmentObject var w: Workspace
    let type:ResourceType
    @State var name = ""
    func update(_ body:(inout ResourceType)->Void) { w.change { p in var types = p.resourceTypes; if let i = types.firstIndex(where:{ $0.id == type.id }) { body(&types[i]); p.typeCatalog = types } } }
    var body: some View {
        HStack {
            TextField("Название типа",text:$name).frame(width:240).onSubmit { update { $0.name = name.trimmingCharacters(in:.whitespaces) } }
            Picker("Единица учёта",selection:Binding(get:{ type.unitID },set:{ id in update { $0.unitID = id } })) { ForEach(w.plan.measurementUnits) { Text("\($0.symbol) · \($0.name)").tag($0.id) } }.labelsHidden().frame(width:190)
            Picker("Единица выработки",selection:Binding(get:{ type.outputUnitID },set:{ id in update { $0.outputUnitID = id } })) { ForEach(w.plan.measurementUnits) { Text("\($0.symbol) · \($0.name)").tag($0.id) } }.labelsHidden().frame(width:190)
            Button(role:.destructive) { if w.plan.resources.contains(where:{ $0.typeID == type.id }) { w.error = "Тип используется ресурсом" } else { w.change { p in p.typeCatalog = p.resourceTypes.filter { $0.id != type.id } } } } label: { Image(systemName:"trash") }
        }.onAppear { name = type.name }.onChange(of:type.name) { _,value in name = value }
    }
}

struct TaskDateCell: View {
    @EnvironmentObject var w:Workspace
    let activity:Activity
    let finish:Bool
    @State private var text = ""
    var calculated:String { guard let timing = w.result?.timings[activity.id] else { return "" }; return w.date(finish && timing.finish > timing.start ? timing.finish-1 : (finish ? timing.finish : timing.start)) }
    var locked:Bool { finish ? activity.lockFinish == true : activity.lockStart == true }
    var requested:String? { finish ? activity.requestedFinish : activity.requestedStart }
    func update(_ body:(inout Activity)->Void) { w.change { p in if let i = p.activities.firstIndex(where:{ $0.id == activity.id }) { body(&p.activities[i]) } }; text = calculated }
    var body: some View {
        HStack(spacing:2) {
            CalendarDateButton(value:calculated,title:"\(finish ? "Окончание" : "Начало") \(activity.id)",plan:w.plan) { value in
                var next = w.plan
                guard let i = next.activities.firstIndex(where:{ $0.id == activity.id }) else { return "Задача удалена" }
                next.activities[i].earliestStart = nil
                if finish { next.activities[i].requestedFinish = value.isEmpty ? nil : value; if value.isEmpty { next.activities[i].lockFinish = false } }
                else { next.activities[i].requestedStart = value.isEmpty ? nil : value; if value.isEmpty { next.activities[i].lockStart = false } }
                do { let result = try Planner.calculate(next); w.install(next,calculation:result); w.dirty = true; text = calculated; return nil } catch { return error.localizedDescription }
            }.help("Расчёт: \(calculated). Назначено: \(requested ?? "нет"). Нажмите для выбора в календаре.")
            Toggle(finish ? "Фиксировать окончание \(activity.id)" : "Фиксировать начало \(activity.id)",isOn:Binding(get:{ locked },set:{ value in
                let date = text.isEmpty ? calculated : text
                update { task in task.earliestStart = nil; if finish { task.lockFinish = value; if value { task.requestedFinish = date } } else { task.lockStart = value; if value { task.requestedStart = date } } }
            })).labelsHidden().toggleStyle(.checkbox).help("Точное соблюдение даты; конфликтующее изменение будет отклонено")
        }.disabled(activity.entityType == "summary").onAppear { text = calculated }.onChange(of:calculated) { _,value in text = value }.onChange(of:requested) { _,_ in text = calculated }
    }
}
struct TaskProperties: View {
    @EnvironmentObject var w:Workspace
    @Environment(\.dismiss) var dismiss
    let activity:Activity
    @State private var draft:Activity
    @State private var start = ""
    @State private var finish = ""
    @State private var error = ""
    init(activity:Activity) { self.activity = activity; _draft = State(initialValue:activity); _start = State(initialValue:activity.requestedStart ?? ""); _finish = State(initialValue:activity.requestedFinish ?? "") }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Свойства · \(activity.id)").font(.title2.bold())
            Form {
                TextField("Название",text:$draft.name)
                Text("Тип: \(EntityKind.title(draft.entityType))")
                TextField("Длительность, раб. дни",value:$draft.duration,format:.number).disabled(draft.entityType != "task" || draft.productivity != nil || (draft.volume != nil && w.plan.resources.first(where:{ $0.id == draft.resource })?.productivity != nil))
                TextField("Приоритет 0–1000",value:Binding(get:{ draft.priority ?? 500 },set:{ draft.priority = $0 }),format:.number).disabled(draft.entityType == "summary")
                TextField("Потребность ресурса",value:$draft.units,format:.number).disabled(draft.entityType != "task")
                Picker("Ресурс",selection:$draft.resource) { Text("Не назначен").tag(""); ForEach(w.plan.resources) { Text($0.name).tag($0.id) } }.disabled(draft.entityType != "task")
                TextField("Объём",value:$draft.volume,format:.number).disabled(draft.entityType != "task")
                Picker("Единица объёма",selection:Binding(get:{ draft.volumeUnit ?? "" },set:{ draft.volumeUnit = $0.isEmpty ? nil : $0 })) { Text("—").tag(""); ForEach(w.plan.measurementUnits) { Text($0.symbol).tag($0.symbol) } }.disabled(draft.entityType != "task")
                HStack { CalendarDateButton(value:start,title:"Начало",plan:w.plan) { value in start = value; if value.isEmpty { draft.lockStart = false }; return nil }; Toggle("Фиксировать",isOn:Binding(get:{ draft.lockStart == true },set:{ draft.lockStart = $0 })) }.disabled(draft.entityType == "summary")
                HStack { CalendarDateButton(value:finish,title:"Окончание",plan:w.plan) { value in finish = value; if value.isEmpty { draft.lockFinish = false }; return nil }; Toggle("Фиксировать",isOn:Binding(get:{ draft.lockFinish == true },set:{ draft.lockFinish = $0 })) }.disabled(draft.entityType == "summary")
            }
            Text("Без фиксации дата задаёт нижнюю границу, связи могут отложить работу. С фиксацией дата должна соблюдаться точно. Больше приоритет — раньше при конкуренции за ресурс.").font(.caption).foregroundStyle(.secondary)
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
            HStack { Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Применить") {
                guard !draft.name.trimmingCharacters(in:.whitespaces).isEmpty else { error = "Введите название"; return }
                draft.requestedStart = start.isEmpty ? nil : start; draft.requestedFinish = finish.isEmpty ? nil : finish
                if draft.requestedStart != activity.requestedStart || draft.requestedFinish != activity.requestedFinish { draft.earliestStart = nil }
                var next = w.plan
                guard let i = next.activities.firstIndex(where:{ $0.id == activity.id }) else { error = "Задача удалена"; return }
                next.activities[i] = draft
                do { let result = try Planner.calculate(next); w.install(next,calculation:result); w.dirty = true; dismiss() } catch { self.error = error.localizedDescription }
            }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
        }.padding(26).frame(width:580)
    }
}
struct ResourceLoadPanel: View {
    @EnvironmentObject var w:Workspace
    let plan:Schedule
    let result:Calculation
    let tableWidth:CGFloat
    let dayWidth:CGFloat
    let chartWidth:CGFloat
    let days:Int
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            Divider()
            HStack(spacing:0) {
                Text("Загрузка ресурсов · \(plan.levelResources ?? true ? "по приоритетам" : "без выравнивания")").font(.headline).padding(.leading,10).frame(width:tableWidth,alignment:.leading)
                HStack(spacing:0) { ForEach(0..<days,id:\.self) { day in Text(dayWidth >= 16 || day % 5 == 0 ? "\(day)" : "").lineLimit(1).minimumScaleFactor(0.5).font(.system(size:9)).frame(width:dayWidth) } }.frame(width:chartWidth,alignment:.leading)
            }.frame(height:28).background(Color(nsColor:.controlBackgroundColor))
            ScrollView(.vertical) {
                LazyVStack(spacing:0) {
                    ForEach(plan.resources) { resource in
                        let type = plan.resourceTypes.first { $0.id == resource.typeID }
                        let symbol = plan.measurementUnits.first { $0.id == type?.outputUnitID }?.symbol ?? "ед."
                        let loads = w.snapshot.loads(resource,days:days)
                        HStack(spacing:0) {
                            HStack { Text(resource.name).bold(); Text("Доступно: \(resource.capacity.formatted())").foregroundStyle(.secondary); if let p = resource.productivity { Text("Выработка: \(p.formatted()) \(symbol)/\(resource.timeUnit == "hour" ? "ч" : "дн") на единицу").foregroundStyle(.secondary) }; Spacer() }.font(.caption).padding(.leading,10).frame(width:tableWidth)
                            ResourceHeatmap(loads:loads,width:chartWidth,dayWidth:dayWidth,title:resource.name,symbol:symbol,date:{ w.date($0) })
                        }.frame(height:34)
                    }
                }
            }.frame(maxHeight:.infinity)
            Text("% — занятая доля ресурса; второе число — плановый объём выработки за день. Подсказка показывает детали; в последний день учитывается остаток объёма.").font(.caption2).foregroundStyle(.secondary).padding(5)
        }.frame(width:tableWidth+chartWidth,height:200,alignment:.topLeading).background(Color(nsColor:.textBackgroundColor))
    }
}

struct NativeTaskMenu: NSViewRepresentable {
    let properties:()->Void
    let select:()->Void
    let delete:()->Void
    let group:(()->Void)?
    func makeNSView(context:Context) -> TaskMenuSurface { TaskMenuSurface() }
    func updateNSView(_ view:TaskMenuSurface,context:Context) { view.onProperties = properties; view.onSelect = select; view.onDelete = delete; view.onGroup = group }
}
final class TaskMenuSurface: NSView {
    var onProperties:(()->Void)?
    var onSelect:(()->Void)?
    var onDelete:(()->Void)?
    var onGroup:(()->Void)?
    private var monitor:Any?
    override func hitTest(_ point:NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching:[.rightMouseDown,.leftMouseDown]) { [weak self] event in
            guard let self, event.window === self.window, event.type == .rightMouseDown || event.modifierFlags.contains(.control) else { return event }
            let point = self.convert(event.locationInWindow,from:nil)
            guard self.visibleRect.contains(point) else { return event }
            self.rightMouseDown(with:event); return nil
        }
    }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    override func mouseDown(with event:NSEvent) { if event.modifierFlags.contains(.control) { rightMouseDown(with:event) } else { super.mouseDown(with:event) } }
    override func rightMouseDown(with event:NSEvent) {
        let menu = NSMenu()
        func add(_ title:String,_ selector:Selector) { let item = NSMenuItem(title:title,action:selector,keyEquivalent:""); item.target = self; menu.addItem(item) }
        add("Свойства…",#selector(propertiesAction)); add("Выбрать задачу",#selector(selectAction))
        if onGroup != nil { add("Объединить выбранные в суммарную",#selector(groupAction)) }
        menu.addItem(.separator()); add("Удалить",#selector(deleteAction))
        NSMenu.popUpContextMenu(menu,with:event,for:self)
    }
    @objc func propertiesAction() { onProperties?() }
    @objc func selectAction() { onSelect?() }
    @objc func groupAction() { onGroup?() }
    @objc func deleteAction() { onDelete?() }
}
