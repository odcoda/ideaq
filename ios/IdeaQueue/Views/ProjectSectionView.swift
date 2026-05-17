import Foundation
import SwiftUI

struct ProjectSectionView: View {
    @ObservedObject var store: DashboardStore
    let project: String
    let isLandscape: Bool

    @State private var isHeaderDropTarget = false

    var body: some View {
        VStack(spacing: 5) {
            header

            if !store.collapsedProjects.contains(project) {
                GeometryReader { proxy in
                    let layout = TableLayout(availableWidth: proxy.size.width, isLandscape: isLandscape)
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
                    rowCount: store.visibleIdeas(in: project).count,
                    isLandscape: isLandscape
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
            .dropDestination(for: String.self) { items, _ in
                receiveDraggedIdeas(items, at: store.ideaCount(in: project))
            } isTargeted: { isTargeted in
                isHeaderDropTarget = isTargeted
            }
            .background(isHeaderDropTarget ? Color.accentColor.opacity(0.12) : Color.clear)

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

            if layout.showsLandscapeColumns {
                headerCell("description", width: layout.descriptionWidth)
                headerCell("size", width: layout.sizeWidth)
            }

            headerCell("priority", width: layout.priorityWidth)
        }
        .frame(height: layout.headerHeight)
    }

    private func headerCell(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .font(.system(size: 9.5, design: .monospaced))
            .fontWeight(.semibold)
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
            .frame(width: width, alignment: .leading)
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

    private func receiveDraggedIdeas(_ items: [String], at targetIndex: Int) -> Bool {
        guard let payload = items.compactMap(IdeaDragPayload.init).first else { return false }
        let adjustedIndex = adjustedTargetIndex(for: payload, targetIndex: targetIndex)
        guard payload.project != project || payload.index != adjustedIndex else { return false }
        store.moveIdea(
            fromProject: payload.project,
            fromIndex: payload.index,
            toProject: project,
            toIndex: adjustedIndex
        )
        return true
    }

    private func adjustedTargetIndex(for payload: IdeaDragPayload, targetIndex: Int) -> Int {
        if payload.project == project, payload.index < targetIndex {
            return max(targetIndex - 1, 0)
        }
        return targetIndex
    }
}

private struct TableLayout {
    let availableWidth: CGFloat
    let isLandscape: Bool

    var showsLandscapeColumns: Bool { isLandscape }
    var controlWidth: CGFloat { 24 }
    var priorityWidth: CGFloat { 62 }
    var sizeWidth: CGFloat { showsLandscapeColumns ? 38 : 0 }
    var headerHeight: CGFloat { 20 }
    var rowHeight: CGFloat { 30 }

    var contentWidth: CGFloat {
        max(availableWidth - controlWidth - priorityWidth - sizeWidth, 160)
    }

    var nameWidth: CGFloat {
        floor(contentWidth * (showsLandscapeColumns ? 0.18 : 0.34))
    }

    var humanWidth: CGFloat {
        if showsLandscapeColumns {
            return floor(contentWidth * 0.34)
        }
        return contentWidth - nameWidth
    }

    var descriptionWidth: CGFloat {
        guard showsLandscapeColumns else { return 0 }
        return max(contentWidth - nameWidth - humanWidth, 120)
    }

    static func heightForProject(rowCount: Int, isLandscape: Bool) -> CGFloat {
        let layout = TableLayout(availableWidth: 0, isLandscape: isLandscape)
        return layout.headerHeight + (CGFloat(rowCount) * layout.rowHeight)
    }
}

private struct IdeaDragPayload: Codable {
    let project: String
    let index: Int

    private static let prefix = "ideaq-idea:"

    var encoded: String {
        guard
            let data = try? JSONEncoder().encode(self),
            let json = String(data: data, encoding: .utf8)
        else {
            return ""
        }
        return Self.prefix + json
    }

    init(project: String, index: Int) {
        self.project = project
        self.index = index
    }

    init?(_ rawValue: String) {
        guard rawValue.hasPrefix(Self.prefix) else { return nil }
        let json = String(rawValue.dropFirst(Self.prefix.count))
        guard
            let data = json.data(using: .utf8),
            let payload = try? JSONDecoder().decode(Self.self, from: data)
        else {
            return nil
        }
        self = payload
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
    @State private var isDropTarget = false

    var body: some View {
        HStack(spacing: 0) {
            controls
            ReadOnlyTextCell(
                text: idea.name,
                width: layout.nameWidth,
                height: layout.rowHeight,
                showsFullText: false
            )
            ReadOnlyTextCell(
                text: idea.humanIdea,
                width: layout.humanWidth,
                height: layout.rowHeight,
                showsFullText: true
            )

            if layout.showsLandscapeColumns {
                ReadOnlyTextCell(
                    text: idea.description,
                    width: layout.descriptionWidth,
                    height: layout.rowHeight,
                    showsFullText: true
                )
                sizeCell
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
        .overlay(alignment: .top) {
            if isDropTarget {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
            }
        }
        .dropDestination(for: String.self) { items, _ in
            receiveDraggedIdeas(items)
        } isTargeted: { isTargeted in
            isDropTarget = isTargeted
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

            if allProjects.contains(where: { $0 != project }) {
                Menu("Move to project") {
                    ForEach(allProjects.filter { $0 != project }, id: \.self) { otherProject in
                        Button(otherProject) {
                            store.moveIdea(project: project, index: index, to: otherProject)
                        }
                    }
                }

                Divider()
            }

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
        .draggable(IdeaDragPayload(project: project, index: index).encoded) {
            Text(idea.name.isEmpty ? "idea" : idea.name)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(uiColor: .systemBackground))
                        .shadow(radius: 3)
                )
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(width: 1)
        }
    }

    private var sizeCell: some View {
        Menu {
            ForEach(SizeOption.allCases, id: \.rawValue) { size in
                Button(size.rawValue) {
                    store.updateSize(project: project, index: index, value: size.rawValue)
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(idea.difficulty.isEmpty ? SizeOption.small.rawValue : idea.difficulty)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.primary)
            .frame(width: layout.sizeWidth, height: layout.rowHeight)
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
            HStack(spacing: 3) {
                Image(systemName: prioritySymbol(idea.priority))
                    .font(.system(size: 9, weight: .semibold))
                Text(priorityText)
                    .font(.system(size: 10, design: .monospaced))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(priorityColor(idea.priority))
            .frame(width: layout.priorityWidth, height: layout.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(width: 1)
        }
    }

    private var priorityText: String {
        idea.priority.isEmpty ? PriorityOption.none.rawValue : idea.priority
    }

    private func receiveDraggedIdeas(_ items: [String]) -> Bool {
        guard let payload = items.compactMap(IdeaDragPayload.init).first else { return false }
        let adjustedIndex = adjustedTargetIndex(for: payload)
        guard payload.project != project || payload.index != adjustedIndex else { return false }
        store.moveIdea(
            fromProject: payload.project,
            fromIndex: payload.index,
            toProject: project,
            toIndex: adjustedIndex
        )
        return true
    }

    private func adjustedTargetIndex(for payload: IdeaDragPayload) -> Int {
        if payload.project == project, payload.index < index {
            return max(index - 1, 0)
        }
        return index
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

private struct ReadOnlyTextCell: View {
    let text: String
    let width: CGFloat
    let height: CGFloat
    let showsFullText: Bool

    @State private var showingFullText = false

    var body: some View {
        Text(text.isEmpty ? " " : text)
            .font(.system(size: 10, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .frame(width: width, height: height, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                guard showsFullText, !text.isEmpty else { return }
                showingFullText = true
            }
            .help(showsFullText ? text : "")
            .popover(isPresented: $showingFullText, arrowEdge: .top) {
                ScrollView {
                    Text(text)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(minWidth: 240, maxWidth: 340, maxHeight: 240)
                .presentationCompactAdaptation(.popover)
            }
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color.black.opacity(0.08))
                    .frame(width: 1)
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

                Section("Size") {
                    Picker("Size", selection: Binding(
                        get: { store.ideaField(project: project, index: index, field: .difficulty) },
                        set: { store.updateSize(project: project, index: index, value: $0) }
                    )) {
                        ForEach(SizeOption.allCases, id: \.rawValue) { size in
                            Text(size.rawValue).tag(size.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
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
