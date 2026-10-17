import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Placeholder for the camera: a drawn pack with its nutrition panel.
/// The real app shows the DataScannerViewController feed here, then the captured still.
struct CameraBackdrop: View {
    let target: LabelPanel
    let phase: AppModel.Phase
    let labelFound: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color(hex: 0x2C2A27), Color(hex: 0x121110)], startPoint: .top, endPoint: .bottom)

                PackSurface(panel: target)
                    .overlay(Color.black.opacity(phase == .result ? 0.4 : 0))
                    .frame(width: proxy.size.width * 1.25, height: proxy.size.height * 0.8)
                    .rotationEffect(.degrees(-4))
                    .offset(x: -proxy.size.width * 0.12, y: -proxy.size.height * 0.06)

                VStack(alignment: .leading, spacing: 12) {
                    if let claim = target.frontClaim {
                        Text(claim)
                            .font(.headline.weight(.heavy))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.white, in: .rect(cornerRadius: 4))
                            .foregroundStyle(.black)
                    }
                    Text(target.ingredients)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.8))
                        .opacity(phase == .result ? 0.5 : 1)
                    PrintedLabelView(panel: target)
                        .frame(width: proxy.size.width * 0.72, alignment: .leading)
                        .overlay {
                            ScanHighlight(phase: phase, labelFound: labelFound)
                        }
                }
                .rotationEffect(.degrees(-4))
                .padding(.leading, proxy.size.width * 0.08)
                .padding(.top, 150)
                .frame(width: proxy.size.width * 0.85, alignment: .leading)

                if phase == .scanning {
                    Text("Simulated camera")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .glassEffect()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 64)
                }
            }
        }
        .animation(.snappy, value: phase == .result)
    }
}

private struct PackSurface: View {
    let panel: LabelPanel

    var body: some View {
        LinearGradient(colors: panel.packColors.map(Color.init(hex:)), startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(RadialGradient(colors: [.white.opacity(0.22), .clear], center: .topLeading, startRadius: 0, endRadius: 320))
    }
}

/// Yellow corners while the scanner locks on; a solid outline once the frame is captured.
private struct ScanHighlight: View {
    let phase: AppModel.Phase
    let labelFound: Bool

    var body: some View {
        ZStack {
            if phase == .result {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.yellow, lineWidth: 2.5)
                    .shadow(color: .yellow.opacity(0.6), radius: 8)
                    .padding(-5)
            } else if labelFound {
                CornerBrackets()
                    .stroke(.yellow, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .padding(-8)
                    .transition(.scale(scale: 1.1).combined(with: .opacity))
            }
        }
    }
}

private struct CornerBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        let l: CGFloat = 22
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + l)); p.addLine(to: CGPoint(x: rect.minX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.minX + l, y: rect.minY))
        p.move(to: CGPoint(x: rect.maxX - l, y: rect.minY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + l))
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - l)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.maxX - l, y: rect.maxY))
        p.move(to: CGPoint(x: rect.minX + l, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - l))
        return p
    }
}
