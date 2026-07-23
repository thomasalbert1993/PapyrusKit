#if canImport(PDFKit)

import Foundation
import PDFKit

/// An element for rendering some text on a PDF.
///
public struct PDFTextBox {
    
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
        
        var verticalCenteringOffset: CGFloat = 0
        if fixedHeight != nil {
            verticalCenteringOffset = (outputSize.height - textContainer.size.height) / 2
        }
        
        layoutManager.drawGlyphs(
            forGlyphRange: layoutManager.glyphRange(for: textContainer),
            at: point
                .adding(vector: .init(dx: padding.width, dy: padding.height))
                .adding(vector: Self.drawingOffset)
                .adding(vector: .init(dx: 0, dy: verticalCenteringOffset))
        )
    }
    
    public func lastGlyphBottomRightPosition(whenDrawingAt origin: CGPoint) -> CGPoint {
        
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        guard glyphRange.length > 0 else { return origin }
        
        let lastGlyphIndex = glyphRange.upperBound - 1
        return layoutManager.boundingRect(forGlyphRange: NSRange(location: lastGlyphIndex, length: 1), in: textContainer).bottomRight
            .adding(vector: .init(dx: origin.x, dy: origin.y))
            .adding(vector: .init(dx: padding.width, dy: padding.height))
            .adding(vector: Self.drawingOffset)
    }
    
    
    //--------------------
    // MARK: Initializers
    //--------------------
    
    /// The default initializer.
    ///
    /// - Parameter attributedString: The attributed text.
    /// - Parameter strikethrough: A boolean indicating whether the text shoule be striketrought.
    /// - Parameter lineHeight: The custom line height.
    /// - Parameter maxWidth: The box max width (including padding).
    /// - Parameter fixedWidth: The box fixed width (including padding).
    /// - Parameter alignment: The text alignment.
    /// - Parameter backgroundColor: The background color.
    /// - Parameter borderColor: The border color.
    /// - Parameter borderThickness: The border thickness (`nil` means no border).
    /// - Parameter cornerRadius: The corner radius.
    /// - Parameter padding: The inner padding.
    public init(
        attributedString: AttributedString,
        strikethrough: Bool = false,
        lineHeight: CGFloat? = nil,
        maxWidth: CGFloat? = nil,
        fixedWidth: CGFloat? = nil,
        fixedHeight: CGFloat? = nil,
        alignment: NSTextAlignment = .left,
        backgroundColor: UIColor? = nil,
        borderColor: UIColor = .black,
        borderThickness: CGFloat = 0,
        cornerRadius: CGFloat = 0,
        padding: CGSize = .zero,
        renderer: PDFRenderer)
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
        if strikethrough {
            mutableAttributedString.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: .init(location: 0, length: mutableAttributedString.length))
        }
        
        if var maxWidth = fixedWidth ?? maxWidth {
            maxWidth -= 2 * padding.width
            maxWidth -= 2 * Self.drawingOffset.dx
            textContainer = .init(size: .init(width: maxWidth, height: CGFLOAT_MAX))
        }
        else {
            textContainer = .init(size: .init(width: CGFLOAT_MAX, height: CGFLOAT_MAX))
        }
        
        layoutManager = .init()
        layoutManager.addTextContainer(textContainer)
        
        textStorage = .init(attributedString: mutableAttributedString)
        textStorage.addLayoutManager(layoutManager)
        
        let textSize = layoutManager.usedRect(for: textContainer).size
        outputSize = CGSize(
            width: fixedWidth ?? textSize.width + 2 * padding.width + 2 * Self.drawingOffset.dx,
            height: fixedHeight ?? textSize.height + 2 * padding.height + 2 * Self.drawingOffset.dy
        )
        
        var containerSize = textSize
        if let fixedWidth {
            containerSize.width = fixedWidth - 2 * padding.width - 2 * Self.drawingOffset.dx
        }
//        if let fixedHeight {
//            containerSize.height = fixedHeight - 2 * padding.height - 2 * Self.drawingOffset.dy
//        }
        textContainer.size = containerSize
        
//        if let fixedWidth {
//            textContainer.size = CGSize(
//                width: fixedWidth - 2 * padding.width - 2 * Self.drawingOffset.dx,
//                height: textSize.height
//            )
//        } else {
//            textContainer.size = textSize // fit to content
//        }
    }
    
    
    //---------------
    // MARK: Private
    //---------------
    
    private static let drawingOffset = CGVector(dx: -5, dy: 0) // offset to remove white space at left/right
    
    private let textStorage: NSTextStorage
    private let textContainer: NSTextContainer
    private let layoutManager: NSLayoutManager
}

#endif
