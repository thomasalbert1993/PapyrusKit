#if canImport(PDFKit)

import Foundation
import PDFKit

/// The main engine responsible for rendering a PDF document from a collection of `PDFSection` instances.
///
/// `PDFRenderer` handles the full rendering pipeline: pagination, multi-column layout,
/// headers, footers, and watermarks. It converts sections and their nested blocks into
/// a laid-out, multi-page `Data` output using `UIGraphicsPDFRenderer`.
///
/// The layout hierarchy is: `PDFSection` > `PDFBlock` > `PDFDrawableElement`.
/// The renderer lays out sections sequentially, dispatching their blocks across pages
/// and columns according to the provided `PDFLayout`.
///
public final class PDFRenderer {
    
    /// The DPI resolution.
    public static let dpi = 72
    
    
    //----------------
    // MARK: Metadata
    //----------------
    
    /// The author name to embbed in file's metadata.
    public var authorName: String?
    /// The website URL to embbed in file's metadata.
    public var website: String?
    
    
    //-------------------------
    // MARK: Layout & Sections
    //-------------------------
    
    /// The document layout details.
    public let layout: PDFLayout
    
    /// The PDF sections.
    public var sections = [PDFSection]()
    
    
    //-------------------------
    // MARK: Headers & Footers
    //-------------------------
    
    public enum HeaderStyle {
        case none
        case firstPage(
            height: CGFloat,
            renderer: (
                _ frame: CGRect
            ) -> PDFBlock
        )
        case allPages(
            height: CGFloat,
            renderer: (
                _ page: Int,
                _ nbPages: Int,
                _ frame: CGRect
            ) -> PDFBlock
        )
    }
    
    public enum FooterStyle {
        case none
        case lastPage(
            height: CGFloat,
            renderer: (
                _ frame: CGRect
            ) -> PDFBlock
        )
        case allPages(
            height: CGFloat,
            renderer: (
                _ page: Int,
                _ nbPages: Int,
                _ frame: CGRect
            ) -> PDFBlock
        )
    }
    
    /// The header style.
    public var headerStyle: HeaderStyle = .none
    
    /// The footer style.
    public var footerStyle: FooterStyle = .none
    
    
    //-----------------
    // MARK: Watermark
    //-----------------
    
    /// A watermark printed on all pages.
    public var watermark: String?
    
    /// The watermark color
    public var watermarkColor = UIColor.red.withAlphaComponent(0.2)
    
    /// The watermark font.
    public var watermarkFont = UIFont.systemFont(ofSize: 52, weight: .bold)
    
    
    //--------------------
    // MARK: Initializers
    //--------------------
    
    /// The default initializer.
    ///
    /// - Parameter layout: The document layout.
    public required init(layout: PDFLayout) {
        self.layout = layout
    }
    
    
    //---------------------------
    // MARK: Rendering Documents
    //---------------------------
    
    /// Rendering the PDF document.
    ///
    /// - Returns: The rendererd PDF data.
    public func render() throws -> Data {
        
        let rendererFormat = UIGraphicsPDFRendererFormat()
        rendererFormat.documentInfo = [
            kCGPDFContextCreator: authorName ?? "",
            kCGPDFContextAuthor: website ?? "",
        ] as [String:Any]
        
        let renderer = UIGraphicsPDFRenderer(
            bounds: .init(origin: .zero, size: layout.format.size(for: layout.orientation)),
            format: rendererFormat
        )
        
        let pagedBlocks = try renderPaginatedBlocks()
        runningHeaders = pagedBlocks.map { $0.first?.runningHeader }
        
        return renderer.pdfData { context in
            
            let nbPages = pagedBlocks.count
            for (page, blocks) in pagedBlocks.enumerated() {
                
                context.beginPage()
                
                // 1) Draw watermark
                
                if let watermark {
                    
                    let watermarkTextBox = PDFTextBox(
                        attributedString: .init(string: watermark, font: watermarkFont, color: watermarkColor),
                        maxWidth: 1000, // TODO: To calculate (but required for centering)
                        alignment: .center,
                        borderColor: watermarkColor,
                        borderThickness: 3,
                        cornerRadius: 20,
                        padding: .init(width: 15, height: 2),
                        renderer: self
                    )
                    
                    context.cgContext.saveGState()
                    let centerPoint = layout.contentFrame.center
                    context.cgContext.translateBy(x: centerPoint.x, y: centerPoint.y)
                    context.cgContext.rotate(by: -.pi/4)
                    context.cgContext.translateBy(x: -centerPoint.x, y: -centerPoint.y)
                    
                    let textOrigin = CGPoint(
                        x: centerPoint.x - watermarkTextBox.outputSize.width / 2,
                        y: centerPoint.y - watermarkTextBox.outputSize.height / 2
                    )
                    
                    watermarkTextBox.draw(at: textOrigin, in: context.cgContext)
                    
                    context.cgContext.restoreGState()
                }
                
                // 2) Draw header
                
                switch headerStyle {
                        
                    case .none:
                        break
                        
                    case .firstPage(let height, let renderer):
                        if page == 0 {
                            let headerFrame = layout.contentFrame.topRect(height: height)
                            renderer(headerFrame).draw(at: headerFrame.origin, in: context.cgContext)
                        }
                        
                    case .allPages(let height, let renderer):
                        let headerFrame = layout.contentFrame.topRect(height: height)
                            renderer(page, nbPages, headerFrame).draw(at: headerFrame.origin, in: context.cgContext)
                        }
                
                // 3) Draw blocks
                
                for (index, positionedBlock) in blocks.enumerated() {
                    positionedBlock.block.draw(
                        at: positionedBlock.origin,
                        in: context.cgContext,
                        info: .init(
                            page: page,
                            pageCount: nbPages,
                            isFirstBlockOnPage: index == 0,
                            isLastBlockOnPage: index == blocks.count - 1
                        )
                    )
                }
                
                // 4) Draw footer
                                
                switch footerStyle {
                        
                    case .none:
                        break
                        
                    case .lastPage(let height, let renderer):
                        if page == nbPages - 1 {
                            let footerFrame = layout.contentFrame.bottomRect(height: height)
                            renderer(footerFrame).draw(at: footerFrame.origin, in: context.cgContext)
                        }
                    
                    case .allPages(let height, let renderer):
                        let footerFrame = layout.contentFrame.bottomRect(height: height)
                        renderer(page, nbPages, footerFrame).draw(at: footerFrame.origin, in: context.cgContext)
                }
            }
        }
    }
    
    
    /// The running header in effect at the top of a page, to show in its header like a
    /// book's chapter title.
    ///
    /// It is the latest `PDFSection.runningHeader` set up to the section of the page's
    /// first block: a section starting further down the page only shows from the next one.
    /// Only meaningful while rendering, from the header and footer renderers.
    ///
    /// - Parameter page: The page index, from 0.
    ///
    /// - Returns: The running header, `nil` when no section set one yet.
    public func runningHeader(onPage page: Int) -> String? {
        runningHeaders.indices.contains(page) ? runningHeaders[page] : nil
    }


