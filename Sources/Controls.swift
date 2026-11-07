import SwiftUI
import AppKit

struct CalendarDateButton: View {
    let value:String
    let title:String
    let plan:Schedule
    let commit:(String)->String?
    @State private var presented = false
    var body: some View {
        Button { presented = true } label: {
            HStack(spacing:3) { Text(value.isEmpty ? title : value).lineLimit(1).minimumScaleFactor(0.8); Image(systemName:"calendar").font(.system(size:9)).foregroundStyle(.secondary) }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
        }.buttonStyle(.plain).font(.system(size:10).monospacedDigit()).accessibilityLabel("Календарь: \(title)")
        .popover(isPresented:$presented,arrowEdge:.bottom) {
            QuickCalendar(value:value,title:title,plan:plan) { date in
                if let error = commit(date) { return error }
                presented = false; return nil
            } cancel: { presented = false }
        }
    }
}
struct QuickCalendar: View {
    let value:String
    let title:String
    let plan:Schedule
    let choose:(String)->String?
    let cancel:()->Void
    @State private var year:Int
    @State private var month:Int
    @State private var error = ""
    private let months = ["Январь","Февраль","Март","Апрель","Май","Июнь","Июль","Август","Сентябрь","Октябрь","Ноябрь","Декабрь"]
    init(value:String,title:String,plan:Schedule,choose:@escaping(String)->String?,cancel:@escaping()->Void) {
        self.value = value; self.title = title; self.plan = plan; self.choose = choose; self.cancel = cancel
        let parts = (Planner.validDate(value) ? value : plan.startDate).split(separator:"-")
        _year = State(initialValue:Int(parts[0]) ?? 2026); _month = State(initialValue:Int(parts[1]) ?? 1)
    }
    var years:ClosedRange<Int> { let base = Int(plan.startDate.prefix(4)) ?? year; return max(1,min(base-50,year))...min(9999,max(base+400,year)) }
    func allowed(_ date:String) -> Bool {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier:"en_US_POSIX"); formatter.timeZone = TimeZone(identifier:plan.calendar.timezone); formatter.dateFormat = "yyyy-MM-dd"
        guard let parsed = formatter.date(from:date), date >= Planner.date(0,plan:plan) else { return false }
        var calendar = Calendar(identifier:.gregorian); calendar.timeZone = formatter.timeZone
        return plan.calendar.weekdays.contains(calendar.component(.weekday,from:parsed)) && !plan.calendar.holidays.contains(date)
    }
    func step(_ amount:Int) { var next = month+amount; if next == 0 { guard year > 1 else { return }; year -= 1; next = 12 }; if next == 13 { guard year < 9999 else { return }; year += 1; next = 1 }; month = next; error = "" }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Text(title).font(.headline)
            HStack {
                Button { step(-1) } label: { Image(systemName:"chevron.left") }.help("Предыдущий месяц")
                Picker("Месяц",selection:$month) { ForEach(1...12,id:\.self) { number in Text(months[number-1]).tag(number) } }.labelsHidden().frame(width:145)
                Picker("Год",selection:$year) { ForEach(years,id:\.self) { number in Text(String(number)).tag(number) } }.labelsHidden().frame(width:95)
                Button { step(1) } label: { Image(systemName:"chevron.right") }.help("Следующий месяц")
            }
            LazyVGrid(columns:Array(repeating:GridItem(.fixed(38),spacing:3),count:7),spacing:4) {
                ForEach(["Пн","Вт","Ср","Чт","Пт","Сб","Вс"],id:\.self) { Text($0).font(.caption.bold()).foregroundStyle(.secondary).frame(height:22) }
                let grid = CalendarGrid.days(year:year,month:month)
                ForEach(0..<grid.count,id:\.self) { index in
                    if let date = grid[index] {
                        Button { error = choose(date) ?? "" } label: { Text(String(Int(date.suffix(2)) ?? 0)).frame(width:36,height:28).background(date == value ? Color.teal.opacity(0.22) : .clear).clipShape(RoundedRectangle(cornerRadius:5)) }.buttonStyle(.plain).disabled(!allowed(date)).help(date)
                    } else { Color.clear.frame(width:36,height:28) }
                }
            }
            Text("Выберите рабочий день. Выходные и исключения календаря недоступны.").font(.caption).foregroundStyle(.secondary)
            if !error.isEmpty { Text(error).foregroundStyle(.red).font(.callout).fixedSize(horizontal:false,vertical:true) }
            HStack { Button("Снять назначение") { error = choose("") ?? "" }; Spacer(); Button("Отмена",action:cancel).keyboardShortcut(.cancelAction) }
        }.padding(18).frame(width:330).onChange(of:month) { _,_ in error = "" }.onChange(of:year) { _,_ in error = "" }
    }
}
struct TaskKeyboardHandler: NSViewRepresentable {
    let enabled:Bool
    let delete:()->Void
    func makeNSView(context:Context) -> KeyboardSurface { KeyboardSurface() }
    func updateNSView(_ view:KeyboardSurface,context:Context) { view.enabled = enabled; view.onDelete = delete }
}
final class KeyboardSurface:NSView {
    var enabled = false
    var onDelete:(()->Void)?
    private var monitor:Any?
    override func hitTest(_ point:NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
            guard let self, self.enabled, event.window === self.window, NSApp.keyWindow === self.window, self.window?.attachedSheet == nil, [51,117].contains(event.keyCode), event.modifierFlags.intersection([.command,.control,.option]).isEmpty else { return event }
            if let editor = self.window?.firstResponder as? NSTextView, editor.isEditable { return event }
            if self.window?.firstResponder is NSTextField { return event }
            self.onDelete?(); return nil
        }
    }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}

