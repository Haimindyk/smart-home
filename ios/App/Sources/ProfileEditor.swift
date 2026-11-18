import SwiftUI
import PhotosUI

/// "My profile": name, emoji, color and an optional photo (the web app's profile dialog).
struct ProfileEditorSheet: View {
    @EnvironmentObject private var home: HomeStore
    @Environment(\.dismiss) private var dismiss
    private static let emojis = ["🙂", "🧑", "👤", "🧔", "👩", "🧑‍🦱", "🧑‍🦰", "👨", "🐶", "💙"]
    private static let colors = ["#6366f1", "#3b82f6", "#0ea5e9", "#10b981", "#f59e0b", "#ec4899", "#a855f7", "#ef4444"]
    @State private var name = ""
    @State private var emoji = "🙂"
    @State private var color = "#6366f1"
    @State private var photo: PhotosPickerItem?
    @State private var photoJPEG: Data?
    @State private var removePhoto = false
    @State private var saving = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        preview
                        VStack(alignment: .leading, spacing: 8) {
                            PhotosPicker(selection: $photo, matching: .images) { Label(hasPhoto ? "החלפת תמונה" : "הוספת תמונה", systemImage: "camera") }.accessibilityIdentifier("profile-photo")
                            if hasPhoto { Button(role: .destructive) { photoJPEG = nil; removePhoto = true; photo = nil } label: { Label("הסרת תמונה", systemImage: "trash") } }
                        }.font(.hb(.subheadline, .semibold))
                    }.padding(.vertical, 4)
                }
                Section("שם") { TextField("השם שלך", text: $name).accessibilityIdentifier("profile-name") }
                Section("אימוג׳י") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                        ForEach(Self.emojis, id: \.self) { e in
                            Button { emoji = e } label: { Text(e).font(.system(size: 26)).frame(maxWidth: .infinity, minHeight: 48).background(emoji == e ? Color.wellnessChip : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(emoji == e ? Color.wellnessInk : Color.wellnessHairline, lineWidth: emoji == e ? 2 : 1)) }.buttonStyle(.plain)
                        }
                    }.padding(.vertical, 4)
                }
                Section("צבע") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                        ForEach(Self.colors, id: \.self) { c in
                            Button { color = c } label: { Circle().fill(Color(hex: c)).frame(height: 32).overlay(Circle().strokeBorder(Color.wellnessInk, lineWidth: color == c ? 3 : 0).padding(-3)) }.buttonStyle(.plain).accessibilityLabel("צבע").accessibilityAddTraits(color == c ? [.isSelected] : [])
                        }
                    }.padding(.vertical, 6)
                }
            }
            .wellnessList().navigationTitle("הפרופיל שלי").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ביטול") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("שמירה") { Task { saving = true; if await home.saveProfile(name: name, emoji: emoji, color: color, photoJPEG: photoJPEG, removePhoto: removePhoto) { dismiss() }; saving = false } }.disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty).accessibilityIdentifier("profile-save") }
            }
            .onAppear { if let me = home.me { name = me.name; emoji = me.emoji ?? "🙂"; color = me.color.count == 7 ? me.color : "#6366f1" } }
            .onChange(of: photo) { _, item in Task { await load(item) } }
        }
    }
    private var hasPhoto: Bool { photoJPEG != nil || (!removePhoto && home.me?.photoURL != nil) }
    private var preview: some View {
        ZStack {
            if let jpeg = photoJPEG, let image = UIImage(data: jpeg) { Image(uiImage: image).resizable().scaledToFill().frame(width: 76, height: 76).clipShape(Circle()) }
            else { MemberAvatar(member: previewMember, size: 76) }
        }.overlay(Circle().strokeBorder(Color(hex: color).opacity(0.6), lineWidth: 2).frame(width: 76, height: 76))
    }
    private var previewMember: HMember? {
        guard let me = home.me else { return nil }
        var m = me; m.name = name; m.emoji = emoji; m.color = color; if removePhoto { m.photoURL = nil }; return m
    }
    /// Center-crops to a square and downsizes so the upload stays small (the web app crops to a square as well).
    private func load(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        let side = min(image.size.width, image.size.height), target: CGFloat = 512
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: target, height: target))
        let cropped = renderer.image { _ in
            let scale = target / side
            image.draw(in: CGRect(x: -(image.size.width - side) / 2 * scale, y: -(image.size.height - side) / 2 * scale, width: image.size.width * scale, height: image.size.height * scale))
        }
        var quality = 0.85, jpeg = cropped.jpegData(compressionQuality: quality)
        while let current = jpeg, current.count > 1_500_000, quality > 0.3 { quality -= 0.15; jpeg = cropped.jpegData(compressionQuality: quality) }
        photoJPEG = jpeg; removePhoto = false
    }
}
