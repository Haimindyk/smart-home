import SwiftUI
import AVFoundation
import PhotosUI
import WellnessCore

/// Resizes and compresses a photo for upload (max edge 1800 px, JPEG up to 5 MB).
enum MealPhoto {
    static func jpeg(from image: UIImage) -> Data? {
        let scale = min(1, 1800 / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size)); image.draw(in: CGRect(origin: .zero, size: size))
        }
        var quality = 0.86, jpeg = resized.jpegData(compressionQuality: quality)
        while let current = jpeg, current.count > 5_000_000, quality > 0.3 { quality -= 0.15; jpeg = resized.jpegData(compressionQuality: quality) }
        return jpeg
    }
    /// A plain stand-in photo used by the UI tests (the simulator has no camera).
    static func sample() -> UIImage {
        let size = CGSize(width: 900, height: 1200)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(red: 0.33, green: 0.28, blue: 0.24, alpha: 1).setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(white: 0.95, alpha: 1).setFill(); ctx.cgContext.fillEllipse(in: CGRect(x: 90, y: 330, width: 720, height: 540))
            UIColor(red: 0.72, green: 0.45, blue: 0.2, alpha: 1).setFill(); ctx.cgContext.fillEllipse(in: CGRect(x: 190, y: 470, width: 300, height: 210))
            UIColor(red: 0.97, green: 0.95, blue: 0.88, alpha: 1).setFill(); ctx.cgContext.fillEllipse(in: CGRect(x: 450, y: 520, width: 260, height: 200))
        }
    }
}

// MARK: - Camera

final class CameraModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    enum Status { case loading, ready, denied, unavailable }
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "kh.camera")
    private var input: AVCaptureDeviceInput?
    private var onPhoto: ((UIImage) -> Void)?
    @Published private(set) var status: Status = .loading
    @Published private(set) var hasUltraWide = false
    @Published var ultraWide = false
    @Published var flashOn = false

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configure()
        case .notDetermined: AVCaptureDevice.requestAccess(for: .video) { ok in DispatchQueue.main.async { if ok { self.configure() } else { self.status = .denied } } }
        default: status = .denied
        }
    }
    func stop() { queue.async { if self.session.isRunning { self.session.stopRunning() } } }
    private func device(ultra: Bool) -> AVCaptureDevice? {
        AVCaptureDevice.default(ultra ? .builtInUltraWideCamera : .builtInWideAngleCamera, for: .video, position: .back)
    }
    private func configure() {
        queue.async {
            guard self.input == nil else { if !self.session.isRunning { self.session.startRunning() }; return }
            guard let device = self.device(ultra: false), let input = try? AVCaptureDeviceInput(device: device) else { DispatchQueue.main.async { self.status = .unavailable }; return }
            self.session.beginConfiguration(); self.session.sessionPreset = .photo
            if self.session.canAddInput(input) { self.session.addInput(input); self.input = input }
            if self.session.canAddOutput(self.output) { self.session.addOutput(self.output) }
            self.session.commitConfiguration(); self.session.startRunning()
            let ultra = self.device(ultra: true) != nil
            DispatchQueue.main.async { self.status = .ready; self.hasUltraWide = ultra }
        }
    }
    func setUltraWide(_ on: Bool) {
        ultraWide = on
        queue.async {
            guard let device = self.device(ultra: on), let new = try? AVCaptureDeviceInput(device: device) else { return }
            self.session.beginConfiguration()
            let old = self.input
            if let old { self.session.removeInput(old) }
            if self.session.canAddInput(new) { self.session.addInput(new); self.input = new }
            // Switching failed: put the previous lens back, or the viewfinder would stay black.
            else if let old, self.session.canAddInput(old) { self.session.addInput(old) }
            self.session.commitConfiguration()
        }
    }
    func capture(_ done: @escaping (UIImage) -> Void) {
        onPhoto = done
        queue.async {
            let settings = AVCapturePhotoSettings()
            if self.output.supportedFlashModes.contains(.on) { settings.flashMode = self.flashOn ? .on : .off }
            self.output.capturePhoto(with: settings, delegate: self)
        }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
        DispatchQueue.main.async { self.onPhoto?(image); self.onPhoto = nil }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    final class View: UIView { override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self } }
    func makeUIView(context: Context) -> View {
        let view = View(); let layer = view.layer as! AVCaptureVideoPreviewLayer
        layer.session = session; layer.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ uiView: View, context: Context) {}
}

// MARK: - Screen