struct TimelineHeader:View {
    static let height:CGFloat = 76
    let plan:Schedule
    let days:Int
    let dayWidth:CGFloat
    var body: some View {
        let scale = TimelineCalendar(plan:plan,count:days)
        VStack(alignment:.leading,spacing:0) {
            bands(scale.years,emphasized:true)
            bands(scale.months,emphasized:false)
            HStack(spacing:0) {
                ForEach(0..<days,id:\.self) { day in
                    Text(dayWidth >= 16 || day % 5 == 0 ? "\(day)" : "").lineLimit(1).minimumScaleFactor(0.5).font(.system(size:10)).foregroundStyle(.secondary).frame(width:dayWidth,height:32).help(scale.dates[day])
                }
            }
        }.frame(height:Self.height,alignment:.topLeading)
    }
    func bands(_ bands:[TimelineBand],emphasized:Bool) -> some View {
        HStack(spacing:0) {
            ForEach(bands) { band in
                Text(band.label).font(.system(size:emphasized ? 11 : 10,weight:emphasized ? .semibold : .regular)).lineLimit(1).minimumScaleFactor(0.5).padding(.leading,4).frame(width:CGFloat(band.count)*dayWidth,height:22,alignment:.leading).background(emphasized ? Color.teal.opacity(0.10) : Color.secondary.opacity(0.06)).overlay(alignment:.trailing) { Rectangle().fill(Color.secondary.opacity(0.25)).frame(width:1) }.overlay(alignment:.bottom) { Rectangle().fill(Color.secondary.opacity(0.18)).frame(height:0.5) }.help(band.label)
            }
        }
    }
}

struct ScheduleColumn:Identifiable {
    let id:String
    let title:String
    let width:CGFloat
    static let all:[ScheduleColumn] = [
        .init(id:"select",title:"✓",width:26),.init(id:"code",title:"Код",width:45),
        .init(id:"kind",title:"Тип",width:95),.init(id:"name",title:"Название задачи",width:210),
        .init(id:"duration",title:"Длительность",width:100),.init(id:"start",title:"Начало · фикс.",width:125),
        .init(id:"finish",title:"Окончание · фикс.",width:125),.init(id:"volume",title:"Объём",width:75),
        .init(id:"unit",title:"Ед. изм.",width:65),.init(id:"parent",title:"Родитель",width:100),
        .init(id:"resource",title:"Ресурс",width:125),.init(id:"priority",title:"Приоритет",width:70),
        .init(id:"demand",title:"Потребн.",width:50),.init(id:"progress",title:"%",width:45),
        .init(id:"menu",title:"",width:40)
    ]
}
extension View {
    @ViewBuilder func optionalColumn(_ visible:Bool) -> some View { if visible { self } }
}

struct GraphScaleSettings:View {
    @Binding var fit:Bool
    @Binding var zoom:Double
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Масштаб графика").font(.headline)
            Toggle("Весь проект по ширине окна",isOn:$fit)
            HStack {
                Button("Дни") { fit = false; zoom = 32 }
                Button("Недели") { fit = false; zoom = 10 }
                Button("Месяцы") { fit = false; zoom = 3 }
            }
            Text("Ширина рабочего дня: \(zoom.formatted(.number.precision(.fractionLength(0)))) пт")
            Slider(value:Binding(get:{ zoom },set:{ zoom = $0; fit = false }),in:2...160).accessibilityLabel("Ширина рабочего дня")
            HStack { Button("−") { fit = false; zoom = max(2,zoom/1.25) }; Button("+") { fit = false; zoom = min(160,zoom*1.25) }; Spacer(); Button("Сбросить") { fit = true; zoom = 24 } }
            Text("В ручном масштабе прокручивайте график горизонтально. Панель загрузки закреплена снизу и следует за шкалой по горизонтали.").font(.caption).foregroundStyle(.secondary)
        }.padding(20).frame(width:350)
    }
}

struct HorizontalScrollObserver:NSViewRepresentable {
    let changed:(CGFloat)->Void
    func makeNSView(context:Context) -> ScrollObserverSurface { ScrollObserverSurface() }
    func updateNSView(_ view:ScrollObserverSurface,context:Context) { view.changed = changed; view.attach() }
}
final class ScrollObserverSurface:NSView {
    var changed:((CGFloat)->Void)?
    private var token:NSObjectProtocol?
    private weak var observed:NSClipView?
    override func hitTest(_ point:NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); attach() }
    func attach() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let clip = self.enclosingScrollView?.contentView, self.observed !== clip else { return }
            if let token = self.token { NotificationCenter.default.removeObserver(token) }
            self.observed = clip; clip.postsBoundsChangedNotifications = true
            self.changed?(clip.bounds.origin.x)
            self.token = NotificationCenter.default.addObserver(forName:NSView.boundsDidChangeNotification,object:clip,queue:.main) { [weak self,weak clip] _ in
                guard let clip else { return }; let x = clip.bounds.origin.x
                DispatchQueue.main.async { self?.changed?(x) }
            }
        }
    }
    deinit { if let token { NotificationCenter.default.removeObserver(token) } }
}
