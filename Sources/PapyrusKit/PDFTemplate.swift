import Foundation

#if canImport(PDFKit)

/// A protocol for designing reusable templates to render in PDF documents.
///
public protocol PDFTemplate {
    
    /// Rendering the PDF blocks with a given max width.
    ///
    /// - Parameter maxWidth: The blocks maximum width (including margins).
    /// - Parameter renderer: The related renderer.
    ///
    /// - Returns: The rendered blocks.
    func renderBlocks(maxWidth: CGFloat, renderer: PDFRenderer) throws -> [PDFBlock]
}

#endif
