import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("yachad.myNickname") private var myNickname: String = ""

    var body: some View {
        Group {
            if myNickname.trimmingCharacters(in: .whitespaces).isEmpty {
                NicknameOnboardingView(nickname: $myNickname)
            } else {
                AreaListView()
            }
        }
        .task { await appState.refreshAreas() }
        .onOpenURL { url in
            NotificationCenter.default.post(name: .yachadOpenInviteURL, object: url)
        }
    }
}

extension Notification.Name {
    static let yachadOpenInviteURL = Notification.Name("yachad.openInviteURL")
}
