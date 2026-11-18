import SwiftUI
import UIKit

/// Exercise demonstrations bundled from the web app (public-domain frames, see Resources/Exercises/SOURCE.txt).
struct ExerciseDemo: Decodable, Identifiable, Hashable {
    let id: String, he: String, en: String
    let cues: String?
    func image(_ frame: Int) -> UIImage? {
        guard let path = Bundle.main.path(forResource: "\(id)-\(frame)", ofType: "jpg", inDirectory: "Exercises") else { return nil }
        return UIImage(contentsOfFile: path)
    }
}

enum ExerciseDemos {
    static let all: [ExerciseDemo] = {
        guard let url = Bundle.main.url(forResource: "exercise-demos", withExtension: "json"), let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([ExerciseDemo].self, from: data)) ?? []
    }()
    static func resolve(name: String, catalogId: String? = nil) -> ExerciseDemo? {
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        if let catalogId, let hit = all.first(where: { $0.id == catalogId }) { return hit }
        return all.first { [$0.he, $0.en, $0.id].contains { $0.lowercased() == key } }
    }
}

struct ExerciseThumb: View {
    let demo: ExerciseDemo
    var size: CGFloat = 56
    var body: some View {
        Group {
            if let image = demo.image(0) { Image(uiImage: image).resizable().scaledToFill() } else { Color.wellnessChip }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)).accessibilityHidden(true)
    }
}

struct ExerciseDemoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let name: String
    let demo: ExerciseDemo
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 10) {
                        ForEach(0..<2, id: \.self) { frame in
                            if let image = demo.image(frame) {
                                Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)).accessibilityLabel(frame == 0 ? "תנוחת פתיחה" : "תנוחת סיום")
                            }
                        }
                    }
                    if let cues = demo.cues, !cues.isEmpty {
                        VStack(alignment: .leading, spacing: 8) { Text("דגשי ביצוע").sectionTitle(); Text(cues) }.frame(maxWidth: .infinity, alignment: .leading).wellnessCard()
                    }
                    Text("חומר לימוד כללי, לא הנחיה רפואית אישית.").font(.hb(.footnote)).foregroundStyle(Color.wellnessSecondary)
                }.padding(20)
            }.wellnessScreen().navigationTitle(name).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("סגור") { dismiss() } } }
        }
    }
}
