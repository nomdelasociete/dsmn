import AppKit
import CoreText
import SwiftUI

private struct DSMNRefreshOnAppearKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Offscreen design previews must not query platform services or renew fallback leases.
    var dsmnRefreshOnAppear: Bool {
        get { self[DSMNRefreshOnAppearKey.self] }
        set { self[DSMNRefreshOnAppearKey.self] = newValue }
    }
}

/// Identity from dsmn-website PR #5, commit b3aa932.
enum DSMNBrand {
    static let paper = adaptive(light: 0xF1F0E7, dark: 0x232621)
    static let ink = adaptive(light: 0x20231E, dark: 0xF1F0E7)
    static let muted = adaptive(light: 0x65665F, dark: 0xC0C4B9)
    static let sage = adaptive(light: 0x626B55, dark: 0xB6C8A3)
    static let orange = adaptive(light: 0xA93F24, dark: 0xF49B7E)
    static let rule = adaptive(light: 0xAAA99E, dark: 0x555B4F)
    static let field = adaptive(light: 0xFAF9F3, dark: 0x2D312A)
    static let panel = Color(hex: 0x292B28)
    static let panelInk = Color(hex: 0xE8E9E4)
    static let panelMuted = Color(hex: 0xC0C4B9)
    static let panelRule = Color(hex: 0x52574D)
    static let panelGreen = Color(hex: 0xA4BD8C)

    static var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        .module
        #else
        .main
        #endif
    }

    private static let registeredFonts: Void = {
        for name in ["GeistPixelSquare", "IBMPlexMono-Regular"] {
            if let url = resourceBundle.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }()

    static func display(_ size: CGFloat) -> Font {
        _ = registeredFonts
        return .custom("GeistPixel-Square", size: size).weight(.bold)
    }

    static func mono(_ size: CGFloat = 11) -> Font {
        _ = registeredFonts
        return .custom("IBMPlexMono-Regular", size: size)
    }

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            NSColor(srgb: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        })
    }
}

extension Color {
    init(hex: UInt32) { self.init(nsColor: NSColor(srgb: hex)) }
}

extension NSColor {
    convenience init(srgb: UInt32) {
        self.init(srgbRed: CGFloat((srgb >> 16) & 255) / 255,
                  green: CGFloat((srgb >> 8) & 255) / 255,
                  blue: CGFloat(srgb & 255) / 255, alpha: 1)
    }
}

struct DSMNPulseMark: Shape {
    func path(in rect: CGRect) -> Path {
        Path(DSMNIdentity.pulsePath(in: rect))
    }
}

struct DSMNWordmark: View {
    var size: CGFloat = 28

    var body: some View {
        HStack(spacing: 10) {
            DSMNPulseMark()
                .frame(width: size * 1.2, height: size * 0.86)
            Text("dsmn").font(DSMNBrand.display(size))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("dsmn")
    }
}

struct DSMNPageHeader: View {
    var eyebrow: String
    var title: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                DSMNWordmark()
                Spacer()
                Text(eyebrow).font(DSMNBrand.mono()).foregroundStyle(DSMNBrand.sage)
            }
            Rectangle().fill(DSMNBrand.ink).frame(height: 1)
                .padding(.bottom, 8)
            Text(title).font(DSMNBrand.display(34))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(detail).font(.system(size: 13))
                .foregroundStyle(DSMNBrand.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct DSMNActionStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(prominent ? DSMNBrand.paper : DSMNBrand.ink)
            .background(prominent ? DSMNBrand.ink : DSMNBrand.field)
            .overlay(Rectangle().strokeBorder(DSMNBrand.rule, lineWidth: prominent ? 0 : 1))
            .overlay(Rectangle().strokeBorder(DSMNBrand.orange, lineWidth: isFocused ? 2 : 0))
            .brightness(isEnabled && isHovered ? (prominent ? 0.08 : -0.03) : 0)
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
    }
}

struct DSMNSettingsRow<Actions: View>: View {
    var systemImage: String
    var title: String
    var detail: String
    var status: String
    var isComplete: Bool
    var isBusy = false
    var isOptional = false
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                if isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: systemImage).font(.system(size: 18))
                        .foregroundStyle(isComplete ? DSMNBrand.sage : DSMNBrand.muted)
                }
            }
            .frame(width: 24, height: 26)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    if isOptional {
                        Text("Optional").font(DSMNBrand.mono(10)).foregroundStyle(DSMNBrand.muted)
                    }
                }
                Text(detail).font(.system(size: 12)).foregroundStyle(DSMNBrand.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text(status).font(DSMNBrand.mono(10))
                    .foregroundStyle(isComplete ? DSMNBrand.sage : DSMNBrand.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            actions.frame(width: 160, alignment: .trailing)
                .buttonStyle(DSMNActionStyle())
        }
        .padding(.vertical, 18)
        .overlay(alignment: .bottom) { Rectangle().fill(DSMNBrand.rule).frame(height: 1) }
    }
}

struct DSMNWindowStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(DSMNBrand.ink)
            .tint(DSMNBrand.sage)
            .buttonStyle(DSMNActionStyle())
            .background(DSMNBrand.paper)
    }
}

extension View {
    func dsmnWindowStyle() -> some View { modifier(DSMNWindowStyle()) }
}
