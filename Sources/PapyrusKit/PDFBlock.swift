#if canImport(PDFKit)

import Foundation
import PDFKit

/// A block containing some `PDFDrawableElement` instances.
///
/// The `PDFBlock` instances are wrapped into `PDFSection` instances.
///
/// Their origin is `[0;_]` relative to their parent section (inside section margins),
/// and their size is defined by their content.
///
/// Blocks are always drawn one above the other, you can not draw two blocks side by side (in a same section).
///
public struct PDFBlock {
    
    /// The block contents.
    public var elements: [PDFDrawableElement]
    
    /// The block own margins.
    public var margins: UIEdgeInsets
    
    /// Indicates wether the top margin should be cleared when the block is drawn
    /// at the top of a column/section.
    public var clearsTopMarginWhenIsTopBlock: Bool
    
    /// Indicates wether the block should be drawn on a new column/page
    /// if it's the last one fitting space.
    public var prefersNotBeingLastBlock: Bool
    
    public init(
        elements: [PDFDrawableElement],
        margins: UIEdgeInsets = .zero,
        clearsTopMarginWhenIsTopBlock: Bool = false,
        prefersNotBeingLastBlock: Bool = false
    ) {
        self.elements = elements
        self.margins = margins
        self.clearsTopMarginWhenIsTopBlock = clearsTopMarginWhenIsTopBlock
        self.prefersNotBeingLastBlock = prefersNotBeingLastBlock
    }
    
    /// Getting the block rendering size, including margins.
    ///
    /// - Parameter dpi: The DPI resolution.
    ///
    /// - Returns: The block size (in dots).
    public var size: CGSize {
        var size = CGSize()
        for element in elements {
            size.width = max(size.width, element.relativeFrame.maxX)
            size.height = max(size.height, element.relativeFrame.maxY)
        }
        return .init(
            width: size.width + margins.left + margins.right,
            height: size.height + margins.top + margins.bottom
        )
    }
    
    /// Drawing the block at a given position.
    ///
    /// - Parameter origin: The absolute origin.
    /// - Parameter context: The `CGContext` to draw into.
    /// - Parameter renderer: The related renderer.
    public func draw(at origin: CGPoint, in context: CGContext) {
        for element in elements {
            var elementOrigin = element.relativeFrame.origin
            elementOrigin.x += origin.x + margins.left
            elementOrigin.y += origin.y + margins.top
            element.draw(at: elementOrigin, in: context)
        }
    }
}

#endif
