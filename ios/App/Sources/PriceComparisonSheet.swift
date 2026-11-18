import SwiftUI
import WellnessCore

/// Which supermarket chain is cheapest for this shopping list (the web app's price comparison sheet).
struct PriceComparisonSheet: View {
    @EnvironmentObject private var home: HomeStore
    @Environment(\.dismiss) private var dismiss
    let section: HSection
    @State private var result: PriceComparison.Result?
    @State private var loaded = false
    @State private var expanded: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !loaded { HStack(spacing: 10) { ProgressView(); Text("משווים מחירים…").font(.hb(.subheadline)).foregroundStyle(Color.wellnessSecondary) }.frame(maxWidth: .infinity).padding(.top, 40) }
                    else if let result, !(result.ranked.isEmpty && result.unavailable.isEmpty) { content(result) }
                    else { ContentUnavailableView("אין מה להשוות", systemImage: "cart", description: Text("הוסף פריטים לרשימה כדי לראות איפה הכי זול.")) }
                }.padding(16)
            }
            .wellnessScreen().navigationTitle("השוואת מחירים").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("סגור") { dismiss() } } }
        }
        .task { result = await home.comparePrices(for: section); loaded = true }
    }
    @ViewBuilder private func content(_ r: PriceComparison.Result) -> some View {
        if let cheapest = r.cheapest {
            VStack(alignment: .leading, spacing: 6) {
                Label("הכי זול: \(cheapest.chain.name)", systemImage: "trophy.fill").font(.hb(.headline, .bold)).foregroundStyle(Color.kindShopping)
                Text("₪\(cheapest.total!.formatted(.number.precision(.fractionLength(2))))").font(.hb(.largeTitle, .heavy)).foregroundStyle(Color.wellnessInk)
                if let savings = r.savings, savings > 0, let percent = r.savingsPercent { Text("חיסכון של ₪\(savings.formatted(.number.precision(.fractionLength(2)))) (\(percent.formatted())%) לעומת \(r.mostExpensive?.chain.name ?? "")").font(.hb(.subheadline)).foregroundStyle(Color.wellnessSecondary) }
            }.frame(maxWidth: .infinity, alignment: .leading).wellnessCard()
        } else { Text("אף רשת לא מחירה את כל הפריטים, ולכן אי אפשר לקבוע איפה הכי זול.").font(.hb(.subheadline)).foregroundStyle(Color.wellnessSecondary).wellnessCard() }
        ForEach(r.ranked, id: \.chain.key) { chain in row(chain, best: chain.chain.key == r.cheapest?.chain.key) }
        if !r.unavailable.isEmpty { Text("ללא נתונים: " + r.unavailable.map(\.chain.name).joined(separator: "، ")).font(.hb(.footnote)).foregroundStyle(Color.wellnessSecondary) }
    }
    private func row(_ chain: PriceComparison.ChainResult, best: Bool) -> some View {
        let open = expanded == chain.chain.key
        return VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.snappy) { expanded = open ? nil : chain.chain.key } } label: {
                HStack(spacing: 12) {
                    Text(String(chain.chain.name.prefix(1))).font(.hb(.headline, .bold)).foregroundStyle(.white).frame(width: 40, height: 40).background(Color.kindInfo, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(chain.chain.name).font(.hb(.headline, .semibold)).foregroundStyle(Color.wellnessInk)
                        Text("\(chain.matched) מתוך \(chain.count) פריטים").font(.hb(.caption)).foregroundStyle(chain.matched < chain.count ? Color.fatCoralText : Color.wellnessSecondary)
                    }
                    Spacer()
                    Text("₪\((chain.total ?? 0).formatted(.number.precision(.fractionLength(2))))").font(.hb(.title3, .bold)).foregroundStyle(best ? Color.kindShopping : Color.wellnessInk).monospacedDigit()
                    Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(Color.wellnessSecondary).rotationEffect(.degrees(open ? 180 : 0))
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("price-chain-\(chain.chain.key)")
            if open {
                ForEach(chain.items, id: \.itemID) { item in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.hb(.subheadline)).foregroundStyle(Color.wellnessInk)
                            if let name = item.productName, item.status == .similar { Text("דומה: \(name)").font(.hb(.caption)).foregroundStyle(Color.wellnessSecondary) }
                        }
                        Spacer()
                        Text(item.price.map { "₪\($0.formatted(.number.precision(.fractionLength(2))))" } ?? "לא נמצא").font(.hb(.subheadline, .semibold)).foregroundStyle(item.price == nil ? Color.fatCoralText : Color.wellnessInk).monospacedDigit()
                    }
                }
            }
        }.wellnessCard(padding: 16).overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(best ? Color.kindShopping.opacity(0.6) : .clear, lineWidth: 2))
    }
}