/// Camera-first "add a meal": live viewfinder, shutter, gallery, flash, 1x / 0.5x, and chips for barcode, description and more.
struct MealCameraScreen: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var home: HomeStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var center = MealAnalysisCenter.shared
    @StateObject private var camera = CameraModel()
    @State private var photoItem: PhotosPickerItem?
    @State private var showMore = false
    @State private var showBarcode = false
    @State private var showDescribe = false
    @State private var showHelp = false
    @State private var showConsent = false
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if camera.status == .ready { CameraPreview(session: camera.session).ignoresSafeArea() } else { placeholder }
            viewfinder
            VStack(spacing: 0) {
                topBar.padding(.top, 8)
                Spacer()
                modeChips.padding(.bottom, 14)
                if camera.hasUltraWide { zoomPicker.padding(.bottom, 14) }
                bottomBar.padding(.bottom, 18)
            }.padding(.horizontal, 16)
            if let phase = center.phase { analysisOverlay(phase) }
        }
        .statusBarHidden(false).preferredColorScheme(.dark)
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: center.phase) { _, phase in
            if phase == .ready { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { center.openResult() } }
        }
        .onChange(of: photoItem) { _, item in Task { await loadFromGallery(item) } }
        .sheet(isPresented: $showMore) { AddMealSheet().environmentObject(store).presentationDragIndicator(.visible) }
        .sheet(isPresented: $showBarcode) { AddMealSheet(autoScan: true).environmentObject(store).presentationDragIndicator(.visible) }
        .sheet(isPresented: $showDescribe) { DescribeMealSheet { text in center.startText(description: text, store: store) }.environmentObject(store).presentationDetents([.medium, .large]).presentationDragIndicator(.visible) }
        .sheet(isPresented: $showHelp) { CameraHelpSheet().presentationDetents([.medium]).presentationDragIndicator(.visible) }
        .sheet(isPresented: $showConsent) { AIConsentView().environmentObject(store).presentationDetents([.large]).presentationDragIndicator(.visible) }
    }

    // MARK: Pieces

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.16), Color(white: 0.06)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 10) {
                Image(systemName: camera.status == .denied ? "camera.badge.ellipsis" : "camera.fill").font(.system(size: 38)).foregroundStyle(.white.opacity(0.5))
                Text(camera.status == .denied ? "אין גישה למצלמה. אפשר לאשר אותה בהגדרות המכשיר, או לבחור תמונה מהגלריה." : camera.status == .loading ? "" : "המצלמה לא זמינה במכשיר הזה. אפשר לבחור תמונה מהגלריה.")
                    .font(.hb(.subheadline)).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center).padding(.horizontal, 40)
            }
        }
    }
    private var viewfinder: some View {
        GeometryReader { geo in
            let rect = CGRect(x: geo.size.width * 0.14, y: geo.size.height * 0.27, width: geo.size.width * 0.72, height: geo.size.height * 0.36)
            ZStack { ForEach(0..<4, id: \.self) { corner in Bracket().stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round)).frame(width: 34, height: 34)
                .rotationEffect(.degrees(Double(corner) * 90)).position(x: corner == 0 || corner == 3 ? rect.minX + 17 : rect.maxX - 17, y: corner < 2 ? rect.minY + 17 : rect.maxY - 17) } }
        }.allowsHitTesting(false).ignoresSafeArea()
    }
    private var topBar: some View {
        ZStack {
            Text("צילום ארוחה").font(.hb(.subheadline, .semibold)).foregroundStyle(.white).padding(.horizontal, 18).padding(.vertical, 10).background(.black.opacity(0.4), in: Capsule())
            HStack(spacing: 10) {
                roundButton("xmark", "סגירה", id: "camera-close") { dismiss() }
                roundButton("questionmark", "עזרה", id: "camera-help") { showHelp = true }
                Spacer()
            }.environment(\.layoutDirection, .leftToRight)
        }
    }
    private var modeChips: some View {
        HStack(spacing: 10) {
            chip("סריקת ברקוד", "barcode.viewfinder", id: "camera-barcode") { showBarcode = true }
            chip("תיאור", "text.bubble", id: "camera-describe") { showDescribe = true }
            chip("עוד", "ellipsis", id: "camera-more") { showMore = true }
        }
    }
    private var zoomPicker: some View {
        HStack(spacing: 4) {
            zoomOption("1x", on: !camera.ultraWide) { camera.setUltraWide(false) }
            zoomOption("0.5x", on: camera.ultraWide) { camera.setUltraWide(true) }
        }.padding(4).background(.black.opacity(0.4), in: Capsule())
    }
    private var bottomBar: some View {
        HStack {
            PhotosPicker(selection: $photoItem, matching: .images) { roundLabel("photo.on.rectangle", size: 54) }.accessibilityLabel("בחירה מהגלריה").accessibilityIdentifier("camera-gallery")
            Spacer()
            Button { shoot() } label: {
                ZStack { Circle().strokeBorder(.white, lineWidth: 4).frame(width: 82, height: 82); Circle().fill(.white).frame(width: 66, height: 66) }
            }.buttonStyle(PressableStyle()).disabled(center.isBusy).accessibilityLabel("צילום").accessibilityIdentifier("camera-shutter")
            Spacer()
            Button { camera.flashOn.toggle() } label: { roundLabel(camera.flashOn ? "bolt.fill" : "bolt.slash.fill", size: 54) }.accessibilityLabel(camera.flashOn ? "כיבוי פלאש" : "הפעלת פלאש").accessibilityIdentifier("camera-flash")
        }.environment(\.layoutDirection, .leftToRight)
    }
    private func roundButton(_ symbol: String, _ label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { roundLabel(symbol, size: 46) }.accessibilityLabel(label).accessibilityIdentifier(id)
    }
    private func roundLabel(_ symbol: String, size: CGFloat) -> some View {
        Image(systemName: symbol).font(.system(size: size * 0.38, weight: .semibold)).foregroundStyle(.white).frame(width: size, height: size).background(.black.opacity(0.4), in: Circle())
    }
    private func chip(_ title: String, _ symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.hb(.subheadline, .semibold)).foregroundStyle(.white).padding(.horizontal, 16).frame(minHeight: 46).background(.black.opacity(0.4), in: Capsule())
        }.accessibilityIdentifier(id)
    }
    private func zoomOption(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.hb(.subheadline, .bold)).foregroundStyle(on ? Color.yellow : .white.opacity(0.8)).frame(minWidth: 52, minHeight: 36).background(on ? Color.white.opacity(0.16) : .clear, in: Capsule())
        }
    }

    // MARK: Actions

    private func shoot() {
        guard gate() else { return }
        if store.isFixture { submit(MealPhoto.sample()); return }
        guard camera.status == .ready else { return }
        camera.capture { submit($0) }
    }
    private func submit(_ image: UIImage) {
        guard let jpeg = MealPhoto.jpeg(from: image) else { return }
        center.start(jpeg: jpeg, note: "", store: store)
    }
    private func loadFromGallery(_ item: PhotosPickerItem?) async {
        guard let item, gate(), let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        photoItem = nil
        submit(image)
    }
    /// The AI estimate needs an adult profile and the one-time consent.
    private func gate() -> Bool {
        if center.isBusy { return false }
        guard store.aiEligible else { store.reportError("ה־AI זמין מגיל 18. השלם תאריך לידה בפרופיל."); return false }
        guard store.aiConsented else { showConsent = true; return false }
        return true
    }

    // MARK: Analysis overlay

    @ViewBuilder private func analysisOverlay(_ phase: MealAnalysisCenter.Phase) -> some View {
        ScanAnalysisView(image: center.preview, phase: phase, onBackground: { dismiss() }, onRetry: { center.clear() })
            .transition(.opacity)
    }
}

