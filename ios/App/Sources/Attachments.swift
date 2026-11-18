import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Attachments of a task or chore: add photos or files, open them, delete them (the web app's attachment row).
struct AttachmentsSection: View {
    @EnvironmentObject private var home: HomeStore
    @Environment(\.openURL) private var openURL
    var taskID: String? = nil
    var choreID: String? = nil
    @State private var photo: PhotosPickerItem?
    @State private var importing = false
    @State private var busy = false
    var body: some View {
        Section("קבצים מצורפים") {
            ForEach(home.attachments(task: taskID, chore: choreID)) { item in
                HStack(spacing: 12) {
                    Image(systemName: icon(item.kind)).font(.title3).foregroundStyle(Color.wellnessSecondary).frame(width: 40, height: 40).background(Color.wellnessChip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.fileName).font(.hb(.body)).foregroundStyle(Color.wellnessInk).lineLimit(1)
                        if item.size > 0 { Text(ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file)).font(.hb(.caption)).foregroundStyle(Color.wellnessSecondary) }
                    }
                    Spacer(minLength: 8)
                    Button { Task { if let url = await home.url(for: item) { openURL(url) } } } label: { Image(systemName: "arrow.up.right.square").frame(width: 44, height: 44) }.buttonStyle(.plain).accessibilityLabel("פתיחת \(item.fileName)")
                }
                .swipeActions { Button(role: .destructive) { Task { await home.delete(item) } } label: { Label("מחיקה", systemImage: "trash") } }
            }
            HStack(spacing: 18) {
                PhotosPicker(selection: $photo, matching: .images) { Label("תמונה", systemImage: "photo") }.accessibilityIdentifier("attachment-photo")
                Button { importing = true } label: { Label("קובץ", systemImage: "paperclip") }.buttonStyle(.plain).accessibilityIdentifier("attachment-file")
                if busy { ProgressView() }
            }.font(.hb(.subheadline, .semibold)).frame(minHeight: 44)
        }
        .onChange(of: photo) { _, item in Task { await addPhoto(item) } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { result in Task { await addFile(result) } }
    }
    private func icon(_ kind: String) -> String { switch kind { case "image": "photo"; case "pdf": "doc.richtext"; case "audio": "waveform"; case "video": "film"; default: "doc" } }
    private func addPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        busy = true; defer { busy = false; photo = nil }
        let jpeg = image.jpegData(compressionQuality: 0.85) ?? data
        await home.addAttachment(data: jpeg, fileName: "photo-\(Int(Date().timeIntervalSince1970)).jpg", mimeType: "image/jpeg", taskID: taskID, choreID: choreID)
    }
    private func addFile(_ result: Result<URL, Error>) async {
        guard case .success(let url) = result else { return }
        busy = true; defer { busy = false }
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        await home.addAttachment(data: data, fileName: url.lastPathComponent, mimeType: mime, taskID: taskID, choreID: choreID)
    }
}
