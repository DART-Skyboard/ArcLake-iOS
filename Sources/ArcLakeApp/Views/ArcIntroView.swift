import SwiftUI

// MARK: — ArcIntroView
// The welcome/"what's new" animation. Shown on first install, and again any
// time the app's marketing version differs from the last one this device
// recorded showing it to, or after a sign-out. Ends with a "Next" button
// that hands off to the existing sign-in flow — this view never signs
// anyone in itself, it's purely the intro sequence.
struct ArcIntroView: View {
    var onFinished: () -> Void

    @State private var stage: Int = 0
    @State private var showNext = false

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [Color(red: 0.05, green: 0.11, blue: 0.19),
                         Color(red: 0.02, green: 0.03, blue: 0.06)],
                center: .center, startRadius: 10, endRadius: 520)
                .ignoresSafeArea()

            GridFloorView()
                .opacity(stage >= 6 ? 1 : 0)
                .animation(.easeOut(duration: 2), value: stage)

            // Stays visible the whole way through — dims to an ambient
            // background level once the wordmark settles in, rather than
            // vanishing outright. The atom is the point of the app; it
            // shouldn't disappear the moment the logo/wordmark show up.
            OrbitalSystemView(stage: stage)
                .opacity(stage >= 7 ? 0.32 : 1)
                .animation(.easeOut(duration: 1.6), value: stage)

            // Replaced the generic Apple-default bird.fill symbol with the
            // user's own hummingbird illustration — a real, custom-designed
            // vector-style artwork (matching what's used on the website),
            // not a system glyph standing in for it.
            HummingbirdImage()
                .frame(width: 130, height: 130)
                .shadow(color: .cyan.opacity(0.55), radius: 26)
                .scaleEffect(stage >= 5 ? 1 : 0.7)
                .rotationEffect(.degrees(stage >= 5 ? 0 : -6))
                .opacity(stage >= 5 ? 1 : 0)
                .offset(y: -46)
                .animation(.spring(response: 0.9, dampingFraction: 0.75), value: stage)

            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 14) {
                    Text("ArcLake")
                        .font(.custom("Orbitron-Regular", size: 42))
                        .tracking(3)
                        .foregroundStyle(
                            LinearGradient(colors: [.white, Color(red: 0.31, green: 0.82, blue: 1.0)],
                                           startPoint: .leading, endPoint: .trailing))
                        .shadow(color: .cyan.opacity(0.5), radius: 16)
                        .opacity(stage >= 6 ? 1 : 0)
                        .offset(y: stage >= 6 ? 0 : 12)
                        .animation(.easeOut(duration: 0.6), value: stage)

                    Text("CHEMISTRY  ·  PHYSICS  ·  REIMAGINED")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .tracking(3)
                        .foregroundColor(.white.opacity(0.45))
                        .opacity(stage >= 8 ? 1 : 0)
                        .animation(.easeIn(duration: 1), value: stage)
                }
                .padding(.bottom, 150)
            }

            VStack {
                Spacer()
                if showNext {
                    Button(action: onFinished) {
                        HStack(spacing: 8) {
                            Text("Next")
                            Image(systemName: "arrow.right")
                        }
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.horizontal, 36).padding(.vertical, 14)
                        .background(Color(red: 0.31, green: 0.82, blue: 1.0))
                        .clipShape(Capsule())
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .padding(.bottom, 64)
                }
            }
        }
        .onAppear { runTimeline() }
    }

    // Mirrors the approved HTML preview's beats exactly, so what ships
    // matches what was already reviewed.
    private func runTimeline() {
        let beats: [(Double, Int)] = [
            (0.15, 1), (0.9, 2), (1.5, 3), (2.1, 4),
            (4.9, 5), (5.35, 6), (6.3, 7), (7.4, 8),
        ]
        for (delay, s) in beats {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { stage = s }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.6) {
            withAnimation(.easeOut(duration: 0.5)) { showNext = true }
        }
    }
}

