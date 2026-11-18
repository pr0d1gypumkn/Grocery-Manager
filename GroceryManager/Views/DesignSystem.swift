import SwiftUI

// MARK: - Formatting

extension Double {
    /// "2", "1.5", "0.25" — never "2.00".
    var quantityText: String {
        formatted(.number.precision(.fractionLength(0...2)))
    }

    /// "1 item", "2 items", "250 g" — pluralizes count units.
    func quantityText(unit: String) -> String {
        let plural = self != 1
        let shown: String = switch unit {
        case "item": plural ? "items" : "item"
        case "serving": plural ? "servings" : "serving"
        default: unit
        }
        return "\(quantityText) \(shown)"
    }
}

extension Int {
    /// "1 item", "9 items".
    func counted(_ singular: String, _ plural: String? = nil) -> String {
        "\(self) \(self == 1 ? singular : (plural ?? singular + "s"))"
    }
}

// MARK: - Category styling

enum CategoryStyle {
    static let all = ["Produce", "Dairy", "Meat", "Seafood", "Bakery", "Pantry", "Frozen", "Beverages", "Other"]

    static func symbol(for category: String) -> String {
        switch category.lowercased() {
        case "produce", "fruit", "vegetable": "leaf.fill"
        case "dairy": "drop.fill"
        case "meat", "protein": "fork.knife"
        case "seafood": "fish.fill"
        case "bakery", "grain": "birthday.cake.fill"
        case "pantry": "basket.fill"
        case "frozen": "snowflake"
        case "beverages": "cup.and.saucer.fill"
        default: "tag.fill"
        }
    }

    static func tint(for category: String) -> Color {
        switch category.lowercased() {
        case "produce", "fruit", "vegetable": .green
        case "dairy": .blue
        case "meat", "protein": .red
        case "seafood": .teal
        case "bakery", "grain": .brown
        case "pantry": .orange
        case "frozen": .cyan
        case "beverages": .purple
        default: .gray
        }
    }
}

extension MealType {
    var tint: Color {
        switch self {
        case .breakfast: .orange
        case .lunch: .yellow
        case .dinner: .indigo
        case .snack: .green
        }
    }
}

extension FoodGroup {
    var symbol: String {
        switch self {
        case .vegetables: "carrot.fill"
        case .fruit: "leaf.fill"
        case .protein: "fork.knife"
        case .legumes: "circle.hexagongrid.fill"
        case .grains: "laurel.leading"
        case .dairy: "drop.fill"
        case .healthyFats: "drop.halffull"
        }
    }

    var tint: Color {
        switch self {
        case .vegetables: .green
        case .fruit: .pink
        case .protein: .red
        case .legumes: .brown
        case .grains: .orange
        case .dairy: .blue
        case .healthyFats: .mint
        }
    }
}

/// A horizontal strip of food-group badges, in a stable order.
struct FoodGroupBadges: View {
    let groups: Set<FoodGroup>

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(FoodGroup.allCases.filter(groups.contains)) { group in
                    StatusBadge(text: group.rawValue, symbol: group.symbol, tint: group.tint)
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Backgrounds

/// A soft, tinted backdrop that gives Liquid Glass surfaces something to refract.
struct AmbientBackground: View {
    var tint: Color = .accentColor

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            LinearGradient(
                colors: [tint.opacity(0.18), .clear],
                startPoint: .top,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Components

/// A compact Liquid Glass metric tile.
struct GlassStatTile: View {
    let title: String
    let value: String
    let symbol: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)
                .frame(height: 24, alignment: .leading)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassEffect(.regular.tint(tint.opacity(0.12)), in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }
}

/// A row of stat tiles that blend together as one glass group.
struct GlassStatRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                content
            }
        }
    }
}

/// A small capsule label, e.g. "Ready", "Missing 2", "Expires in 2 days".
struct StatusBadge: View {
    let text: String
    var symbol: String?
    var tint: Color

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.14), in: .capsule)
    }
}

/// A rounded glyph tile used as a leading row icon.
struct IconTile: View {
    let symbol: String
    var tint: Color
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: .rect(cornerRadius: size * 0.28))
            .accessibilityHidden(true)
    }
}

extension View {
    /// Standard content card: a Liquid Glass surface with a continuous rounded shape.
    func glassCard(cornerRadius: CGFloat = 24, tint: Color? = nil) -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(
                tint.map { Glass.regular.tint($0.opacity(0.12)) } ?? .regular,
                in: .rect(cornerRadius: cornerRadius)
            )
    }
}
