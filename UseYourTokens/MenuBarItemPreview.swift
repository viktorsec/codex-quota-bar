import AppKit
import SwiftUI

/// Cropped menu bars using AppKit's template rendering, with optional magnification.
struct MenuBarItemPreview: View {
    @Environment(\.colorScheme) private var colorScheme
    let image: NSImage
    var showsBothAppearances = true
    var scale: CGFloat = 1

    var body: some View {
        VStack(spacing: 6) {
            if showsBothAppearances {
                strip(.light)
                strip(.dark)
            } else {
                strip(colorScheme)
            }
        }
        .frame(width: max(108, image.size.width * scale + 24))
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func strip(_ colorScheme: ColorScheme) -> some View {
        MenuBarPreviewStrip(image: image, scale: scale)
            .frame(height: max(image.size.height, NSStatusBar.system.thickness) * scale)
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
    let scale: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        // Within-window blending keeps the sample self-contained; it must not
        // pick up arbitrary windows behind Settings or fade when Settings blurs.
        view.material = .menu
        view.blendingMode = .withinWindow
        view.state = .active

        let imageView = PreviewImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
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
        imageView.previewScale = scale
        imageView.invalidateIntrinsicContentSize()
        imageView.contentTintColor = image.isTemplate ? .labelColor : nil
    }
}

private final class PreviewImageView: NSImageView {
    var previewScale: CGFloat = 1

    override var intrinsicContentSize: NSSize {
        guard let image else { return super.intrinsicContentSize }
        return NSSize(width: image.size.width * previewScale, height: image.size.height * previewScale)
    }
}
