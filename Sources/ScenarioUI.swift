import SwiftUI

/// Compare an immutable project snapshot before making any change to the open schedule.
@MainActor
struct ResourceScenarioSheet: View {
    @ObservedObject var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var input: Schedule?
    @State private var comparison: ResourceStrategyComparison?
    @State private var error: String?

    init(workspace: Workspace) { self.workspace = workspace }

    private var storedStrategy: ResourceStrategy { workspace.plan.resourceStrategy ?? .standard }
    private var canApply: Bool {
        guard let input, input == workspace.plan, let comparison, comparison.limitation == nil else { return false }
        return comparison.selected != storedStrategy || workspace.needsCalculation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                Label("Сравнение вариантов", systemImage: "arrow.triangle.branch")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(workspace.plan.name).foregroundStyle(.secondary).lineLimit(1)
                Text("Приложение сравнит правила выбора следующей работы при дефиците ресурсов. Связи, ограничения и назначения не меняются.")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let comparison {
                        summary(comparison)
                        trials(comparison)
                        changes(comparison)
                    } else if let error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.primary)
                        Text("Это не доказывает, что расписание невозможно. Проверьте ограничения или назначение ресурсов.")
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView("Сравниваю варианты…")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            Divider()
            HStack(spacing: 12) {
                if storedStrategy != .standard {
                    Button("Вернуть обычный расчёт", action: restoreStandard)
                        .help("Снять выбор стратегии для проекта")
                }
                Spacer()
                Button("Закрыть") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Применить к графику", action: apply)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canApply)
                    .help("Выбор стратегии сохранится с проектом; базовый план не меняется")
            }
            .padding(16)
        }
        .frame(width: 650, height: 540)
        .task(id: workspace.plan) { await compare(workspace.plan) }
    }

    private func summary(_ comparison: ResourceStrategyComparison) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if let limitation = comparison.limitation {
                Label(limitation, systemImage: "info.circle")
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Лучший из проверенных: \(comparison.best.duration) раб. дн.")
                    .font(.headline)
                if let standard = comparison.standard, standard.duration > comparison.best.duration {
                    Label("На \(standard.duration - comparison.best.duration) раб. дн. короче обычного расчёта", systemImage: "arrow.down.right")
                        .foregroundStyle(.green)
                } else if comparison.standard == nil {
                    Text("Обычный расчёт не построил расписание; один из вариантов сработал.")
                }
                Text("Это подбор варианта, а не доказательство оптимальности.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
    }

    private func trials(_ comparison: ResourceStrategyComparison) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Правила расчёта")
                .font(.headline).accessibilityAddTraits(.isHeader)
                .padding(.bottom, 6)
            ForEach(comparison.trials, id: \.strategy) { trial in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(trial.strategy.title)
                        if let failure = trial.failure {
                            Text(failure).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                    Spacer(minLength: 0)
                    if trial.strategy == storedStrategy && comparison.limitation == nil {
                        Text("В проекте").font(.caption).foregroundStyle(.secondary)
                    }
                    if trial.strategy == comparison.selected && comparison.limitation == nil {
                        Text("Лучший").font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                    }
                    Text(trial.duration.map { "\($0) дн." } ?? "Не найдено")
                        .monospacedDigit().fontWeight(.semibold)
                }
                .padding(.vertical, 8)
                Divider()
            }
        }
    }

    private struct Change: Identifiable {
        let id: String
        let name: String
        let start: Int
        let finish: Int
    }

    @ViewBuilder private func changes(_ comparison: ResourceStrategyComparison) -> some View {
        if let input, let standard = comparison.standard, comparison.selected != .standard {
            let shifted: [Change] = input.activities.compactMap { activity in
                guard activity.entityType != "summary", let before = standard.timings[activity.id],
                      let after = comparison.best.timings[activity.id],
                      before.start != after.start || before.finish != after.finish else { return nil }
                return Change(id: activity.id, name: activity.name,
                              start: after.start - before.start, finish: after.finish - before.finish)
            }
            if !shifted.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Какие работы сдвинутся (\(shifted.count))")
                        .font(.headline).accessibilityAddTraits(.isHeader)
                    Text("Относительно обычного расчёта, в рабочих днях. Минус означает раньше.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(shifted) { item in
                        HStack(spacing: 12) {
                            Text(item.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                            Text(item.name).lineLimit(1).help(item.name)
                            Spacer(minLength: 4)
                            Text("Старт \(delta(item.start)) · Финиш \(delta(item.finish))")
                                .font(.caption.monospacedDigit())
                        }
                    }
                }
            }
        }
    }

    private func delta(_ value: Int) -> String {
        value > 0 ? "+\(value)" : value < 0 ? "−\(-value)" : "0"
    }

    private func compare(_ plan: Schedule) async {
        guard !Task.isCancelled else { return }
        input = plan
        comparison = nil
        error = nil
        let calculation = Task.detached(priority: .userInitiated) { try Planner.compareResourceStrategies(plan) }
        do {
            let result = try await withTaskCancellationHandler(
                operation: { try await calculation.value },
                onCancel: { calculation.cancel() }
            )
            guard !Task.isCancelled, plan == workspace.plan else { return }
            comparison = result
        } catch {
            guard !Task.isCancelled, plan == workspace.plan else { return }
            self.error = error.localizedDescription
        }
    }

    private func apply() {
        guard canApply, var next = input, let comparison else { return }
        next.resourceStrategy = comparison.selected == .standard ? nil : comparison.selected
        let hasChanged = next != workspace.plan
        workspace.install(next, calculation: comparison.best)
        if hasChanged { workspace.dirty = true }
        dismiss()
    }

    private func restoreStandard() {
        do {
            var next = workspace.plan
            next.resourceStrategy = nil
            try workspace.accept(next)
            dismiss()
        } catch {
            self.error = "Не удалось вернуть обычный расчёт: \(error.localizedDescription)"
            comparison = nil
        }
    }
}
