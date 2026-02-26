import SwiftUI

/// Consistent gradient background used across the entire app.
/// Replaces plain `Color.pageBackground` with radial gradient orbs for visual depth.
struct AppBackground: View {
    var body: some View {
        ZStack {
            Color.pageBackground

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.blue400.opacity(0.45), Color.blue400.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 180
                    )
                )
                .frame(width: 360, height: 360)
                .offset(x: 140, y: -320)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.blue600.opacity(0.28), Color.blue600.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 400)
                .offset(x: -160, y: -140)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.blue200.opacity(0.50), Color.blue100.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 160
                    )
                )
                .frame(width: 320, height: 320)
                .offset(x: 100, y: 300)
        }
        .ignoresSafeArea()
    }
}
