import AppKit
import SwiftUI

/// Actual-size menu bar crops, including the native bar's vertical padding.
struct MenuBarItemPreview: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var menuBarHeight = currentMenuBarHeight
    let image: NSImage
    var showsBothAppearances = true

    private static var currentMenuBarHeight: CGFloat {
        // Status-bar thickness describes the 22-point button, not the full bar
        // on displays with a camera housing (33 points on the built-in display).
        max(NSStatusBar.system.thickness, NSApp.mainMenu?.menuBarHeight ?? 0)
    }

    var body: some View {
        VStack(spacing: 6) {
            if showsBothAppearances {
                strip(.light)
                strip(.dark)
            } else {
                strip(colorScheme)
            }
        }
        // Keep the preview's layout bounds equal to its visible strips so the
        // Settings row centers the strips, rather than an expandable VStack.
        .frame(width: 108, height: showsBothAppearances ? menuBarHeight * 2 + 6 : menuBarHeight,
               alignment: .center)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            menuBarHeight = Self.currentMenuBarHeight
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            menuBarHeight = Self.currentMenuBarHeight
        }
    }

    private func strip(_ colorScheme: ColorScheme) -> some View {
        MenuBarPreviewStrip(image: image)
            .frame(width: 108, height: menuBarHeight)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            }
            .environment(\.colorScheme, colorScheme)
    }
}

private struct MenuBarPreviewStrip: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        // Within-window blending keeps the sample self-contained; it must not
        // pick up arbitrary windows behind Settings or fade when Settings blurs.
        view.material = .menu
        view.blendingMode = .withinWindow
        view.state = .active

        let imageView = PreviewImageView()
        imageView.identifier = NSUserInterfaceItemIdentifier("menu-bar-preview-image")
        imageView.imageScaling = .scaleNone
        imageView.imageAlignment = .alignCenter
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        imageView.setContentHuggingPriority(.required, for: .vertical)
        imageView.setContentCompressionResistancePriority(.required, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.required, for: .vertical)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        let dark = context.environment.colorScheme == .dark
        let highContrast = context.environment.colorSchemeContrast == .increased
        let appearance: NSAppearance.Name = highContrast
            ? (dark ? .accessibilityHighContrastDarkAqua : .accessibilityHighContrastAqua)
            : (dark ? .darkAqua : .aqua)
        view.appearance = NSAppearance(named: appearance)
        guard let imageView = view.subviews.first as? PreviewImageView else { return }
        imageView.image = image
        imageView.invalidateIntrinsicContentSize()
        imageView.contentTintColor = image.isTemplate ? .labelColor : nil
    }
}

private final class PreviewImageView: NSImageView {
    override var intrinsicContentSize: NSSize {
        guard let image else { return super.intrinsicContentSize }
        return image.size
    }
}
