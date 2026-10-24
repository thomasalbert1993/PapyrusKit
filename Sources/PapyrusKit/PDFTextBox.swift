#if canImport(PDFKit)

import Foundation
import PDFKit

/// An element for rendering some text on a PDF.
///
public struct PDFTextBox: Sendable {

    /// The attributed string.
    public let attributedString: AttributedString

    /// The constrained line height.
    public let lineHeight: CGFloat?
    /// The constrained box width.
    public let maxWidth: CGFloat?
    /// The box fixed width.
    public let fixedWidth: CGFloat?
    /// The box fixed height.
    public let fixedHeight: CGFloat?
    /// The text alignment.
    public let textAlignment: NSTextAlignment

    /// The background color.
    public var backgroundColor: UIColor?
    /// The border color.
    public var borderColor: UIColor
    /// The border thickness.
    public var borderThickness: CGFloat
    /// The corner radius.
    public var cornerRadius: CGFloat
    /// The inner padding.
    public let padding: CGSize

    /// The rendering output size.
    public let outputSize: CGSize


    //-----------------
    // MARK: Rendering
    //-----------------

    /// Generating the corresponding `PDFDrawableElement`.
    ///
    /// - Parameter origin: The relative origin.
    ///
    /// - Returns: The generated `PDFDrawableElement`.
    public func makeDrawableElement(at origin: CGPoint) -> PDFDrawableElement {
        .init(relativeFrame: .init(origin: origin, size: outputSize)) { context, offset in
            draw(at: origin.adding(vector: offset), in: context)
        }
    }

    /// Drawing the text box.
    ///
    /// - Parameter point: The absolute origin.
    /// - Parameter context: The `CGContext` to draw into.
    public func draw(at point: CGPoint, in context: CGContext) {

        // 1) Box

        if backgroundColor != nil || !borderThickness.isZero {
            PDFDrawableElement.rect(
                frame: .init(origin: .zero, size: outputSize),
                cornerRadius: cornerRadius,
                fillColor: backgroundColor,
                borderColor: borderColor,
                borderThickness: borderThickness
            ).draw(at: point, in: context)
        }

        // 2) Text

        let layout = TextLayout(text: text, containerSize: containerSize)
        layout.layoutManager.drawGlyphs(
            forGlyphRange: layout.layoutManager.glyphRange(for: layout.textContainer),
            at: textOrigin(whenDrawingAt: point)
        )
    }

    /// The bottom right corner of the last glyph, to lay out what follows the text.
    ///
    /// - Parameter origin: The box origin.
    ///
    /// - Returns: The position, the box origin when the text is empty.
    public func lastGlyphBottomRightPosition(whenDrawingAt origin: CGPoint) -> CGPoint {

        let layout = TextLayout(text: text, containerSize: containerSize)
        let glyphRange = layout.layoutManager.glyphRange(for: layout.textContainer)
        guard glyphRange.length > 0 else { return origin }

        let lastGlyphIndex = glyphRange.upperBound - 1
        let textOrigin = textOrigin(whenDrawingAt: origin)
        return layout.layoutManager.boundingRect(forGlyphRange: NSRange(location: lastGlyphIndex, length: 1), in: layout.textContainer).bottomRight
            .adding(vector: .init(dx: textOrigin.x, dy: textOrigin.y))
    }


    //--------------------
    // MARK: Initializers
    //--------------------

