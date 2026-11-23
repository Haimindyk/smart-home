import SwiftUI
import PhotosUI
import WellnessCore

/// Photo -> AI estimate -> review quantities -> save. Gated exactly like the web app (adult + explicit consent).
struct AIMealSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let onSaved: () -> Void
    @State private var photo: PhotosPickerItem?
    @State private var showCamera = false
    @State private var imageData: Data?
    @State private var note = ""
    @State private var analyzing = false
    @State private var analysis: AppStore.MealAnalysis?
    var body: some View {
        NavigationStack {
            Group {
                if !store.aiEligible { unavailable }
                else if !store.aiConsented { consent }
                else if let analysis { MealReviewView(analysis: analysis) { dismiss(); onSaved() } }
                else { capture }
            }
            .wellnessScreen().navigationTitle("ארוחה מתמונה").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("סגור") { dismiss() } } }
        }
    }
    private var unavailable: some View {
        ContentUnavailableView("ה־AI זמין מגיל 18", systemImage: "person.crop.circle.badge.exclamationmark",
            description: Text("השלם תאריך לידה בפרופיל באפליקציה הרגילה כדי להפעיל המלצות AI. אפשר להמשיך להוסיף ארוחות ידנית."))
    }
    private var consent: some View { AIConsentView() }
    private var capture: some View {
        VStack(spacing: 18) {
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image).resizable().scaledToFill().frame(height: 260).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous)).accessibilityLabel("תמונת הארוחה")
            } else {
                VStack(spacing: 12) {
                    VStack(spacing: 8) {
                        Image(systemName: "camera.viewfinder").font(.system(size: 44)).foregroundStyle(Color.wellnessSecondary)
                        Text("צלם או בחר תמונה של הארוחה").font(.hb(.headline, .semibold))
                        Text("לתוצאה מדויקת יותר צלם מלמעלה באור טוב.").font(.hb(.footnote)).foregroundStyle(Color.wellnessSecondary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity, minHeight: 130)
                    HStack(spacing: 10) {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button { showCamera = true } label: { Label("צלם ארוחה", systemImage: "camera.fill").frame(maxWidth: .infinity) }
                                .buttonStyle(PrimaryButton()).accessibilityIdentifier("meal-camera")
                        }
                        PhotosPicker(selection: $photo, matching: .images) {
                            Label("מהגלריה", systemImage: "photo.on.rectangle").font(.hb(.body, .semibold)).frame(maxWidth: .infinity, minHeight: 48)
                                .background(Color.wellnessCard, in: Capsule()).overlay(Capsule().strokeBorder(Color.wellnessHairline))
                        }.buttonStyle(PressableStyle())
                    }
                }
                .padding().frame(maxWidth: .infinity)
                .background(Color.wellnessCard, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.wellnessHairline, style: StrokeStyle(lineWidth: 1.5, dash: [6])))
            }
            TextField("הערה לשיפור הדיוק (לא חובה)", text: $note, axis: .vertical).lineLimit(1...3).padding(14)
                .background(Color.wellnessCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.wellnessHairline))
            Spacer()
            Button { Task { await analyze() } } label: {
                if analyzing { HStack(spacing: 10) { ProgressView().tint(Color.wellnessOnPrimary); Text("מנתח… זה יכול לקחת עד דקה") } } else { Label("נתח ארוחה", systemImage: "sparkles") }
            }.buttonStyle(PrimaryButton()).disabled(imageData == nil || analyzing)
        }.padding(20)
        .onChange(of: photo) { _, item in Task { await load(item) } }
        .fullScreenCover(isPresented: $showCamera) { CameraPicker { process($0) }.ignoresSafeArea() }
    }
    private func load(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        process(image)
    }
    private func process(_ image: UIImage) { imageData = MealPhoto.jpeg(from: image) }
    private func analyze() async {
        guard let imageData else { return }
        analyzing = true; defer { analyzing = false }
        if let result = await store.analyzeMeal(jpeg: imageData, description: note.trimmingCharacters(in: .whitespacesAndNewlines)) { analysis = result }
    }
}

/// Shared consent / eligibility gate (same wording and rules as the web app).
struct AIConsentView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            Image(systemName: "sparkles").font(.system(size: 34, weight: .semibold)).foregroundStyle(.white).frame(width: 84, height: 84)
                .background(LinearGradient(colors: [Color(red: 1, green: 0.62, blue: 0.25), Color(red: 1, green: 0.38, blue: 0.38)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 27, style: .continuous))
                .shadow(color: Color(red: 1, green: 0.45, blue: 0.3).opacity(0.35), radius: 16, y: 8)
            Text("אישור שימוש ב־AI").font(.hb(.title2, .bold))
            VStack(spacing: 10) {
                point("paperplane.fill", Color.proteinBlue, "אישור שימוש ב־AI שולח את תוכן הבקשה הדרוש ל־Cloudflare. התוצאות דורשות בדיקה ואישור שלך.")
                point("lock.shield.fill", Color.carbsGold, "שם, PIN ופרופיל גוף מלא אינם נשלחים אוטומטית. אין שימוש בתוכן לאימון המודלים. אפשר לבטל בהגדרות.")
            }
            Spacer(minLength: 0)
            Button { Task { _ = await store.grantAIConsent() } } label: {
                if store.busy { ProgressView().tint(Color.wellnessOnPrimary) } else { Text("מאשר/ת שימוש ב־AI האישי") }
            }.buttonStyle(PrimaryButton()).disabled(store.busy)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func point(_ symbol: String, _ color: Color, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(color).frame(width: 36, height: 36)
                .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(text).font(.hb(.subheadline)).foregroundStyle(Color.wellnessInk).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
        }.wellnessCard(padding: 14)
    }
}

/// System camera (photo only). Hands back the captured image, or nothing when cancelled.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController(); picker.sourceType = .camera; picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
