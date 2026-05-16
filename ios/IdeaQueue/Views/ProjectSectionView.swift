import SwiftUI

struct ProjectSectionView: View {
    @ObservedObject var store: DashboardStore
    let project: String

    var body: some View {
        VStack(spacing: 5) {
            header

            if !store.collapsedProjects.contains(project) {
                GeometryReader { proxy in
                    let layout = TableLayout(availableWidth: proxy.size.width)
                    let visibleIdeas = store.visibleIdeas(in: project)

                    VStack(spacing: 0) {
                        headerRow(layout: layout)
                        ForEach(visibleIdeas, id: \.0) { index, idea in
                            IdeaRowView(
                                store: store,
                                project: project,
                                index: index,
                                idea: idea,
                                allProjects: store.orderedProjects,
                                layout: layout
                            )
                        }
                    }
                }
                .frame(height: TableLayout.heightForProject(
                    availableWidth: UIScreen.main.bounds.width,
                    rowCount: store.visibleIdeas(in: project).count
                ))
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
            }
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(uiColor: .systemBackground))
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button {
                store.toggleCollapse(project: project)
            } label: {
                HStack(spacing: 4) {
                    Text(store.collapsedProjects.contains(project) ? "▶" : "▼")
                    Text(project)
                        .fontWeight(.semibold)
                    Text("(\(store.visibleIdeas(in: project).count)/\((store.document.queueProjects[project] ?? []).count))")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 11, design: .monospaced))
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            smallButton("↑") { store.moveProjectUp(project) }
            smallButton("↓") { store.moveProjectDown(project) }
            smallButton("+") { store.addIdea(to: project) }
            smallButton("sort") { store.sortProjectByPriority(project) }
        }
    }

    private func headerRow(layout: TableLayout) -> some View {
        HStack(spacing: 0) {
            headerCell("", width: layout.controlWidth)
            headerCell("name", width: layout.nameWidth)
            headerCell("human", width: layout.humanWidth)

            if !layout.isCompact {
                headerCell("desc", width: layout.descriptionWidth)
                headerCell("rel", width: layout.relatedWidth)
                headerCell("d", width: layout.difficultyWidth)
            }

            headerCell("", width: layout.priorityWidth)
        }
        .frame(height: layout.headerHeight)
    }

    private func headerCell(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .font(.system(size: 10, design: .monospaced))
            .fontWeight(.semibold)
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.08))
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color.black.opacity(0.08))
                    .frame(width: 1)
            }
    }

    private func smallButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 10, design: .monospaced))
            .buttonStyle(.bordered)
            .controlSize(.mini)
    }
}

private struct TableLayout {
    let availableWidth: CGFloat

    var isCompact: Bool { availableWidth < 700 }
    var controlWidth: CGFloat { 28 }
    var priorityWidth: CGFloat { 28 }
    var difficultyWidth: CGFloat { isCompact ? 0 : 34 }
    var headerHeight: CGFloat { 24 }
    var rowHeight: CGFloat { isCompact ? 42 : 44 }

    var contentWidth: CGFloat {
        max(availableWidth - controlWidth - priorityWidth - difficultyWidth, 160)
    }

    var nameWidth: CGFloat {
        floor(contentWidth * (isCompact ? 0.30 : 0.18))
    }

    var humanWidth: CGFloat {
        floor(contentWidth * (isCompact ? 0.70 : 0.28))
    }

    var descriptionWidth: CGFloat {
        guard !isCompact else { return 0 }
        return floor(contentWidth * 0.32)
    }

    var relatedWidth: CGFloat {
        guard !isCompact else { return 0 }
        return max(contentWidth - nameWidth - humanWidth - descriptionWidth, 90)
    }

    static func heightForProject(availableWidth: CGFloat, rowCount: Int) -> CGFloat {
        let layout = TableLayout(availableWidth: availableWidth)
        return layout.headerHeight + (CGFloat(rowCount) * layout.rowHeight)
    }
}

private struct IdeaRowView: View {
    @ObservedObject var store: DashboardStore
    let project: String
    let index: Int
    let idea: Idea
    let allProjects: [String]
    let layout: TableLayout

    @State private var showingDetails = false

