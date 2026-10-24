#if canImport(PDFKit)

import Foundation
import PDFKit

extension AttributedString {

    /// Creates a string with a font, a color, and optional underline and strikethrough.
    ///
    /// - Parameter string: The text.
    /// - Parameter font: The font.
    /// - Parameter color: The text color.
    /// - Parameter underlined: Whether the text is underlined.
    /// - Parameter strikethrough: Whether the text is struck through.
    public init(string: String, font: UIFont, color: UIColor = .black, underlined: Bool = false, strikethrough: Bool = false) {

        if underlined || strikethrough { // we use a NSAttributedString because .underlineStyle of AttributedString does not work
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
            ]
            if underlined {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            if strikethrough {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            self.init(NSAttributedString(string: string, attributes: attributes))
        }
        else {
            self.init(string)
            self.font = font
            self.foregroundColor = color
        }
    }
}

#endif