private struct Bracket: Shape {
    func path(in rect: CGRect) -> Path { var p = Path(); p.move(to: CGPoint(x: rect.minX, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + 12)); p.addQuadCurve(to: CGPoint(x: rect.minX + 12, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY)); return p }
}

// MARK: - Scan animation

/// The captured photo with a light band sweeping up and down while the AI reads it. The job keeps running if the user leaves.
struct ScanAnalysisView: View {
    let image: UIImage?
    let phase: MealAnalysisCenter.Phase
    let onBackground: () -> Void
    let onRetry: () -> Void
    @State private var sweep: CGFloat = 0
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let accent = Color(red: 0.36, green: 0.9, blue: 0.62)
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image { Color.black.overlay(Image(uiImage: image).resizable().scaledToFill()).overlay(Color.black.opacity(0.32)).clipped().ignoresSafeArea() }
            else { LinearGradient(colors: [Color(white: 0.18), Color(white: 0.05)], startPoint: .top, endPoint: .bottom).ignoresSafeArea() }
            GeometryReader { geo in
                let band: CGFloat = 150
                let y = sweep * (geo.size.height - band)
                ZStack(alignment: .top) {
                    LinearGradient(colors: [accent.opacity(0), accent.opacity(0.34), accent.opacity(0)], startPoint: .top, endPoint: .bottom).frame(height: band)
                    Rectangle().fill(accent).frame(height: 3).shadow(color: accent, radius: 10).offset(y: band / 2)
                }.offset(y: y).opacity(phase == .analyzing ? 1 : 0)
            }.ignoresSafeArea().allowsHitTesting(false)
            corners.opacity(phase == .analyzing ? (pulse ? 1 : 0.55) : 0.4)
            VStack(spacing: 14) {
                Spacer()
                switch phase {
                case .analyzing:
                    Label("מנתח את הארוחה…", systemImage: "sparkles").font(.hb(.headline, .bold)).foregroundStyle(.white).shadow(radius: 6)
                    Text("אפשר לצאת מהאפליקציה, הניתוח ימשיך ברקע ותקבל עדכון כשיסתיים.").font(.hb(.footnote)).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center).padding(.horizontal, 36)
                    Button { onBackground() } label: { Text("המשך ברקע").font(.hb(.subheadline, .semibold)).foregroundStyle(.white).padding(.horizontal, 22).frame(minHeight: 46).background(.white.opacity(0.18), in: Capsule()) }
                        .accessibilityIdentifier("scan-background")
                case .failed(let message):
                    Label("הניתוח לא הצליח", systemImage: "exclamationmark.triangle.fill").font(.hb(.headline, .bold)).foregroundStyle(.white)
                    Text(message).font(.hb(.footnote)).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center).padding(.horizontal, 36)
                    Button { onRetry() } label: { Text("צילום מחדש").font(.hb(.subheadline, .semibold)).foregroundStyle(.black).padding(.horizontal, 22).frame(minHeight: 46).background(.white, in: Capsule()) }
                        .accessibilityIdentifier("scan-retry")
                case .ready:
                    Label("מוכן", systemImage: "checkmark.circle.fill").font(.hb(.headline, .bold)).foregroundStyle(.white)
                }
            }.padding(.bottom, 56)
        }
        .onAppear {
            // UI tests wait for the app to go idle, which an endless animation never allows: show a still frame there.
            if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-test") }) { sweep = 0.45; pulse = true; return }
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) { sweep = 1 }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
    private var corners: some View {
        GeometryReader { geo in
            let rect = CGRect(x: geo.size.width * 0.1, y: geo.size.height * 0.22, width: geo.size.width * 0.8, height: geo.size.height * 0.44)
            ForEach(0..<4, id: \.self) { corner in
                Bracket().stroke(accent, style: StrokeStyle(lineWidth: 3.5, lineCap: .round)).frame(width: 40, height: 40).rotationEffect(.degrees(Double(corner) * 90))
                    .position(x: corner == 0 || corner == 3 ? rect.minX + 20 : rect.maxX - 20, y: corner < 2 ? rect.minY + 20 : rect.maxY - 20)
            }
        }.allowsHitTesting(false)
    }
}

