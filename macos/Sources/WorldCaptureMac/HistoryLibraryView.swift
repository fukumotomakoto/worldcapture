import AppKit
import SwiftUI

/// 历史库窗口：以缩略图网格浏览全部已保存的截图与录像，可重新打开、在 Finder 中定位、移到废纸篓或从历史移除。
struct HistoryLibraryView: View {
    @ObservedObject var store: HistoryStore
    @State private var filter: HistoryFilter = .all
    @State private var confirmClear = false

    enum HistoryFilter: String, CaseIterable {
        case all, image, video
        var labelKey: String {
            switch self {
            case .all: return "library.filter.all"
            case .image: return "library.filter.image"
            case .video: return "library.filter.video"
            }
        }
    }

    private var visibleEntries: [HistoryEntry] {
        switch filter {
        case .all: return store.entries
        case .image: return store.entries.filter { $0.kind == .image }
        case .video: return store.entries.filter { $0.kind == .video }
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if visibleEntries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(visibleEntries) { entry in
                            HistoryCell(entry: entry, store: store)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(minWidth: 640, minHeight: 460)
        .onAppear { store.pruneMissing() }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text(Loc.s("library.title")).font(.headline)
            Text(Loc.s("library.count", visibleEntries.count))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Picker("", selection: $filter) {
                ForEach(HistoryFilter.allCases, id: \.self) { f in
                    Text(Loc.s(f.labelKey)).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            Button(role: .destructive) {
                confirmClear = true
            } label: {
                Label(Loc.s("library.clear"), systemImage: "trash")
            }
            .disabled(store.entries.isEmpty)
            .confirmationDialog(Loc.s("library.clear.confirm"), isPresented: $confirmClear) {
                Button(Loc.s("library.clear"), role: .destructive) { store.clearAll() }
                Button(Loc.s("action.close"), role: .cancel) {}
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(Loc.s("library.empty")).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 单个历史项卡片：缩略图 + 文件名 + 时间；点按打开，悬停露出定位/删除按钮，右键提供完整操作。
private struct HistoryCell: View {
    let entry: HistoryEntry
    @ObservedObject var store: HistoryStore

    @State private var thumbnail: NSImage?
    @State private var loaded = false
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            thumbnailArea
            Text(entry.fileName)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .opacity(entry.exists ? 1 : 0.5)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { open() }
        .contextMenu { contextMenu }
        .help(entry.exists ? entry.fileName : Loc.s("library.missing"))
        .task(id: entry.id) { await loadThumbnail() }
    }

    private var thumbnailArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor))
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            } else if loaded {
                Image(systemName: entry.exists ? "photo" : "questionmark.square.dashed")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
            if entry.kind == .video {
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white, .black.opacity(0.55))
            }
        }
        .frame(height: 150)
        .overlay(alignment: .topTrailing) {
            if hovering && entry.exists {
                HStack(spacing: 4) {
                    iconButton("doc.on.doc", Loc.s("library.copy")) { copyOriginal() }
                    iconButton("folder", Loc.s("reveal.finder")) { reveal() }
                    iconButton("trash", Loc.s("library.trash")) { store.moveToTrash(entry) }
                }
                .padding(6)
            }
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button(Loc.s("library.open.file")) { open() }.disabled(!entry.exists)
        Button(Loc.s("library.copy")) { copyOriginal() }.disabled(!entry.exists)
        Button(Loc.s("reveal.finder")) { reveal() }.disabled(!entry.exists)
        Divider()
        Button(Loc.s("library.trash"), role: .destructive) { store.moveToTrash(entry) }
            .disabled(!entry.exists)
        Button(Loc.s("library.removeEntry")) { store.remove(entry) }
    }

    private func iconButton(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .padding(5)
                .background(.thinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func open() {
        guard entry.exists else { return }
        NSWorkspace.shared.open(entry.url)
    }

    private func reveal() {
        NSWorkspace.shared.activateFileViewerSelecting([entry.url])
    }

    /// 复制原始文件（非缩略图）：图片放入原图位图 + 文件引用，视频放入文件引用。
    private func copyOriginal() {
        guard entry.exists else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        var objects: [NSPasteboardWriting] = [entry.url as NSURL]
        if entry.kind == .image, let original = NSImage(contentsOf: entry.url) {
            objects.append(original)
        }
        pasteboard.writeObjects(objects)
    }

    private func loadThumbnail() async {
        thumbnail = await store.thumbnail(for: entry)
        loaded = true
    }
}
