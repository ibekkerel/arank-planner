import SwiftUI

@MainActor
struct WorkspaceGuideSheet: View {
    let openExample: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var lines: [String] {
        guard let url = Bundle.main.url(forResource:"WORKSPACE-GUIDE",withExtension:"md"),
              let guide = try? String(contentsOf:url,encoding:.utf8) else {
            return ["Справку не удалось загрузить. Учебный график можно открыть кнопкой ниже."]
        }
        return guide.components(separatedBy:.newlines)
            .filter { !$0.hasPrefix("# ") && !$0.isEmpty }
            .prefix { $0 != "## Проверка на Mac" }
            .map { $0.replacingOccurrences(of:"[пример «Очередь крана»](Examples/resource-scenarios.osched)",with:"пример «Очередь крана»") }
    }

    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            Label("Справка ARANK Planner",systemImage:"questionmark.circle")
                .font(.title2.bold()).accessibilityAddTraits(.isHeader).padding(20)
            Divider()
            ScrollView {
                VStack(alignment:.leading,spacing:12) {
                    ForEach(Array(lines.enumerated()),id:\.offset) { _,line in
                        if line.hasPrefix("## ") {
                            Text(String(line.dropFirst(3))).font(.headline).accessibilityAddTraits(.isHeader)
                        } else {
                            let parsed = try? AttributedString(markdown:line,options:.init(interpretedSyntax:.inlineOnlyPreservingWhitespace))
                            Text(parsed ?? AttributedString(line)).fixedSize(horizontal:false,vertical:true)
                        }
                    }
                }
                .frame(maxWidth:.infinity,alignment:.leading)
                .padding(20)
            }
            Divider()
            HStack {
                Button("Открыть учебный график",action:openExample).buttonStyle(.borderedProminent)
                Spacer()
                Button("Закрыть") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(16)
        }.frame(width:650,height:535)
    }
}
