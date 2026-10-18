#if canImport(PDFKit)

import Foundation
import PDFKit

/// A drawable element defined by a rendering closure and a relative frame.
/// This is the lowest layout level and contains the drawing itself.
///
/// The `PDFDrawableElement` instances are wrapped into `PDFBlock` instances.
///
public struct PDFDrawableElement {

    /// Where the element is being drawn: only known at drawing time, once the blocks are
    /// paginated. Lets an element adapt to a page break — a bar running down several
    /// blocks can stop short on a page's last block and start again on the next page's
    /// first.
    public struct DrawingInfo: Sendable {
        /// The page index, from 0.
        public let page: Int
        /// The number of pages.
        public let pageCount: Int
        /// Whether the element's block is the first one on its page.
        public let isFirstBlockOnPage: Bool
        /// Whether the element's block is the last one on its page.
        public let isLastBlockOnPage: Bool

        public init(page: Int, pageCount: Int, isFirstBlockOnPage: Bool, isLastBlockOnPage: Bool) {
            self.page = page
            self.pageCount = pageCount
            self.isFirstBlockOnPage = isFirstBlockOnPage
            self.isLastBlockOnPage = isLastBlockOnPage
        }

        /// A single page holding a single block — what a block drawn on its own gets.
        public static let standalone = DrawingInfo(page: 0, pageCount: 1, isFirstBlockOnPage: true, isLastBlockOnPage: true)
    }
    
    /// The element frame, relative to it's parent `PDFBlock`.
    ///
    /// The parent block's own margin are not taken into account so origin `[0;0]`
    /// refers to the upper left inner point inside margins.
    public let relativeFrame: CGRect
    
    /// The rendering closure.
    ///
    /// - Parameter context: The `CGContext` to draw into.
    /// - Parameter offset: The relative to absolute position offset.
    /// - Parameter info: Where the element is being drawn (page, position on the page).
    public let renderer: (
        _ context: CGContext,
        _ offset: CGVector,
        _ info: DrawingInfo
    ) -> Void
    
    public init(
        relativeFrame: CGRect,
        renderer: @escaping (_ context: CGContext, _ offset: CGVector) -> Void
    ) {
        self.relativeFrame = relativeFrame
        self.renderer = { context, offset, _ in renderer(context, offset) }
    }

    /// An element whose drawing depends on where it lands once paginated.
    ///
    /// - Parameter relativeFrame: The element frame, relative to its block.
    /// - Parameter renderer: The rendering closure, given the page and the block's
    ///   position on it along with the context and the offset.
    public init(
        relativeFrame: CGRect,
        renderer: @escaping (_ context: CGContext, _ offset: CGVector, _ info: DrawingInfo) -> Void
    ) {
        self.relativeFrame = relativeFrame
        self.renderer = renderer
    }
    
    /// Drawing content at a given point.
    ///
    /// - Parameter origin: The absolute origin, already offsetted by `relatedFrame` origin.
    /// - Parameter context: The `CGContext` to draw into.
    /// - Parameter info: Where the element is being drawn.
    func draw(at origin: CGPoint, in context: CGContext, info: DrawingInfo = .standalone) {
        renderer(context, .init(
            dx: origin.x - relativeFrame.origin.x,
            dy: origin.y - relativeFrame.origin.y
        ), info)
    }
}

extension PDFDrawableElement {
    
    //-------------------------------
    // MARK: Basic Drawable Elements
    //-------------------------------
    
    /// Generating a drawable line.
    ///
    /// - Parameter startPoint: The line start point (relative to block).
    /// - Parameter endPoint: The line end point (relative to block).
    /// - Parameter thickness: The line thickness.
    /// - Parameter lineCap: The line cap style.
    /// - Parameter color: The line color.
    ///
    /// - Returns: The generated `DrawableElement`.
    public static func line(
        from startPoint: CGPoint,
        to endPoint: CGPoint,
        thickness: CGFloat,
        lineCap: CGLineCap = .butt,
        color: UIColor = .black)
        -> Self
    {
        let frame = CGRect(x: startPoint.x, y: startPoint.y, width: endPoint.x - startPoint.x, height: endPoint.y - startPoint.y)
        return Self.init(relativeFrame: frame) { context, offset in
            context.move(to: startPoint.adding(vector: offset))
            context.addLine(to: endPoint.adding(vector: offset))
            context.setLineWidth(thickness)
            context.setLineCap(lineCap)
            context.setStrokeColor(color.cgColor)
            context.strokePath()
        }
    }
    
    /// Generating a drawable rect.
    ///
    /// - Parameter frame: The rect frame (relative to block).
    /// - Parameter cornerRadius: The rect corner radius.
    /// - Parameter fillColor: The fill color.
    /// - Parameter borderColor: The border color.
    /// - Parameter borderThickness: The border thickness.
    ///
    /// - Returns: The generated `DrawableElement`.
    public static func rect(
        frame: CGRect,
        cornerRadius: CGFloat = 0,
        fillColor: UIColor? = nil,
        borderColor: UIColor = .black,
        borderThickness: CGFloat = 0)
        -> Self
    {
        Self.init(relativeFrame: frame) { context, offset in
            
            if let fillColor {
                context.setFillColor(fillColor.cgColor)
            }
            
            if borderThickness > 0 {
                context.setStrokeColor(borderColor.cgColor)
                context.setLineWidth(borderThickness)
            }
            
            context.addPath(UIBezierPath(roundedRect: frame.offsetBy(vector: offset), cornerRadius: cornerRadius).cgPath)
            
            if fillColor != nil {
                if borderThickness > 0 {
                    context.drawPath(using: .fillStroke)
                } else {
                    context.drawPath(using: .fill)
                }
            }
            else if !borderThickness.isZero {
                context.drawPath(using: .stroke)
            }
        }
    }
    
    /// Generarting a drawable ellipse.
    ///
    /// - Parameter frame: The ellipse frame (relative to block).
    /// - Parameter fillColor: The fill color.
    /// - Parameter borderColor: The border color.
    /// - Parameter borderThickness: The border thickness.
    ///
    /// - Returns: The generated `DrawableElement`.
    public static func ellipse(
        frame: CGRect,
        fillColor: UIColor? = nil,
        borderColor: UIColor = .black,
        borderThickness: CGFloat = 0)
        -> Self
    {
        Self.init(relativeFrame: frame) { context, offset in
            
            if let fillColor {
                context.setFillColor(fillColor.cgColor)
            }
            
            if borderThickness > 0 {
                context.setStrokeColor(borderColor.cgColor)
                context.setLineWidth(borderThickness)
            }
            
            context.addPath(UIBezierPath(ovalIn: frame.offsetBy(vector: offset)).cgPath)
            
            if fillColor != nil {
                if borderThickness > 0 {
                    context.drawPath(using: .fillStroke)
                } else {
                    context.drawPath(using: .fill)
                }
            }
            else if !borderThickness.isZero {
                context.drawPath(using: .stroke)
            }
        }
    }
}

#endif
