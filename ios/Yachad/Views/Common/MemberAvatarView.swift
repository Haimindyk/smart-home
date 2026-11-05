import SwiftUI

struct MemberAvatarView: View {
    let member: AreaMember?
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            Circle().fill(color)
            if let emoji = member?.avatarEmoji {
                Text(emoji).font(.system(size: size * 0.55))
            } else {
                Text(initial)
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
    }

    private var initial: String {
        String(member?.nickname.trimmingCharacters(in: .whitespaces).first ?? "?").uppercased()
    }

    private var color: Color {
        guard let hex = member?.color else { return .gray }
        return Color(hex: hex) ?? .indigo
    }
}

extension Color {
    init?(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexString = hexString.replacingOccurrences(of: "#", with: "")
        guard hexString.count == 6, let value = UInt64(hexString, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self = Color(red: r, green: g, blue: b)
    }
}
