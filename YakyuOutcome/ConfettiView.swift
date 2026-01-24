import SwiftUI
import UIKit

struct ConfettiView: UIViewRepresentable {
    func makeUIView(context: Context) -> ConfettiEmitterView {
        ConfettiEmitterView()
    }

    func updateUIView(_ uiView: ConfettiEmitterView, context: Context) {}
}

final class ConfettiEmitterView: UIView {
    override class var layerClass: AnyClass { CAEmitterLayer.self }

    private var emitterLayer: CAEmitterLayer { layer as! CAEmitterLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureEmitter()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureEmitter()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        emitterLayer.emitterPosition = CGPoint(x: bounds.midX, y: -30)
        emitterLayer.emitterSize = CGSize(width: bounds.width, height: 1)
        emitterLayer.emitterShape = .line
        emitterLayer.emitterMode = .outline
        emitterLayer.beginTime = CACurrentMediaTime()
    }

    private func configureEmitter() {
        backgroundColor = .clear
        emitterLayer.renderMode = .unordered
        emitterLayer.birthRate = 1

        let colors: [UIColor] = [
            .systemRed, .systemBlue, .systemGreen, .systemOrange, .systemYellow, .systemPink, .systemTeal
        ]

        emitterLayer.emitterCells = colors.map { color in
            let cell = CAEmitterCell()
            cell.birthRate = 12
            cell.lifetime = 4.0
            cell.velocity = 260
            cell.velocityRange = 180
            cell.emissionLongitude = .pi
            cell.emissionRange = .pi / 3
            cell.yAcceleration = 280
            cell.spin = 3.0
            cell.spinRange = 4.0
            cell.scale = 0.12
            cell.scaleRange = 0.06
            cell.alphaSpeed = -0.25
            cell.color = color.cgColor
            cell.contents = confettiImage().cgImage
            return cell
        }
    }

    private func confettiImage() -> UIImage {
        let size = CGSize(width: 10, height: 18)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        let ctx = UIGraphicsGetCurrentContext()
        ctx?.setFillColor(UIColor.white.cgColor)
        ctx?.fill(CGRect(origin: .zero, size: size))
        let img = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        return img
    }
}