    var body: some View {
        HStack(spacing: 0) {
            controls
            editableCell(text: binding(for: .name), width: layout.nameWidth)
            editableCell(text: binding(for: .humanIdea), width: layout.humanWidth)

            if !layout.isCompact {
                editableCell(text: binding(for: .description), width: layout.descriptionWidth)
                editableCell(
                    text: Binding(
                        get: { store.relatedText(project: project, index: index) },
                        set: { store.updateRelated(project: project, index: index, value: $0) }
                    ),
                    width: layout.relatedWidth
                )
                editableCell(text: binding(for: .difficulty), width: layout.difficultyWidth)
            }

            priorityCell
        }
        .frame(height: layout.rowHeight)
        .background(priorityBackground(priority: idea.priority))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(height: 1)
        }
        .sheet(isPresented: $showingDetails) {
            IdeaDetailsSheet(store: store, project: project, index: index)
        }
    }

    private var controls: some View {
        Menu {
            Button("Edit details") {
                showingDetails = true
            }

            Divider()

            Button("Move up") {
                store.moveIdeaUp(project: project, index: index)
            }
            Button("Move down") {
                store.moveIdeaDown(project: project, index: index)
            }

            Menu("Move to project") {
                ForEach(allProjects.filter { $0 != project }, id: \.self) { otherProject in
                    Button(otherProject) {
                        store.moveIdea(project: project, index: index, to: otherProject)
                    }
                }
            }

            Divider()

            Button("Complete") {
                store.completeIdea(project: project, index: index)
            }

            Button("Delete", role: .destructive) {
                store.deleteIdea(project: project, index: index)
            }
        } label: {
            Text("☰")
                .font(.system(size: 12, design: .monospaced))
                .frame(width: layout.controlWidth, height: layout.rowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(width: 1)
        }
    }

    private var priorityCell: some View {
        Menu {
            ForEach(PriorityOption.allCases, id: \.rawValue) { priority in
                Button {
                    store.updatePriority(project: project, index: index, value: priority.rawValue)
                } label: {
                    Label(priority.rawValue, systemImage: prioritySymbol(priority.rawValue))
                }
            }
        } label: {
            Image(systemName: prioritySymbol(idea.priority))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(priorityColor(idea.priority))
                .frame(width: layout.priorityWidth, height: layout.rowHeight)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(width: 1)
        }
    }

    private func editableCell(text: Binding<String>, width: CGFloat) -> some View {
        TextField("", text: text)
            .font(.system(size: 10.5, design: .monospaced))
            .textFieldStyle(.plain)
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color.black.opacity(0.08))
                    .frame(width: 1)
            }
    }

    private func binding(for field: IdeaTextField) -> Binding<String> {
        Binding(
            get: { store.ideaField(project: project, index: index, field: field) },
            set: { store.updateTextField(project: project, index: index, field: field, value: $0) }
        )
    }

    private func priorityBackground(priority: String) -> Color {
        switch priority {
        case PriorityOption.high.rawValue:
            return Color(red: 0.93, green: 0.91, blue: 0.99)
        case PriorityOption.medium.rawValue:
            return Color(red: 0.88, green: 0.95, blue: 0.99)
        case PriorityOption.low.rawValue:
            return Color(red: 0.99, green: 0.98, blue: 0.86)
        default:
            return Color.clear
        }
    }

    private func prioritySymbol(_ priority: String) -> String {
        switch priority {
        case PriorityOption.high.rawValue:
            return "exclamationmark.circle.fill"
        case PriorityOption.medium.rawValue:
            return "circle.fill"
        case PriorityOption.low.rawValue:
            return "minus.circle.fill"
        default:
            return "circle"
        }
    }

    private func priorityColor(_ priority: String) -> Color {
        switch priority {
        case PriorityOption.high.rawValue:
            return Color(red: 0.50, green: 0.28, blue: 0.86)
        case PriorityOption.medium.rawValue:
            return Color(red: 0.03, green: 0.52, blue: 0.78)
        case PriorityOption.low.rawValue:
            return Color(red: 0.66, green: 0.45, blue: 0.03)
        default:
            return .secondary
        }
    }
}

private struct IdeaDetailsSheet: View {
    @ObservedObject var store: DashboardStore
    let project: String
    let index: Int

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Idea") {
                    TextField("name", text: binding(for: .name))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("human_idea", text: binding(for: .humanIdea), axis: .vertical)
                        .lineLimit(3...6)
                    TextField("description", text: binding(for: .description), axis: .vertical)
                        .lineLimit(3...6)
                    TextField("difficulty", text: binding(for: .difficulty))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField(
                        "related",
                        text: Binding(
                            get: { store.relatedText(project: project, index: index) },
                            set: { store.updateRelated(project: project, index: index, value: $0) }
                        ),
                        axis: .vertical
                    )
                    .lineLimit(2...4)
                }

                Section("Priority") {
                    Picker("Priority", selection: Binding(
                        get: { store.priority(project: project, index: index) },
                        set: { store.updatePriority(project: project, index: index, value: $0) }
                    )) {
                        ForEach(PriorityOption.allCases, id: \.rawValue) { priority in
                            Text(priority.rawValue).tag(priority.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Edit Idea")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func binding(for field: IdeaTextField) -> Binding<String> {
        Binding(
            get: { store.ideaField(project: project, index: index, field: field) },
            set: { store.updateTextField(project: project, index: index, field: field, value: $0) }
        )
    }
}
