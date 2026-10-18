import SwiftUI

// HBS house style, matching the HBS – ATEM Auto Switcher (PyQt) look:
// soft dark grey, monochrome controls, green/red only for status.

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double(hex >> 16 & 0xFF) / 255,
                  green: Double(hex >> 8 & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

enum HBS {
    static let appName = "EasyIP MAC"
    static let helpURL = URL(string: "https://github.com/nickfromsad/HBS-EasyIP-MAC#readme")!
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"

    static let header = Color(hex: 0x141414)
    static let background = Color(hex: 0x1E1E1E)
    static let field = Color(hex: 0x181818)
    static let log = Color(hex: 0x111111)
    static let button = Color(hex: 0x2A2A2A)
    static let buttonHover = Color(hex: 0x333333)
    static let buttonPressed = Color(hex: 0x1A1A1A)
    static let border = Color(hex: 0x383838)
    static let buttonBorder = Color(hex: 0x404040)
    static let hoverBorder = Color(hex: 0x606060)
    static let text = Color(hex: 0xD4D4D4)
    static let lightGrey = Color(hex: 0xC8C8C8)
    static let label = Color(hex: 0x888888)
    static let groupTitle = Color(hex: 0x686868)
    static let dim = Color(hex: 0x909090)
    static let faint = Color(hex: 0x555555)
    static let green = Color(hex: 0x00CC55)
    static let red = Color(hex: 0xFF4444)
    static let orange = Color.orange
}

// MARK: - Header

/// "//HBS | EasyIP MAC v0.1.0 ……… (?) hofbroadcast.nl"
struct HBSHeader: View {
    var update: UpdateCheck.Release?
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 0) {
            Text("//HBS")
                .font(.custom("Arial", size: 20).bold())
                .kerning(3)
                .foregroundStyle(HBS.text)
            Rectangle()
                .fill(Color(hex: 0x444444))
                .frame(width: 1, height: 28)
                .padding(.horizontal, 12)
            Text(HBS.appName)
                .font(.custom("Arial", size: 13))
                .foregroundStyle(HBS.dim)
            Text("v\(HBS.version)")
                .font(.system(size: 10))
                .foregroundStyle(HBS.faint)
                .padding(.leading, 8)
            if let update {
                Button("Update available: v\(update.version)") { openURL(update.url) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(HBS.background)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(HBS.green))
                    .padding(.leading, 12)
                    .help("Open the download page of the new version")
            }
            Spacer()
            Button("?") { openURL(HBS.helpURL) }
                .buttonStyle(HelpButtonStyle())
                .help("Open documentation")
            Text("hofbroadcast.nl")
                .font(.system(size: 10))
                .foregroundStyle(HBS.faint)
                .padding(.leading, 10)
        }
        // Leaves room for the window's traffic-light buttons, which sit inside the header.
        .padding(.leading, 80)
        .padding(.trailing, 16)
        .frame(height: 52)
        .background(HBS.header)
    }
}

private struct HelpButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverView { hovering in
            configuration.label
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(hovering ? Color(hex: 0xCCCCCC) : HBS.label)
                .frame(width: 22, height: 22)
                .background(Circle().fill(hovering ? Color(hex: 0x3A3A3A) : HBS.button))
                .overlay(Circle().stroke(hovering ? Color(hex: 0x666666) : Color(hex: 0x444444)))
        }
    }
}

// MARK: - Controls

/// Tracks mouse hover for the styles below.
struct HoverView<Content: View>: View {
    @ViewBuilder let content: (Bool) -> Content
    @State private var hovering = false

    var body: some View {
        content(hovering).onHover { hovering = $0 }
    }
}

/// Standard HBS button: dark fill, thin grey border that lights up on hover.
/// `prominent` is the light "ON" look, used for the confirm button in sheets.
struct HBSButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        HoverView { hovering in
            configuration.label
                .font(.system(size: 12, weight: prominent ? .bold : .regular))
                .foregroundStyle(prominent && isEnabled ? HBS.background : (isEnabled ? HBS.text : HBS.faint))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .frame(minHeight: 24)
                .background(RoundedRectangle(cornerRadius: 3).fill(fill(pressed: configuration.isPressed, hovering: hovering)))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(
                    prominent && isEnabled ? .clear : (hovering && isEnabled ? HBS.hoverBorder : HBS.buttonBorder)))
                .contentShape(Rectangle())
        }
    }

    private func fill(pressed: Bool, hovering: Bool) -> Color {
        if prominent && isEnabled { return hovering ? Color(hex: 0xB0B0B0) : HBS.lightGrey }
        if pressed { return HBS.buttonPressed }
        return hovering && isEnabled ? HBS.buttonHover : HBS.button
    }
}

/// Dark title strip for sheets, in the style of the main header.
struct HBSSheetHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.custom("Arial", size: 15).bold())
                .foregroundStyle(HBS.text)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(HBS.dim)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HBS.header)
    }
}

/// The big full-width button at the bottom, like AUTOMATION ON/OFF.
struct HBSBigButtonStyle: ButtonStyle {
    var active: Bool

    func makeBody(configuration: Configuration) -> some View {
        HoverView { hovering in
            configuration.label
                .font(.custom("Arial", size: 17).bold())
                .kerning(1)
                .foregroundStyle(active ? HBS.background : HBS.lightGrey)
                .frame(maxWidth: .infinity, minHeight: 65)
                .background(RoundedRectangle(cornerRadius: 8).fill(
                    active ? (hovering ? Color(hex: 0xB0B0B0) : HBS.lightGrey)
                        : (configuration.isPressed ? HBS.buttonPressed : (hovering ? Color(hex: 0x2E2E2E) : Color(hex: 0x252525)))))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(active ? .clear : (hovering ? HBS.hoverBorder : HBS.buttonBorder)))
                .contentShape(Rectangle())
        }
    }
}

/// Group box with a small grey title, like QGroupBox in the ATEM switcher.
struct HBSGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(HBS.groupTitle)
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(HBS.border))
    }
}

/// "● Connected"-style status text.
struct StatusDot: View {
    let text: String
    let color: Color

    var body: some View {
        Text("● \(text)")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(color)
    }
}

/// Small bold tag, like the CLSD / OPEN gate labels.
struct HBSTag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 2).fill(HBS.button))
    }
}

/// Dark text field matching the ATEM switcher's inputs.
struct HBSFieldStyle: TextFieldStyle {
    var valid = true

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .font(.system(size: 12).monospacedDigit())
            .foregroundStyle(valid ? HBS.text : HBS.red)
            .padding(.horizontal, 6)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 3).fill(HBS.field))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(valid ? Color(hex: 0x3A3A3A) : HBS.red.opacity(0.6)))
    }
}

/// Label + control on one line, grey description underneath (the ATEM switcher's settings layout).
struct HBSSettingRow<Control: View>: View {
    let label: String
    var description: String?
    @ViewBuilder let control: Control

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(HBS.text)
                    .frame(width: 130, alignment: .leading)
                control
            }
            if let description {
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: 0x777777))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 6)
            }
        }
    }
}
