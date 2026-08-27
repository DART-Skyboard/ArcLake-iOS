import SwiftUI
import StoreKit

// MARK: — ArcLakeClip root view
// Deliberately self-contained: no SceneKit, no element database, no
// GitHub/Google SDKs, no audio, no GLB assets — everything the full app
// pulls in that would blow the App Clip's 15MB budget. This reuses the same
// orbital visual language as the app's own intro animation, made
// interactive (drag to rotate, pinch to scale), so someone gets a genuine,
// branded taste of what Arc Lake looks like before deciding to get the
// full app.
struct ClipRootView: View {
    @State private var dragRotation: Double = 0
    @State private var baseRotation: Double = -18
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1

    private var totalRotation: Double { baseRotation + dragRotation }

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [Color(red: 0.05, green: 0.11, blue: 0.19),
                         Color(red: 0.02, green: 0.03, blue: 0.06)],
                center: .center, startRadius: 10, endRadius: 520)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer()
                interactiveAtom
                Spacer()
                footer
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        // SKOverlay is Apple's own purpose-built API for an App Clip's
        // "get the full app" hand-off — a native banner, not an ad-hoc
        // Safari sheet, and it's what App Review expects to see here.
        .onAppear { presentAppStoreOverlay() }
    }

    private func presentAppStoreOverlay() {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        let config = SKOverlay.AppClipConfiguration(position: .bottom)
        let overlay = SKOverlay(configuration: config)
        overlay.present(in: scene)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ClipLogoImage()
                .frame(width: 34, height: 34)
            Text("ArcLake")
                .font(.custom("Orbitron-Regular", size: 20))
                .foregroundColor(.white)
            Spacer()
            Text("PREVIEW")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(.cyan.opacity(0.6))
        }
    }

    private var interactiveAtom: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [.white, .cyan, .clear],
                                      center: .center, startRadius: 0, endRadius: 10))
                .frame(width: 16, height: 16)
                .shadow(color: .cyan.opacity(0.6), radius: 12)

            shell(radiusX: 90,  radiusY: 90,  tilt: 0,   color: .cyan, period: 3.4)
            shell(radiusX: 150, radiusY: 62,  tilt: 18,  color: Color(red: 1, green: 0.31, blue: 0.62), period: 4.6)
            shell(radiusX: 210, radiusY: 78,  tilt: -24, color: Color(red: 1, green: 0.72, blue: 0.31), period: 5.8)
        }
        .rotation3DEffect(.degrees(totalRotation), axis: (x: 0.15, y: 1, z: 0))
        .scaleEffect(scale)
        .gesture(
            DragGesture()
                .onChanged { val in dragRotation = Double(val.translation.width) / 2.4 }
                .onEnded { val in
                    baseRotation += Double(val.translation.width) / 2.4
                    dragRotation = 0
                }
        )
        .gesture(
            MagnificationGesture()
                .onChanged { val in scale = max(0.6, min(1.8, baseScale * val)) }
                .onEnded { val in baseScale = max(0.6, min(1.8, baseScale * val)) }
        )
    }

    @ViewBuilder
    private func shell(radiusX: CGFloat, radiusY: CGFloat, tilt: Double, color: Color, period: Double) -> some View {
        ZStack {
            Ellipse()
                .stroke(color.opacity(0.55), lineWidth: 1.4)
                .frame(width: radiusX * 2, height: radiusY * 2)
                .rotationEffect(.degrees(tilt))

            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let angle: Double = (t.truncatingRemainder(dividingBy: period)) / period * 2 * .pi
                let rad: Double = tilt * .pi / 180
                let ex: Double = cos(angle) * Double(radiusX)
                let ey: Double = sin(angle) * Double(radiusY)
                let rx: Double = ex * cos(rad) - ey * sin(rad)
                let ry: Double = ex * sin(rad) + ey * cos(rad)
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .shadow(color: color.opacity(0.85), radius: 6)
                    .offset(x: CGFloat(rx), y: CGFloat(ry))
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 14) {
            Text("Drag to rotate · Pinch to zoom")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))

            Button {
                presentAppStoreOverlay()
            } label: {
                HStack(spacing: 8) {
                    Text("Get the full app")
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(red: 0.31, green: 0.82, blue: 1.0))
                .clipShape(Capsule())
            }
        }
    }
}

// MARK: — Logo loader (same fix as the main app's intro — loose resource
// file, not an asset-catalog entry, so it needs an explicit path lookup)
private struct ClipLogoImage: View {
    private static let cached: UIImage? = {
        guard let path = Bundle.main.path(forResource: "ArcLakeLogo", ofType: "png"),
              let image = UIImage(contentsOfFile: path) else { return nil }
        return image
    }()

    var body: some View {
        if let ui = Self.cached {
            Image(uiImage: ui).resizable().scaledToFit()
        } else {
            Image(systemName: "atom").resizable().scaledToFit().foregroundColor(.cyan)
        }
    }
}
