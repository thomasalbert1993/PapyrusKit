#if canImport(PDFKit) && canImport(SwiftUI)

import Foundation
import PDFKit
import SwiftUI

/// An element for drawing a vector image on a PDF, kept as vector paths.
///
/// Two sources are supported:
/// - an SF Symbol, sized like text by a point size and a weight;
/// - an image from an asset catalog stored as vectors: an SVG or a PDF with
///   *Preserve Vector Data* checked.
///
/// A `UIImage` drawn into a PDF context is embedded as a bitmap, symbols and vector assets
/// included. `PDFVectorImage` draws through SwiftUI's `ImageRenderer` instead, which keeps
/// them resolution-independent.
///
/// `ImageRenderer` only runs on the main thread: when the PDF renders on another thread,
/// the measurement and the drawing synchronously hop to the main one. Don't render on a
/// background thread the main thread is waiting on.
///
public struct PDFVectorImage: Sendable {

    /// Where the image comes from.
    public enum Source: Sendable {

        /// An SF Symbol, by name.
        ///
        /// - Parameter name: The symbol name, as in `UIImage(systemName:)`.
        /// - Parameter pointSize: The symbol point size, like a font's.
        /// - Parameter weight: The symbol weight, like a font's.
        case symbol(_ name: String, pointSize: CGFloat, weight: Font.Weight = .regular)

        /// An image from an asset catalog, stored as vectors (SVG, or PDF with *Preserve
        /// Vector Data* checked).
        ///
        /// - Parameter name: The asset name, as in `UIImage(named:)`.
        /// - Parameter bundle: The bundle holding the asset catalog, the main bundle when `nil`.
        /// - Parameter size: The drawn size, the asset's own size when `nil`.
        case asset(_ name: String, bundle: Bundle? = nil, size: CGSize? = nil)
    }

    /// The image source.
    public let source: Source

    /// The color to draw the image in, `nil` for its own colors.
    ///
    /// A symbol without a color draws in black; an asset without a color keeps its
    /// original colors.
    public let color: UIColor?

    /// The drawn size, in points.
    public let outputSize: CGSize


    //--------------------
    // MARK: Initializers
    //--------------------

    /// Creates the image, `nil` when the source names no symbol or asset.
    ///
    /// - Parameter source: The image source.
    /// - Parameter color: The color to draw the image in, `nil` for its own colors.
    public init?(_ source: Source, color: UIColor? = nil) {
        switch source {
            case .symbol(let name, _, _):
                guard UIImage(systemName: name) != nil else { return nil }
            case .asset(let name, let bundle, _):
                guard UIImage(named: name, in: bundle, with: nil) != nil else { return nil }
        }

        self.source = source
        self.color = color
        self.outputSize = Self.onMainThread {
            var size = CGSize.zero
            Self.renderer(for: source, color: color).render { renderedSize, _ in
                size = renderedSize
            }
            return size
        }
    }


    //---------------
    // MARK: Drawing
    //---------------

    /// Makes a drawable element for the image.
    ///
    /// - Parameter origin: The image origin (relative to block).
    ///
    /// - Returns: The generated `PDFDrawableElement`.
    public func makeDrawableElement(at origin: CGPoint) -> PDFDrawableElement {
        .init(relativeFrame: .init(origin: origin, size: outputSize)) { context, offset in
            draw(at: origin.adding(vector: offset), in: context)
        }
    }

    /// Draws the image at a given point.
    ///
    /// - Parameter point: The image origin.
    /// - Parameter context: The `CGContext` to draw into.
    public func draw(at point: CGPoint, in context: CGContext) {
        let (source, color, outputSize) = (source, color, outputSize)
        nonisolated(unsafe) let context = context
        Self.onMainThread {
            Self.renderer(for: source, color: color).render { _, draw in
                // The renderer draws in a bottom-left origin space: flip the UIKit context
                // around the image frame.
                context.saveGState()
                context.translateBy(x: point.x, y: point.y + outputSize.height)
                context.scaleBy(x: 1, y: -1)
                draw(context)
                context.restoreGState()
            }
        }
    }


    //---------------
    // MARK: Private
    //---------------

    @MainActor
    private static func renderer(for source: Source, color: UIColor?) -> ImageRenderer<AnyView> {
        let view: AnyView
        switch source {
            case .symbol(let name, let pointSize, let weight):
                view = AnyView(
                    Image(systemName: name)
                        .font(.system(size: pointSize, weight: weight))
                        .foregroundStyle(color.map { Color(uiColor: $0) } ?? .black)
                )

            case .asset(let name, let bundle, let size):
                let image = Image(name, bundle: bundle)
                    .renderingMode(color == nil ? .original : .template)
                    .resizable()
                let naturalSize = UIImage(named: name, in: bundle, with: nil)?.size ?? .zero
                let frameSize = size ?? naturalSize
                view = AnyView(
                    image
                        .foregroundStyle(color.map { Color(uiColor: $0) } ?? .black)
                        .frame(width: frameSize.width, height: frameSize.height)
                )
        }
        return ImageRenderer(content: view)
    }

    /// Runs the work on the main thread, synchronously.
    private static func onMainThread<T: Sendable>(_ work: @MainActor () -> T) -> T {
        if Thread.isMainThread {
            return MainActor.assumeIsolated(work)
        }
        return DispatchQueue.main.sync(execute: work)
    }
}

#endif
