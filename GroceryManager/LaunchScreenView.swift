import SwiftUI

/// Animated launch screen: a Liquid Glass meal-prep container fills with food,
/// its hinged lid swings shut, and the side clips latch.
struct LaunchScreenView: View {
    /// Called once the closing animation has finished.
    var onFinished: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var stage: Stage = .hidden
    @State private var squash = false
    @State private var glint = false

    private enum Stage: Int, Comparable {
        case hidden, tray, filled, lidReady, closed, latched
        static func < (lhs: Stage, rhs: Stage) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    private let boxSize = CGSize(width: 200, height: 136)
    private let corner: CGFloat = 30

    var body: some View {
        ZStack {
            background

            VStack(spacing: 36) {
                container
                    .padding(.top, boxSize.height) // room for the open lid above the tray

                Text("Grocery Manager")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .tracking(0.4)
                    .opacity(stage >= .tray ? 1 : 0)
                    .offset(y: stage >= .tray ? 0 : 12)
            }
            .offset(y: -boxSize.height / 2)
        }
        .task { await run() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Grocery Manager")
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            if colorScheme == .dark {
                Color.black
                // Soft colour pools so the glass has something to refract.
                Circle().fill(Color.teal.opacity(0.35)).frame(width: 320).blur(radius: 90).offset(x: -110, y: -160)
                Circle().fill(Color.orange.opacity(0.22)).frame(width: 260).blur(radius: 90).offset(x: 120, y: 120)
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.0, green: 0.75, blue: 0.91),
                        Color(red: 0.0, green: 0.78, blue: 0.70)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                Circle().fill(Color.white.opacity(0.25)).frame(width: 300).blur(radius: 80).offset(x: 100, y: -180)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Container

    private var container: some View {
        ZStack {
            tray
            clips
            lid
        }
        .frame(width: boxSize.width, height: boxSize.height)
        .scaleEffect(x: squash ? 1.04 : 1, y: squash ? 0.94 : 1, anchor: .bottom)
        .scaleEffect(stage >= .tray ? 1 : 0.6)
        .opacity(stage >= .tray ? 1 : 0)
    }

    private var tray: some View {
        let inset: CGFloat = 12
        let gap: CGFloat = 8
        let innerW = boxSize.width - inset * 2
        let innerH = boxSize.height - inset * 2
        let mainW = innerW * 0.58
        let sideW = innerW - mainW - gap
        let sideH = (innerH - gap) / 2

        return ZStack {
            HStack(spacing: gap) {
                compartment(width: mainW, height: innerH, foods: [
                    Food(symbol: "fish.fill", colors: [.pink, .orange], size: 34, offset: CGSize(width: -6, height: -10), delay: 0.0),
                    Food(symbol: "leaf.fill", colors: [.green, .mint], size: 22, offset: CGSize(width: 22, height: 22), delay: 0.12)
                ])
                VStack(spacing: gap) {
                    compartment(width: sideW, height: sideH, foods: [
                        Food(symbol: "carrot.fill", colors: [.orange, .red], size: 24, offset: .zero, delay: 0.22)
                    ])
                    compartment(width: sideW, height: sideH, foods: [
                        Food(symbol: "circle.hexagongrid.fill", colors: [.yellow, .orange], size: 22, offset: .zero, delay: 0.32)
                    ])
                }
            }
        }
        .frame(width: boxSize.width, height: boxSize.height)
        .glassEffect(.regular.tint(.white.opacity(0.08)), in: .rect(cornerRadius: corner))
    }

    private func compartment(width: CGFloat, height: CGFloat, foods: [Food]) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(colorScheme == .dark ? 0.06 : 0.12))
                .strokeBorder(.white.opacity(0.35), lineWidth: 1)

            ForEach(foods) { food in
                Image(systemName: food.symbol)
                    .font(.system(size: food.size, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: food.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                    .offset(food.offset)
                    .offset(y: stage >= .filled ? 0 : -40)
                    .scaleEffect(stage >= .filled ? 1 : 0.3)
                    .opacity(stage >= .filled ? 1 : 0)
                    .animation(
                        reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.45).delay(food.delay),
                        value: stage >= .filled
                    )
            }
        }
        .frame(width: width, height: height)
    }

    /// Lid hinged on the tray's top edge. Open = flipped 180° so it lies above the tray;
    /// closing swings it toward the viewer and down over the food.
    private var lid: some View {
        let closed = stage >= .closed
        return ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(.white.opacity(0.5), lineWidth: 1.5)

            // Glint that sweeps across once the lid seals.
            LinearGradient(
                colors: [.clear, .white.opacity(0.55), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 60)
            .rotationEffect(.degrees(20))
            .offset(x: glint ? boxSize.width : -boxSize.width)
            .blendMode(.plusLighter)

            Image(systemName: "leaf.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .opacity(closed ? 1 : 0)
        }
        .frame(width: boxSize.width + 6, height: boxSize.height + 6)
        .clipShape(.rect(cornerRadius: corner + 3))
        .glassEffect(.regular.tint(.white.opacity(0.12)), in: .rect(cornerRadius: corner + 3))
        .rotation3DEffect(
            .degrees(closed ? 0 : 180),
            axis: (x: 1, y: 0, z: 0),
            anchor: .top,
            perspective: 0.45
        )
        .opacity(stage >= .lidReady ? 1 : 0)
        .shadow(color: .black.opacity(closed ? 0.18 : 0), radius: 14, y: 8)
    }

    private var clips: some View {
        HStack {
            clip
            Spacer()
            clip
        }
        .frame(width: boxSize.width + 20)
    }

    private var clip: some View {
        Capsule()
            .fill(.clear)
            .frame(width: 10, height: 40)
            .glassEffect(.regular.tint(.white.opacity(0.3)), in: .capsule)
            .scaleEffect(y: stage >= .latched ? 1 : 0.2)
            .opacity(stage >= .latched ? 1 : 0)
    }

    // MARK: - Timeline

    private func run() async {
        if reduceMotion {
            stage = .latched
            try? await Task.sleep(for: .seconds(1.0))
            onFinished()
            return
        }

        await step(.tray, after: 0.05, .spring(duration: 0.5, bounce: 0.3))
        await step(.filled, after: 0.25, .default)              // per-food springs are staggered
        await step(.lidReady, after: 0.55, .easeOut(duration: 0.2))
        await step(.closed, after: 0.15, .spring(duration: 0.65, bounce: 0.18))

        // Lid lands: squash the box, latch the clips, sweep a glint.
        try? await Task.sleep(for: .seconds(0.45))
        withAnimation(.spring(duration: 0.18, bounce: 0)) { squash = true }
        try? await Task.sleep(for: .seconds(0.12))
        withAnimation(.spring(duration: 0.45, bounce: 0.55)) {
            squash = false
            stage = .latched
        }
        withAnimation(.easeInOut(duration: 0.7)) { glint = true }

        try? await Task.sleep(for: .seconds(0.75))
        onFinished()
    }

    private func step(_ next: Stage, after delay: Double, _ animation: Animation) async {
        try? await Task.sleep(for: .seconds(delay))
        withAnimation(animation) { stage = next }
    }
}

private struct Food: Identifiable {
    var id: String { symbol }
    let symbol: String
    let colors: [Color]
    let size: CGFloat
    let offset: CGSize
    let delay: Double
}

#Preview {
    LaunchScreenView()
}