    //---------------
    // MARK: Private
    //---------------
    
    private struct PositionedBlock {
        let block: PDFBlock
        let origin: CGPoint
        /// The running header in effect for the block's section.
        let runningHeader: String?
    }

    /// The running header in effect at the top of each page, filled once paginated.
    private var runningHeaders = [String?]()
    
    private func renderPaginatedBlocks() throws -> [[PositionedBlock]] {
        
        var paginatedBlocks = [[PositionedBlock]]()
        var currentPageBlocks = [PositionedBlock]()
        
        var origin = layout.contentFrame.origin
        switch headerStyle {
            case .none:
                break
            case .firstPage(let height, _),
                     .allPages(let height, _):
                origin.y += height
        }
        
        var runningHeader: String?

        for (sectionIndex, section) in sections.enumerated() {

            if let sectionRunningHeader = section.runningHeader {
                runningHeader = sectionRunningHeader
            }
        
            if case .automatic(let topMargin) = section.position, !currentPageBlocks.isEmpty {
                origin.y += topMargin
            }
            
            let columnsSpacing = section.columnsSpacing
            let columnsWidth = layout.contentFrame.width / CGFloat(section.columns) - CGFloat(section.columns - 1) * columnsSpacing
            
            let blocks = try section.template.renderBlocks(maxWidth: columnsWidth, renderer: self)
            
            var sectionOrigin = origin
            var currentColumn = 0
            
            for (blockIndex, block) in blocks.enumerated() {
                
                var blockSize = block.size
                
                var fitMaxY = layout.contentFrame.maxY
                switch footerStyle {
                    case .none:
                        break
                    case .lastPage(let height, _):
                        fitMaxY -= height // ???
                    case .allPages(let height, _):
                        fitMaxY -= height
                }
                
                var shouldCreateNewPage = false
                var shouldCreateNewColumn = false
                if blockIndex == 0, sectionIndex > 0, case .newPage = section.position {
                    shouldCreateNewPage = true
                }
                else if origin.y + blockSize.height > fitMaxY {
                    shouldCreateNewColumn = true
                }
                else if block.prefersNotBeingLastBlock, blockIndex < (blocks.count - 1) {
                    let nextBlockHeight = blocks[blockIndex + 1].size.height
                    if origin.y + blockSize.height + nextBlockHeight > fitMaxY {
                        shouldCreateNewColumn = true
                    }
                }
                
                var block = block
                if block.clearsTopMarginWhenIsTopBlock, (blockIndex == 0 || shouldCreateNewPage || shouldCreateNewColumn) {
                    block.margins.top = .zero
                    blockSize = block.size // recalculate without top margin
                }
                
                if shouldCreateNewPage || shouldCreateNewColumn {
                    
                    if shouldCreateNewColumn, currentColumn < (section.columns - 1) {
                        
                        // New column
                        
                        currentColumn += 1
                        
                        origin = sectionOrigin
                        origin.x += (columnsWidth + columnsSpacing) * CGFloat(currentColumn)
                    }
                    else {
                        
                        // New page
                        
                        currentColumn = 0
                        
                        paginatedBlocks.append(currentPageBlocks)
                        currentPageBlocks = []
                        
                        origin = layout.contentFrame.origin
                        
                        switch headerStyle {
                            case .none, .firstPage:
                                break
                            case .allPages(let height, _):
                                origin.y += height
                        }
                        
                        sectionOrigin = origin
                    }
                }
                
                currentPageBlocks.append(PositionedBlock(block: block, origin: origin, runningHeader: runningHeader))
                
                origin.y += blockSize.height
            }
        }
        
        if !currentPageBlocks.isEmpty {
            paginatedBlocks.append(currentPageBlocks)
        }
        
        return paginatedBlocks
    }
}

extension CGFloat {
    
    /// Converting inches to dots (for PDF purposes).
    public static func inches(_ inches: Double, dpi: Int = PDFRenderer.dpi) -> CGFloat {
        inches * CGFloat(dpi)
    }
    
    /// Converting centimeters to dots (for PDF purposes).
    public static func centimeters(_ centimeters: Double, dpi: Int = PDFRenderer.dpi) -> CGFloat {
        centimeters / 2.54 * CGFloat(dpi)
    }
}

#endif
