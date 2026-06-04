import Foundation

enum OnboardingPreferences {
    private static let legacyHasSeenOnboardingKey = "hasSeenOnboarding"
    static let wizardDismissedKey = "onboardingWizardDismissed"
    static let setupRemindersSuppressedKey = "setupRemindersSuppressed"
    static let deferredHelperUpdateBuildKey = "deferredHelperUpdateBuild"

    static var wizardDismissed: Bool {
        get { UserDefaults.standard.bool(forKey: wizardDismissedKey) }
        set { UserDefaults.standard.set(newValue, forKey: wizardDismissedKey) }
    }

    static var setupRemindersSuppressed: Bool {
        get { UserDefaults.standard.bool(forKey: setupRemindersSuppressedKey) }
        set { UserDefaults.standard.set(newValue, forKey: setupRemindersSuppressedKey) }
    }

    static var deferredHelperUpdateBuild: Int? {
        get {
            guard UserDefaults.standard.object(forKey: deferredHelperUpdateBuildKey) != nil else {
                return nil
            }

            return UserDefaults.standard.integer(forKey: deferredHelperUpdateBuildKey)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: deferredHelperUpdateBuildKey)
            } else {
                UserDefaults.standard.removeObject(forKey: deferredHelperUpdateBuildKey)
            }
        }
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