// MARK: - Sheets

/// Describe the meal in words (the keyboard's dictation key works here too).
private struct DescribeMealSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let onSubmit: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("תאר את הארוחה").font(.hb(.title3, .bold)).padding(.top, 22)
            Text("למשל: ״חזה עוף בגריל, כוס אורז ושמן זית״. אפשר להקליד או להכתיב עם המיקרופון במקלדת.").font(.hb(.subheadline)).foregroundStyle(Color.wellnessSecondary)
            TextField("מה אכלת?", text: $text, axis: .vertical).lineLimit(3...8).focused($focused).padding(14)
                .background(Color.wellnessChip, in: RoundedRectangle(cornerRadius: 18, style: .continuous)).accessibilityIdentifier("describe-text")
            Spacer(minLength: 0)
            Button { onSubmit(text.trimmingCharacters(in: .whitespacesAndNewlines)); dismiss() } label: { Label("נתח", systemImage: "sparkles") }
                .buttonStyle(PrimaryButton()).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).count < 3).accessibilityIdentifier("describe-submit")
        }.padding(.horizontal, 20).padding(.bottom, 12).background(Color.wellnessCard).onAppear { focused = true }
    }
}

private struct CameraHelpSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("איך לצלם ארוחה").font(.hb(.title3, .bold)).padding(.top, 22)
            tip("sun.max", "צלם באור טוב, מלמעלה, כך שכל המנה בתוך המסגרת.")
            tip("fork.knife", "תמונה אחת לכל צלחת. מנות נפרדות עדיף לצלם בנפרד.")
            tip("sparkles", "ה־AI מעריך בלבד. תמיד אפשר לתקן רכיב או כמות אחרי הניתוח.")
            tip("hand.raised", "הניתוח ממשיך גם אם יוצאים מהאפליקציה.")
            Spacer()
        }.padding(.horizontal, 22).frame(maxWidth: .infinity, alignment: .leading).background(Color.wellnessCard)
    }
    private func tip(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.wellnessSecondary).frame(width: 26)
            Text(text).font(.hb(.subheadline)).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