    /// The default initializer.
    ///
    /// Underline and strikethrough are part of the attributed string, see
    /// `AttributedString.init(string:font:color:underlined:strikethrough:)`.
    ///
    /// - Parameter attributedString: The attributed text.
    /// - Parameter lineHeight: The custom line height.
    /// - Parameter maxWidth: The box max width (including padding).
    /// - Parameter fixedWidth: The box fixed width (including padding).
    /// - Parameter fixedHeight: The box fixed height (including padding), the text being
    ///   vertically centered in it.
    /// - Parameter alignment: The text alignment.
    /// - Parameter backgroundColor: The background color.
    /// - Parameter borderColor: The border color.
    /// - Parameter borderThickness: The border thickness (`0` means no border).
    /// - Parameter cornerRadius: The corner radius.
    /// - Parameter padding: The inner padding.
    public init(
        attributedString: AttributedString,
        lineHeight: CGFloat? = nil,
        maxWidth: CGFloat? = nil,
        fixedWidth: CGFloat? = nil,
        fixedHeight: CGFloat? = nil,
        alignment: NSTextAlignment = .left,
        backgroundColor: UIColor? = nil,
        borderColor: UIColor = .black,
        borderThickness: CGFloat = 0,
        cornerRadius: CGFloat = 0,
        padding: CGSize = .zero)
    {
        self.attributedString = attributedString
        self.lineHeight = lineHeight
        self.maxWidth = maxWidth
        self.fixedWidth = fixedWidth
        self.fixedHeight = fixedHeight
        self.textAlignment = alignment
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.borderThickness = borderThickness
        self.cornerRadius = cornerRadius
        self.padding = padding

        let paragraphStyle = NSMutableParagraphStyle()
        if let lineHeight {
            paragraphStyle.minimumLineHeight = lineHeight
            paragraphStyle.maximumLineHeight = lineHeight
        }
        paragraphStyle.alignment = alignment
        paragraphStyle.lineBreakMode = .byWordWrapping

        let mutableAttributedString = NSMutableAttributedString(attributedString)
        mutableAttributedString.addAttribute(.paragraphStyle, value: paragraphStyle, range: .init(location: 0, length: mutableAttributedString.length))
        let text = NSAttributedString(attributedString: mutableAttributedString)
        self.text = text

        // Measured in the widest room available, then drawn in a container fitting the text
        // (or the fixed width), which the alignment then applies within.
        let measuringWidth = (fixedWidth ?? maxWidth).map { $0 - 2 * padding.width } ?? .greatestFiniteMagnitude
        let textSize = TextLayout(text: text, containerSize: .init(width: measuringWidth, height: .greatestFiniteMagnitude)).usedSize

        outputSize = CGSize(
            width: fixedWidth ?? textSize.width + 2 * padding.width,
            height: fixedHeight ?? textSize.height + 2 * padding.height
        )
        containerSize = CGSize(
            width: fixedWidth.map { $0 - 2 * padding.width } ?? textSize.width,
            height: .greatestFiniteMagnitude
        )
        usedTextHeight = textSize.height
    }


    //---------------
    // MARK: Private
    //---------------

    /// The text with its paragraph style, ready for TextKit.
    ///
    /// An immutable copy, never mutated: reading it from several threads is safe, though
    /// `NSAttributedString` isn't marked `Sendable`.
    nonisolated(unsafe) private let text: NSAttributedString
    /// The size of the container the text is drawn in.
    private let containerSize: CGSize
    /// The height the laid out text takes.
    private let usedTextHeight: CGFloat

    /// Where the text container's origin lands for a box drawn at a given point.
    private func textOrigin(whenDrawingAt point: CGPoint) -> CGPoint {
        // Centered in the box's inner height: the padding is already added below, so it
        // comes off the available room rather than being added on top of the centering.
        var verticalCenteringOffset: CGFloat = 0
        if fixedHeight != nil {
            let innerHeight = outputSize.height - 2 * padding.height
            verticalCenteringOffset = (innerHeight - usedTextHeight) / 2
        }
        return point.adding(vector: .init(dx: padding.width, dy: padding.height + verticalCenteringOffset))
    }

    /// A TextKit stack laying out the text in a container.
    ///
    /// The box keeps no TextKit object, which aren't thread-safe: it builds a fresh stack each
    /// time it measures or draws, which keeps it `Sendable`.
    private struct TextLayout {
        let textStorage: NSTextStorage
        let textContainer: NSTextContainer
        let layoutManager: NSLayoutManager

        init(text: NSAttributedString, containerSize: CGSize) {
            textContainer = NSTextContainer(size: containerSize)
            // No room around the lines: the box's padding is the only inset.
            textContainer.lineFragmentPadding = 0
            layoutManager = NSLayoutManager()
            layoutManager.addTextContainer(textContainer)
            textStorage = NSTextStorage(attributedString: text)
            textStorage.addLayoutManager(layoutManager)
        }

        var usedSize: CGSize {
            layoutManager.usedRect(for: textContainer).size
        }
    }
}

#endif
