import SwiftUI

struct BaseDiamondView: View {
    let bases: Int

    private func filled(_ bit: Int) -> Bool { (bases & bit) != 0 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.thinMaterial)
                .frame(width: 150, height: 150)

            // 2B (top)
            baseIcon(filled(2))
                .offset(x: 0, y: -45)

            // 3B (left)
            baseIcon(filled(4))
                .offset(x: -45, y: 0)

            // 1B (right)
            baseIcon(filled(1))
                .offset(x: 45, y: 0)

            // Home (bottom) - just a marker
            Image(systemName: "house.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
                .offset(x: 0, y: 45)
        }
    }

    private func baseIcon(_ isFilled: Bool) -> some View {
        Image(systemName: isFilled ? "diamond.fill" : "diamond")
            .font(.title2)
    }
}

struct CountView: View {
    let balls: Int
    let strikes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Count").font(.headline)
            HStack(spacing: 8) {
                Text("B:")
                Dots(count: 4, filled: balls)
                Text("S:")
                Dots(count: 3, filled: strikes)
            }
            .monospacedDigit()
        }
    }
}

struct OutsView: View {
    let outs: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Outs").font(.headline)
            Dots(count: 3, filled: outs)
        }
    }
}

struct Dots: View {
    let count: Int
    let filled: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Image(systemName: i < filled ? "circle.fill" : "circle")
                    .font(.caption)
            }
        }
    }
}

