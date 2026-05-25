import SwiftUI

struct SyncSheet: View {
    @ObservedObject var store: DashboardStore
    @Environment(\.dismiss) private var dismiss
    @State private var isTokenVisible = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Repository") {
                    TextField("Server URL", text: $store.syncConfiguration.serverURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Store ID", text: $store.syncConfiguration.storeID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    bearerTokenEditor
                }

                Section("Sync") {
                    Button {
                        Task { await store.syncWithServer() }
                    } label: {
                        Label("Sync now", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                    }
                    .disabled(store.isSyncing)
                }

                Section("Status") {
                    if let message = store.syncStatusMessage {
                        Text(message)
                            .font(.system(size: 12, design: .monospaced))
                    } else {
                        Text("No sync activity yet.")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    if let lastAction = store.syncMetadata.lastAction,
                       let lastDate = store.syncMetadata.lastSyncDate {
                        Text("\(lastAction) on \(lastDate.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    if let revision = store.syncMetadata.lastServerRevision {
                        Text("revision \(revision)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .navigationTitle("Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .overlay {
                if store.isSyncing {
                    ProgressView("Syncing...")
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(uiColor: .systemBackground))
                        )
                }
            }
        }
    }

    private var bearerTokenEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Group {
                    if isTokenVisible {
                        TextField("Bearer token", text: $store.serverToken)
                    } else {
                        SecureField("Bearer token", text: $store.serverToken)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                Button {
                    isTokenVisible.toggle()
                } label: {
                    Image(systemName: isTokenVisible ? "eye.slash" : "eye")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isTokenVisible ? "Hide bearer token" : "Show bearer token")
            }

            HStack(spacing: 10) {
                PasteButton(payloadType: String.self) { strings in
                    guard let token = strings.first else { return }
                    store.serverToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
                }

                Text("Copy on your Mac, then paste here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
