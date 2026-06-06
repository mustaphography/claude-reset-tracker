import AppKit
import SwiftUI

/// Renders the menu bar label: the reset time as text, colored by real usage.
///
/// Matches Nimbalyst's usage indicator exactly — three discrete steps, not a
/// gradient: green below 50%, yellow 50–79%, red at 80%+ (Tailwind 500-level
/// colors), and a neutral gray when usage is unknown. A faint adaptive halo
/// keeps every color legible on any menu bar background (light or dark).
enum MenuBarIcon {
    /// Used when real usage is unknown — we show the time but don't fake a color.
    static let neutral = NSColor(srgbRed: 0.6, green: 0.6, blue: 0.62, alpha: 1)

    /// utilization is 0–100. Thresholds and colors mirror Nimbalyst.
    static func color(utilization u: Double) -> NSColor {
        if u >= 80 { return NSColor(srgbRed: 239 / 255.0, green: 68 / 255.0,  blue: 68 / 255.0, alpha: 1) }  // red-500
        if u >= 50 { return NSColor(srgbRed: 234 / 255.0, green: 179 / 255.0, blue: 8 / 255.0,  alpha: 1) }  // yellow-500
        return NSColor(srgbRed: 34 / 255.0, green: 197 / 255.0, blue: 94 / 255.0, alpha: 1)                  // green-500
    }

    /// Draw `text` in `color` with an adaptive legibility halo, as a
    /// non-template (full-color) image suitable for a menu bar label.
    static func render(text: String, color rawColor: NSColor) -> NSImage {
        let color = rawColor.usingColorSpace(.sRGB) ?? rawColor
        let font = NSFont.systemFont(ofSize: 13, weight: .regular)

        let lum = 0.299 * color.redComponent + 0.587 * color.greenComponent + 0.114 * color.blueComponent
        let halo = (lum > 0.5 ? NSColor.black : NSColor.white).withAlphaComponent(0.45)
        let shadow = NSShadow()
        shadow.shadowColor = halo
        shadow.shadowBlurRadius = 1.5
        shadow.shadowOffset = .zero

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .shadow: shadow,
        ]
        let attr = NSAttributedString(string: text, attributes: attrs)
        let textSize = attr.size()
        let pad: CGFloat = 6
        let imgSize = NSSize(width: ceil(textSize.width) + pad,
                             height: ceil(textSize.height) + pad)

        let image = NSImage(size: imgSize, flipped: false) { rect in
            attr.draw(at: NSPoint(x: pad / 2,
                                  y: (rect.height - textSize.height) / 2))
            return true
        }
        image.isTemplate = false  // preserve our colors; don't let the bar tint it
        return image
    }
}
