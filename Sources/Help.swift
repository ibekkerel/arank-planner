import SwiftUI
import AppKit

struct HelpDocument: Decodable {
    let version: String
    let reviewedRevision: String
    let sections: [HelpTopic]
}
struct HelpTopic: Decodable, Identifiable {
    let id: String
    let group: String
    let title: String
    let paragraphs: [String]
}
struct PlannerHelpView: View {
    @State private var query = ""
    @State private var selectedID: String? = "intro"
    private let document: HelpDocument?
    init() {
        if let url = Bundle.main.url(forResource:"Help",withExtension:"json"),
           let data = try? Data(contentsOf:url) {
            document = try? JSONDecoder().decode(HelpDocument.self,from:data)
        } else { document = nil }
    }
    private var topics: [HelpTopic] {
        let needle = query.trimmingCharacters(in:.whitespacesAndNewlines)
        return (document?.sections ?? []).filter { topic in
            needle.isEmpty || ([topic.title,topic.group] + topic.paragraphs).joined(separator:" ").localizedCaseInsensitiveContains(needle)
        }
    }
    private var current: HelpTopic? { topics.first { $0.id == selectedID } ?? topics.first }
    var body: some View {
        VStack(spacing:0) {
            HStack {
                Text("ARANK Planner · Справка").font(.headline)
                Spacer()
                if let document { Text("Версия \(document.version)").foregroundStyle(.secondary) }
            }.padding()
            Divider()
            if document == nil {
                ContentUnavailableView("Справка недоступна",systemImage:"exclamationmark.triangle",description:Text("Ресурс Help.json отсутствует или повреждён. Пересоберите полный пакет приложения."))
            } else {
                HStack(spacing:0) {
                    VStack {
                        HStack {
                            TextField("Поиск по справке",text:$query).textFieldStyle(.roundedBorder)
                            Button("Сброс") { query = "" }.disabled(query.isEmpty)
                        }.padding(10)
                        List(selection:$selectedID) {
                            ForEach(["Пользователь","Администратор","Разработчик"],id:\.self) { group in
                                let matches = topics.filter { $0.group == group }
                                if !matches.isEmpty {
                                    Section(group) { ForEach(matches) { topic in Text(topic.title).tag(topic.id) } }
                                }
                            }
                        }
                    }.frame(width:290)
                    Divider()
                    if let topic = current {
                        VStack(alignment:.leading,spacing:0) {
                            HStack {
                                Text(topic.group).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("Копировать тему") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(([topic.title] + topic.paragraphs).joined(separator:"\n\n"),forType:.string)
                                }
                            }.padding()
                            ScrollView {
                                VStack(alignment:.leading,spacing:18) {
                                    Text(topic.title).font(.title.bold())
                                    ForEach(Array(topic.paragraphs.enumerated()),id:\.offset) { _, paragraph in
                                        Text(paragraph).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
                                    }
                                }.padding(24).frame(maxWidth:.infinity,alignment:.leading)
                            }.id(topic.id)
                        }
                    } else {
                        ContentUnavailableView("Ничего не найдено",systemImage:"magnifyingglass",description:Text("Измените запрос или нажмите «Сброс»."))
                    }
                }
            }
        }.frame(minWidth:850,minHeight:600)
    }
}
