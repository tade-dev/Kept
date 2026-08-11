import Foundation
import Observation

/// Eight ordered steps. Progress bar + back chevron only on 1–6.
enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome = 0
    case categories = 1
    case leadTimes = 2
    case valueBeat = 3
    case privacy = 4
    case existingReceipts = 5
    case notifications = 6
    case settingUp = 7

    var id: Int { rawValue }

    var showsChrome: Bool {
        (1...6).contains(rawValue)
    }

    /// Fraction 0–1 across steps 1–6, or nil when the bar is hidden.
    var progressFraction: Double? {
        guard showsChrome else { return nil }
        return Double(rawValue) / 6.0
    }

    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }

    var previous: OnboardingStep? {
        guard rawValue > 0 else { return nil }
        return OnboardingStep(rawValue: rawValue - 1)
    }
}

enum TrackedCategory: String, CaseIterable, Identifiable, Codable, Hashable {
    case electronics
    case appliances
    case furniture
    case clothing
    case everything

    var id: String { rawValue }

    var label: String {
        switch self {
        case .electronics: "Electronics"
        case .appliances: "Appliances"
        case .furniture:  "Furniture"
        case .clothing:   "Clothing"
        case .everything: "Everything"
        }
    }

    var symbol: String {
        switch self {
        case .electronics: "laptopcomputer"
        case .appliances:  "washer"
        case .furniture:   "sofa"
        case .clothing:    "tshirt"
        case .everything:  "square.grid.2x2"
        }
    }

    /// The four concrete categories — used when the user taps "Everything".
    static var concrete: [TrackedCategory] {
        [.electronics, .appliances, .furniture, .clothing]
    }
}

struct OnboardingResult: Equatable {
    var categories: Set<TrackedCategory>
    var warningLeadTimes: Set<Int>
    var hasExistingReceipts: Bool

    static let empty = OnboardingResult(
        categories: [],
        warningLeadTimes: [14],
        hasExistingReceipts: false
    )
}

/// Owns the current step and collected answers. Presented full-screen; dismissed
/// by writing `hasOnboarded`. Persists all answers to Settings on `finish()`.
@MainActor
@Observable
final class OnboardingCoordinator {
    var step: OnboardingStep = .welcome
    var result: OnboardingResult = .empty

    /// Whether the flow has enough state to enable the "Continue" button on the current step.
    var canAdvance: Bool {
        switch step {
        case .welcome, .valueBeat, .privacy, .existingReceipts, .notifications, .settingUp:
            return true
        case .categories:
            return !result.categories.isEmpty
        case .leadTimes:
            return !result.warningLeadTimes.isEmpty
        }
    }

    // MARK: - Navigation

    func advance() {
        guard let next = step.next else { return }
        step = next
    }

    func back() {
        guard let previous = step.previous else { return }
        step = previous
    }

    // MARK: - Category answers

    func toggle(_ category: TrackedCategory) {
        if category == .everything {
            let concrete = Set(TrackedCategory.concrete)
            if result.categories.isSuperset(of: concrete) {
                result.categories.removeAll()
            } else {
                result.categories = concrete
            }
            return
        }

        if result.categories.contains(category) {
            result.categories.remove(category)
        } else {
            result.categories.insert(category)
        }
    }

    /// True when all four concrete categories are selected — the "Everything" card lights up.
    var isEverythingSelected: Bool {
        result.categories.isSuperset(of: Set(TrackedCategory.concrete))
    }

    // MARK: - Lead-time answers

    func toggleLead(_ days: Int) {
        if result.warningLeadTimes.contains(days) {
            // Never let the user clear all — keep at least one.
            guard result.warningLeadTimes.count > 1 else { return }
            result.warningLeadTimes.remove(days)
        } else {
            result.warningLeadTimes.insert(days)
        }
    }

    // MARK: - Persistence

    /// Writes every answer to app-wide settings and flips `hasOnboarded`.
    /// Called from step 6 after the "Setting up" delay.
    func finish() {
        SettingsSnapshot.write(leadDays: result.warningLeadTimes)
        SettingsSnapshot.write(trackedCategories: Set(result.categories.map(\.rawValue)))
        SettingsSnapshot.markOnboarded(hasExistingReceipts: result.hasExistingReceipts)
    }
}
