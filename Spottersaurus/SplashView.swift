//
//  SplashView.swift
//  Spottersaurus
//
//  Animated in-app launch screen, themed to the dino mascot (navy + safety
//  orange). Shown over the app on cold start, then fades out. Mirrors the
//  static LaunchScreen.storyboard so the transition from system launch to app
//  is seamless. Motion follows the design brief: elastic logo entrance,
//  concentric pulsing ring, smooth fade.
//

import SwiftUI
import SpottersaurusKit

struct SplashView: View {
    /// Called once the splash has finished animating out.
    var onFinished: () -> Void = {}

    @State private var logoIn = false
    @State private var ringPulse = false
    @State private var fadeOut = false

    private var background: LinearGradient {
        LinearGradient(
            colors: [Theme.Colors.brandNavy, Theme.Colors.brandNavyDark],
            startPoint: .top, endPoint: .bottom
        )
    }

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            VStack(spacing: Theme.Spacing.lg) {
                ZStack {
                    // concentric pulsing ring — bar-speed gauge motif
                    Circle()
                        .stroke(Theme.Colors.brandOrange.opacity(0.55), lineWidth: 4)
                        .frame(width: 220, height: 220)
                        .scaleEffect(ringPulse ? 1.12 : 0.92)
                        .opacity(ringPulse ? 0.0 : 0.6)

                    // app badge logo
                    Image("LaunchLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 168, height: 168)
                        .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
                        .scaleEffect(logoIn ? 1.0 : 0.7)
                        .opacity(logoIn ? 1.0 : 0.0)
                }

                VStack(spacing: Theme.Spacing.xs) {
                    Text("SPOTTERSAURUS")
                        .font(.system(.title, design: .rounded).weight(.heavy))
                        .tracking(1.5)
                        .foregroundStyle(.white)
                    Text("AUTO-SPOTTER")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .tracking(3)
                        .foregroundStyle(Theme.Colors.brandOrange)
                }
                .opacity(logoIn ? 1.0 : 0.0)
            }
        }
        .opacity(fadeOut ? 0.0 : 1.0)
        .onAppear(perform: run)
    }

    private func run() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
            logoIn = true
        }
        withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
            ringPulse = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.45)) { fadeOut = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { onFinished() }
        }
    }
}

#Preview {
    SplashView()
}
