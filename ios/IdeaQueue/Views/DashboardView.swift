import SwiftUI

struct DashboardView: View {
    @ObservedObject var store: DashboardStore

    @State private var showingAddProject = false
    @State private var newProjectName = ""
    @State private var showingSyncSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                toolbar
                filterBar
                content
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .navigationTitle("Idea Queue")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingSyncSheet) {
                SyncSheet(store: store)
            }
            .alert("New Project", isPresented: $showingAddProject) {
                TextField("project_name", text: $newProjectName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Cancel", role: .cancel) {
                    newProjectName = ""
                }
                Button("Add") {
                    store.addProject(named: newProjectName)
                    newProjectName = ""
                }
            } message: {
                Text("Create a new queue JSON file.")
            }
            .overlay(alignment: .bottom) {
                if let pendingDelete = store.pendingDelete {
                    undoToast(name: pendingDelete.idea.name)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    private var toolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                actionButton("sync") {
                    showingSyncSheet = true
                }
                actionButton("+ project") {
                    showingAddProject = true
                }
                actionButton("sort all") {
                    store.sortAllByPriority()
                }
                actionButton(collapseToggleTitle) {
                    if allProjectsCollapsed {
                        store.expandAll()
                    } else {
                        store.collapseAll()
                    }
                }
            }
            .font(.system(size: 12, design: .monospaced))
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("filter")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)

                ForEach(PriorityOption.allCases, id: \.rawValue) { priority in
                    Button(priority.rawValue) {
                        store.togglePriority(priority.rawValue)
                    }
                    .font(.system(size: 12, design: .monospaced))
                    .buttonStyle(.borderedProminent)
                    .tint(store.enabledPriorities.contains(priority.rawValue) ? tintColor(for: priority.rawValue) : .gray.opacity(0.4))
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        GeometryReader { proxy in
            if store.orderedProjects.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Text("No local queue files yet.")
                    Text("Use sync to fetch server data or start by adding a project.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .font(.system(size: 13, design: .monospaced))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let isLandscape = proxy.size.width > proxy.size.height

                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(store.orderedProjects, id: \.self) { project in
                            ProjectSectionView(
                                store: store,
                                project: project,
                                isLandscape: isLandscape
                            )
                        }
                    }
                    .padding(.bottom, 48)
                }
            }
        }
    }

    private var allProjectsCollapsed: Bool {
        let projects = store.orderedProjects
        return !projects.isEmpty && projects.allSatisfy { store.collapsedProjects.contains($0) }
    }

    private var collapseToggleTitle: String {
        allProjectsCollapsed ? "expand all" : "collapse all"
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
    }

    private func undoToast(name: String) -> some View {
        HStack(spacing: 10) {
            Text("deleted \"\(name)\"")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white)
            Button("undo") {
                store.undoDelete()
            }
            .font(.system(size: 12, design: .monospaced))
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.82))
        )
    }

    private func tintColor(for priority: String) -> Color {
        switch priority {
        case PriorityOption.high.rawValue:
            return Color(red: 0.50, green: 0.28, blue: 0.86)
        case PriorityOption.medium.rawValue:
            return Color(red: 0.03, green: 0.52, blue: 0.78)
        case PriorityOption.low.rawValue:
            return Color(red: 0.66, green: 0.45, blue: 0.03)
        default:
            return .gray
        }
    }
}
