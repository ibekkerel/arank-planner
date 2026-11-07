import SwiftUI

struct ResourceCalendarEditor:View {
    @EnvironmentObject var w:Workspace
    @Environment(\.dismiss) var dismiss
    @State var draft:ResourceCalendar
    @State var weekText:[Int:String]
    @State var exceptionText:[String:String]
    @State var error = ""
    init(calendar:ResourceCalendar) {
        _draft = State(initialValue:calendar)
        _weekText = State(initialValue:Dictionary(uniqueKeysWithValues:calendar.week.map { ($0.weekday,WorkInterval.text($0.intervals)) }))
        _exceptionText = State(initialValue:Dictionary(uniqueKeysWithValues:calendar.exceptions.map { ($0.id,WorkInterval.text($0.intervals)) }))
    }
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            Text("Календарь ресурса").font(.title2.bold())
            TextField("Название календаря",text:$draft.name)
            ScrollView {
                VStack(alignment:.leading,spacing:12) {
                    HStack { Text("Рабочая неделя").font(.headline); Spacer(); Button("5/2 · 8 часов") { for day in 1...7 { weekText[day] = (2...6).contains(day) ? "09:00-13:00, 14:00-18:00" : "" } }; Button("Ежедневно · 8 часов") { for day in 1...7 { weekText[day] = "09:00-13:00, 14:00-18:00" } } }
                    Text("Пустое поле — выходной. Несколько интервалов разделяйте запятой; время 00:00–24:00. Ночные смены разделите на два дня.").font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(zip([2,3,4,5,6,7,1],["Понедельник","Вторник","Среда","Четверг","Пятница","Суббота","Воскресенье"])),id:\.0) { day,title in
                        HStack { Text(title).frame(width:120,alignment:.leading); TextField("Выходной или 09:00-13:00, 14:00-18:00",text:Binding(get:{ weekText[day] ?? "" },set:{ weekText[day] = $0 })).accessibilityLabel(title) }
                    }
                    Divider()
                    HStack { Text("Отпуска, праздники и исключения").font(.headline); Spacer(); Button("Добавить период",systemImage:"plus") { draft.exceptions.append(CalendarException(from:w.plan.startDate,through:w.plan.startDate)) } }
                    Text("Исключение заменяет рабочую неделю на весь период включительно. При пересечении периодов действует последнее в списке. Праздники задаются явно; автоматического государственного календаря нет.").font(.caption).foregroundStyle(.secondary)
                    ForEach($draft.exceptions) { $exception in
                        VStack(alignment:.leading,spacing:7) {
                            HStack {
                                TextField("Название",text:$exception.name)
                                Picker("Тип исключения",selection:$exception.kind) { Text("Отпуск").tag("vacation"); Text("Праздник").tag("holiday"); Text("Нерабочий период").tag("off"); Text("Рабочее время").tag("working") }.frame(width:230)
                                Button(role:.destructive) { draft.exceptions.removeAll { $0.id == exception.id } } label: { Image(systemName:"trash") }
                            }
                            HStack { Text("С"); ISOCalendarDate(value:$exception.from,plan:w.plan,title:"Начало периода"); Text("по"); ISOCalendarDate(value:$exception.through,plan:w.plan,title:"Конец периода") }
                            if exception.kind == "working" { TextField("Часы: 09:00-13:00",text:Binding(get:{ exceptionText[exception.id] ?? "" },set:{ exceptionText[exception.id] = $0 })) }
                        }.padding(10).background(Color.secondary.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius:6))
                    }
                    Text("Используется часовой пояс проекта. Доступны только дни, разрешённые календарём проекта. Дневная производительность и ставка пересчитываются относительно 8 часов; почасовая — по фактическим часам смен. Даты задач округляются до рабочего дня; деление смен между несколькими задачами внутри дня пока не выполняется.").font(.caption).foregroundStyle(.secondary)
                }.padding(2)
            }
            if !error.isEmpty { Text(error).font(.callout).foregroundStyle(.red) }
            HStack { Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Сохранить календарь") { save() }.buttonStyle(.borderedProminent) }
        }.padding(22).frame(width:760,height:650)
    }
    func save() {
        do {
            var value = draft
            value.week = try (1...7).map { ResourceWorkday(weekday:$0,intervals:try WorkInterval.parse(weekText[$0] ?? "")) }
            for i in value.exceptions.indices { value.exceptions[i].intervals = value.exceptions[i].kind == "working" ? try WorkInterval.parse(exceptionText[value.exceptions[i].id] ?? "") : [] }
            var next = w.plan
            if let index = next.resourceCalendars?.firstIndex(where:{ $0.id == value.id }) { next.resourceCalendars![index] = value }
            else { if next.resourceCalendars == nil { next.resourceCalendars = [] }; next.resourceCalendars!.append(value) }
            let result = try Planner.calculate(next); w.install(next,calculation:result); w.dirty = true; dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
struct ISOCalendarDate:View {
    @Binding var value:String
    let plan:Schedule
    let title:String
    var allDates:Schedule { var copy = plan; copy.startDate = "1900-01-01"; copy.calendar.weekdays = Array(1...7); copy.calendar.holidays = []; return copy }
    var body:some View {
        HStack { TextField("ГГГГ-ММ-ДД",text:$value).frame(width:110); CalendarDateButton(value:value,title:title,plan:allDates) { date in guard !date.isEmpty else { return "Укажите дату" }; value = date; return nil }.frame(width:100) }
    }
}
