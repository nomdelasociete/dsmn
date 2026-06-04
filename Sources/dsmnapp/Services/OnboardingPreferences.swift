import Foundation

enum OnboardingPreferences {
    private static let legacyHasSeenOnboardingKey = "hasSeenOnboarding"
    static let wizardDismissedKey = "onboardingWizardDismissed"
    static let setupRemindersSuppressedKey = "setupRemindersSuppressed"

    static var wizardDismissed: Bool {
        get { UserDefaults.standard.bool(forKey: wizardDismissedKey) }
        set { UserDefaults.standard.set(newValue, forKey: wizardDismissedKey) }
    }

    static var setupRemindersSuppressed: Bool {
        get { UserDefaults.standard.bool(forKey: setupRemindersSuppressedKey) }
        set { UserDefaults.standard.set(newValue, forKey: setupRemindersSuppressedKey) }
    }

    static func migrateLegacyKeysIfNeeded() {
        guard UserDefaults.standard.bool(forKey: legacyHasSeenOnboardingKey) else {
            return
        }

        if !wizardDismissed {
            wizardDismissed = true
        }

        UserDefaults.standard.removeObject(forKey: legacyHasSeenOnboardingKey)
    }
}