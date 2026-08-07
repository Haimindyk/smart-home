import SwiftUI

/// The website's body background is a solid surface plus one considered
/// accent: a soft radial wash of the primary color near the top-leading
/// corner, faint grain, nothing else. This is the SwiftUI equivalent
/// (skipping the grain texture — not worth a bundled noise asset for how
/// subtle it is at screen size).
struct AmbientBackgroundView: View {
    var body: some View {
        Theme.background
            .overlay(alignment: .topLeading) {
                RadialGradient(
                    colors: [Theme.accent.opacity(0.16), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 420
                )
            }
            .ignoresSafeArea()
    }
}