// MARK: — Orbital system (nucleus + three tilted electron shells)
// MARK: — Hummingbird artwork loader
// ArcLakeHummingbird.png lives as a loose file under Resources/, not inside
// Assets.xcassets — Image("name") only searches the asset catalog by name
// and silently renders nothing for a loose file (the same reason the old
// ArcLakeLogo.png badge never appeared before it was fixed). Loading it
// explicitly by path is what actually works for a bundled-but-uncatalogued
// resource.
private struct HummingbirdImage: View {
    private static let cached: UIImage? = {
        guard let path = Bundle.main.path(forResource: "ArcLakeHummingbird", ofType: "png"),
              let image = UIImage(contentsOfFile: path) else { return nil }
        return image
    }()

    var body: some View {
        if let ui = Self.cached {
            Image(uiImage: ui).resizable().scaledToFit()
        } else {
            // Should never hit in practice, but never render a blank gap
            Image(systemName: "bird.fill")
                .resizable().scaledToFit()
                .foregroundColor(.cyan)
        }
    }
}

private struct OrbitalSystemView: View {
    let stage: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [.white, .cyan, .clear],
                                      center: .center, startRadius: 0, endRadius: 10))
                .frame(width: 14, height: 14)
                .shadow(color: .cyan.opacity(0.6), radius: 10)
                .scaleEffect(stage >= 1 ? 1 : 0.2)
                .opacity(stage >= 1 ? 1 : 0)
                .animation(.spring(response: 0.7, dampingFraction: 0.6), value: stage)

            // Scaled down from the original 96/168/240 radii — the
            // outermost ring, combined with its tilt, was extending past
            // both screen edges on a typical phone width instead of
            // staying comfortably within view.
            shell(radiusX: 62,  radiusY: 62, tilt: 0,   color: .cyan,
                  active: stage >= 2, period: 3.4)
            shell(radiusX: 108, radiusY: 45, tilt: 18,  color: Color(red: 1, green: 0.31, blue: 0.62),
                  active: stage >= 3, period: 4.6)
            shell(radiusX: 154, radiusY: 57, tilt: -24, color: Color(red: 1, green: 0.72, blue: 0.31),
                  active: stage >= 4, period: 5.8)
        }
    }

    @ViewBuilder
    private func shell(radiusX: CGFloat, radiusY: CGFloat, tilt: Double,
                        color: Color, active: Bool, period: Double) -> some View {
        ZStack {
            Ellipse()
                .stroke(color.opacity(0.5), lineWidth: 1.4)
                .frame(width: radiusX * 2, height: radiusY * 2)
                .rotationEffect(.degrees(tilt))
                .opacity(active ? 1 : 0)
                .animation(.easeOut(duration: 1.1), value: active)

            if active {
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    // Keep every term as plain Double through the whole
                    // calculation — mixing Double and CGFloat operands in
                    // the same expression is what made cos()/sin() an
                    // "ambiguous use" for the compiler; only convert to
                    // CGFloat once, at the very end.
                    let angle: Double = (t.truncatingRemainder(dividingBy: period)) / period * 2 * .pi
                    let rad: Double = tilt * .pi / 180
                    let ex: Double = cos(angle) * Double(radiusX)
                    let ey: Double = sin(angle) * Double(radiusY)
                    let rx: Double = ex * cos(rad) - ey * sin(rad)
                    let ry: Double = ex * sin(rad) + ey * cos(rad)
                    Circle()
                        .fill(color)
                        .frame(width: 7, height: 7)
                        .shadow(color: color.opacity(0.85), radius: 6)
                        .offset(x: CGFloat(rx), y: CGFloat(ry))
                }
            }
        }
    }
}

// MARK: — Perspective grid floor, echoing the app's own 3D viewport
private struct GridFloorView: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 40
            var x: CGFloat = 0
            while x <= size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(.cyan.opacity(0.14)), lineWidth: 1)
                x += step
            }
            var y: CGFloat = 0
            while y <= size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(.cyan.opacity(0.14)), lineWidth: 1)
                y += step
            }
        }
        .frame(height: 280)
        .rotation3DEffect(.degrees(75), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.6)
        .mask(LinearGradient(colors: [.white, .white, .clear], startPoint: .top, endPoint: .bottom))
        .frame(maxHeight: .infinity, alignment: .bottom)
    }
}
