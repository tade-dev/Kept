import Foundation

struct PurchaseDateSection: Identifiable {
    let id: String
    let title: String
    let purchases: [Purchase]
}

enum DateGroupedPurchases {
    static func sections(from purchases: [Purchase], now: Date = .now) -> [PurchaseDateSection] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)!
        let startOfPrevious7 = calendar.date(byAdding: .day, value: -7, to: startOfToday)!
        let startOfPrevious30 = calendar.date(byAdding: .day, value: -30, to: startOfToday)!

        var today: [Purchase] = []
        var yesterday: [Purchase] = []
        var previous7: [Purchase] = []
        var previous30: [Purchase] = []
        var earlier: [Purchase] = []

        for purchase in purchases {
            let day = calendar.startOfDay(for: purchase.purchaseDate)
            if day >= startOfToday {
                today.append(purchase)
            } else if day >= startOfYesterday {
                yesterday.append(purchase)
            } else if day >= startOfPrevious7 {
                previous7.append(purchase)
            } else if day >= startOfPrevious30 {
                previous30.append(purchase)
            } else {
                earlier.append(purchase)
            }
        }

        return [
            PurchaseDateSection(id: "today", title: "Today", purchases: today),
            PurchaseDateSection(id: "yesterday", title: "Yesterday", purchases: yesterday),
            PurchaseDateSection(id: "previous7", title: "Previous 7 Days", purchases: previous7),
            PurchaseDateSection(id: "previous30", title: "Previous 30 Days", purchases: previous30),
            PurchaseDateSection(id: "earlier", title: "Earlier", purchases: earlier),
        ]
        .filter { !$0.purchases.isEmpty }
    }
}
