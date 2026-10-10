import SwiftUI
import TruthLensCore

struct HistoryView: View {
    @Environment(AppModel.self) private var app

    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All", scans = "AI Scans", facts = "Fact Checks"
        var id: String { rawValue }
    }

    private enum Confirm: Identifiable {
        case clearUnprotected, clearEverything, deleteSelection, deleteProtected(UUID)
        var id: String {
            switch self {
            case .clearUnprotected: "clear"
            case .clearEverything: "everything"
            case .deleteSelection: "selection"
            case .deleteProtected(let id): "protected-\(id)"
            }
        }
    }

    @State private var filter: Filter = .all
    @State private var search = ""
    @State private var selecting = false
    @State private var selection = Set<UUID>()
    @State private var confirm: Confirm?
    @State private var notice: String?

    private var history: HistoryModel { app.history }

    private var visible: [HistoryEntry] {
        history.entries.filter { e in
            switch filter {
            case .all: true
            case .scans: e.kind == .scan
            case .facts: e.kind == .factCheck
            }
        }
        .filter { search.isEmpty || $0.searchText.contains(search.lowercased()) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    StorageCard(history: history,
                                onClear: { confirm = .clearUnprotected },
                                onClearEverything: { confirm = .clearEverything })
                    if let notice {
                        Label(notice, systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !history.entries.isEmpty {
                        Picker("Show", selection: $filter) {
                            ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    if history.entries.isEmpty {
                        emptyState(icon: "clock.arrow.circlepath", title: "Nothing here yet",
                                   detail: "AI scans and fact checks you run are saved here so you can review them later.")
                    } else if visible.isEmpty {
                        emptyState(icon: "magnifyingglass", title: "No matches",
                                   detail: "Try a different filter or search.")
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(visible) { entry in
                                HistoryRow(entry: entry, selecting: selecting,
                                           selected: selection.contains(entry.id),
                                           onTap: { tapped(entry) },
                                           onToggleProtect: { history.setProtected([entry.id], !entry.protected) },
                                           onDelete: { delete(entry) })
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .padding(.bottom, selecting ? 80 : 0)
            }
            .background(Background())
            .navigationTitle("History")
            .searchable(text: $search, prompt: "Search claims and results")
            .toolbar {
                if !history.entries.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button(selecting ? "Done" : "Select") { setSelecting(!selecting) }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { if selecting { selectionBar } }
        }
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                            titleVisibility: .visible, presenting: confirm) { action in
            Button(confirmButton(action), role: .destructive) { perform(action) }
            Button("Cancel", role: .cancel) {}
        } message: { action in
            Text(confirmMessage(action))
        }
    }

    // MARK: Selection bar

    private var selectionBar: some View {
        let chosen = history.entries.filter { selection.contains($0.id) }
        let allProtected = !chosen.isEmpty && chosen.allSatisfy(\.protected)
        let deletable = HistoryPolicy.split(selection: selection, in: history.entries).deletable.count
        return HStack(spacing: 10) {
            Button(selection.count == visible.count ? "Select none" : "Select all") {
                selection = selection.count == visible.count ? [] : Set(visible.map(\.id))
            }
            Spacer()
            Button(allProtected ? "Unprotect" : "Protect", systemImage: allProtected ? "lock.open" : "lock") {
                history.setProtected(selection, !allProtected)
            }
            .disabled(selection.isEmpty)
            Button("Delete \(deletable)", systemImage: "trash", role: .destructive) { confirm = .deleteSelection }
                .disabled(deletable == 0)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .padding(12)
        .background(.bar)
    }

    // MARK: Actions

    private func setSelecting(_ on: Bool) {
        selecting = on
        selection = []
        notice = nil
    }

    private func tapped(_ entry: HistoryEntry) {
        if selecting {
            if selection.contains(entry.id) { selection.remove(entry.id) } else { selection.insert(entry.id) }
        } else {
            app.open(entry)
        }
    }

    private func delete(_ entry: HistoryEntry) {
        if entry.protected { confirm = .deleteProtected(entry.id) } else { history.delete([entry.id]) }
    }

    private func perform(_ action: Confirm) {
        switch action {
        case .clearUnprotected:
            let kept = history.protectedCount
            history.clearUnprotected()
            notice = kept > 0 ? "Cleared. \(kept) protected item\(kept == 1 ? " was" : "s were") kept." : nil
        case .clearEverything:
            history.clearAll()
            notice = nil
        case .deleteSelection:
            let kept = history.deleteSelection(selection)
            setSelecting(false)
            notice = kept > 0 ? "\(kept) protected item\(kept == 1 ? " was" : "s were") kept. Unprotect to delete." : nil
        case .deleteProtected(let id):
            history.delete([id])
        }
    }

    // MARK: Confirmation text

    private var confirmTitle: String {
        switch confirm {
        case .clearUnprotected: "Clear history?"
        case .clearEverything: "Delete everything?"
        case .deleteSelection: "Delete selected items?"
        case .deleteProtected: "Delete protected item?"
        case nil: ""
        }
    }

    private func confirmButton(_ action: Confirm) -> String {
        switch action {
        case .clearUnprotected: "Delete \(history.clearable.count) unprotected item\(history.clearable.count == 1 ? "" : "s")"
        case .clearEverything: "Delete all \(history.entries.count) items, including protected"
        case .deleteSelection:
            "Delete \(HistoryPolicy.split(selection: selection, in: history.entries).deletable.count) item(s)"
        case .deleteProtected: "Delete anyway"
        }
    }

    private func confirmMessage(_ action: Confirm) -> String {
        switch action {
        case .clearUnprotected:
            "Frees about \(HistoryModel.format(bytes: history.clearableBytes)). \(history.protectedCount) protected item(s) will be kept. This can't be undone."
        case .clearEverything:
            "This permanently deletes every saved scan and fact check, including \(history.protectedCount) protected item(s). This can't be undone."
        case .deleteSelection:
            "Protected items in your selection will be kept. This can't be undone."
        case .deleteProtected:
            "This item is protected. Deleting it can't be undone."
        }
    }

    private func emptyState(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 40, weight: .light)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Storage

struct StorageCard: View {
    let history: HistoryModel
    let onClear: () -> Void
    let onClearEverything: () -> Void
    @AppStorage("saveHistory") private var saveHistory = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Storage used", systemImage: "internaldrive").font(.headline)
                Spacer()
                Text(HistoryModel.format(bytes: history.totalBytes))
                    .font(.title3.bold().monospacedDigit())
                    .accessibilityLabel("History is using \(HistoryModel.format(bytes: history.totalBytes))")
            }
            Text("\(history.entries.count) item\(history.entries.count == 1 ? "" : "s") · \(history.protectedCount) protected")
                .font(.subheadline).foregroundStyle(.secondary)

            Toggle("Save new scans and checks", isOn: $saveHistory)

            HStack(spacing: 10) {
                Button(role: .destructive, action: onClear) {
                    Label("Clear history", systemImage: "trash").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).controlSize(.large)
                .disabled(history.clearable.isEmpty)
                Menu {
                    Button("Delete everything, including protected…", role: .destructive, action: onClearEverything)
                } label: {
                    Label("More", systemImage: "ellipsis.circle").labelStyle(.iconOnly).font(.title2)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .menuStyle(.borderlessButton).fixedSize()
                .disabled(history.entries.isEmpty)
                .accessibilityLabel("More clear options")
            }
            Text("Saved only on this device, with reduced-quality images. Protected items are kept when you clear history.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .card()
    }
}

// MARK: - Row

struct HistoryRow: View {
    @Environment(AppModel.self) private var app
    let entry: HistoryEntry
    let selecting: Bool
    let selected: Bool
    let onTap: () -> Void
    let onToggleProtect: () -> Void
    let onDelete: () -> Void

    private var tint: Color {
        switch entry.kind {
        case .scan: entry.scan?.report.tint ?? .gray
        case .factCheck: entry.fact?.report.rating.color ?? .gray
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    if selecting {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.title2).foregroundStyle(selected ? Color.accentColor : .secondary)
                            .accessibilityHidden(true)
                    }
                    HistoryThumb(entry: entry)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: entry.kind == .scan ? "sparkle.magnifyingglass" : "checkmark.seal")
                            Text(entry.kind == .scan ? "AI Scan" : "Fact Check")
                            Text("·")
                            Text(entry.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                            if entry.protected {
                                Image(systemName: "lock.fill").accessibilityLabel("Protected")
                            }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        Text(entry.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(entry.badge).font(.caption.bold()).foregroundStyle(tint)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(tint.opacity(0.15), in: Capsule())
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? .isSelected : [])

            if !selecting {
                Menu {
                    Button("Open", systemImage: "arrow.up.right.square", action: onTap)
                    Button(entry.protected ? "Unprotect" : "Protect", systemImage: entry.protected ? "lock.open" : "lock",
                           action: onToggleProtect)
                    Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3).frame(minWidth: 44, minHeight: 44)
                }
                .menuStyle(.borderlessButton).fixedSize()
                .accessibilityLabel("Actions for \(entry.title)")
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
        )
        .contextMenu {
            Button(entry.protected ? "Unprotect" : "Protect", systemImage: entry.protected ? "lock.open" : "lock",
                   action: onToggleProtect)
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }
}

struct HistoryThumb: View {
    @Environment(AppModel.self) private var app
    let entry: HistoryEntry
    @State private var data: Data?

    var body: some View {
        Group {
            if let data, let image = Image(data: data) {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: entry.scan?.mediaKind == .audio ? "waveform"
                          : entry.kind == .factCheck ? "text.quote" : "photo")
                        .font(.title3).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
        .task(id: entry.id) { data = entry.hasThumbnail ? app.history.thumbnail(for: entry.id) : nil }
    }
}
