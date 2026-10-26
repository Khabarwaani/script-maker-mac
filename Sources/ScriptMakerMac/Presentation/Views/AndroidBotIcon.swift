import SwiftUI

struct AndroidBotIcon: View {
    var size: CGFloat = 16

    init(size: CGFloat = 16) {
        self.size = size
    }

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let s = min(w, h) / 24.0
            let offsetX = (w - 24 * s) / 2
            let offsetY = (h - 24 * s) / 2

            // Antennae
            var leftAntenna = Path()
            leftAntenna.move(to: CGPoint(x: offsetX + 7.5 * s, y: offsetY + 7.0 * s))
            leftAntenna.addLine(to: CGPoint(x: offsetX + 4.5 * s, y: offsetY + 2.5 * s))
            context.stroke(leftAntenna, with: .foreground, style: StrokeStyle(lineWidth: 1.6 * s, lineCap: .round))

            var rightAntenna = Path()
            rightAntenna.move(to: CGPoint(x: offsetX + 16.5 * s, y: offsetY + 7.0 * s))
            rightAntenna.addLine(to: CGPoint(x: offsetX + 19.5 * s, y: offsetY + 2.5 * s))
            context.stroke(rightAntenna, with: .foreground, style: StrokeStyle(lineWidth: 1.6 * s, lineCap: .round))

            // Head with eye cutouts
            context.drawLayer { layer in
                let headRect = CGRect(x: offsetX + 3 * s, y: offsetY + 7 * s, width: 18 * s, height: 13 * s)
                let headPath = Path { p in
                    p.move(to: CGPoint(x: headRect.minX, y: headRect.maxY))
                    p.addLine(to: CGPoint(x: headRect.minX, y: headRect.minY + 9 * s))
                    p.addArc(
                        center: CGPoint(x: headRect.midX, y: headRect.minY + 9 * s),
                        radius: 9 * s,
                        startAngle: .degrees(180),
                        endAngle: .degrees(0),
                        clockwise: false
                    )
                    p.addLine(to: CGPoint(x: headRect.maxX, y: headRect.maxY))
                    p.closeSubpath()
                }
                layer.fill(headPath, with: .foreground)

                let leftEye = Path(ellipseIn: CGRect(x: offsetX + 6.8 * s, y: offsetY + 11.5 * s, width: 2.2 * s, height: 2.2 * s))
                let rightEye = Path(ellipseIn: CGRect(x: offsetX + 15.0 * s, y: offsetY + 11.5 * s, width: 2.2 * s, height: 2.2 * s))
                layer.blendMode = .clear
                layer.fill(leftEye, with: .color(.black))
                layer.fill(rightEye, with: .color(.black))
            }
        }
        .frame(width: size, height: size)
    }
}
