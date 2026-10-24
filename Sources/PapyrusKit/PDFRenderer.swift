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

    /// The author name to embed in the file's metadata.
    public var authorName: String?
    /// The website URL to embed in the file's metadata, as its creator.
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
        /// A footer on the last page only. Only that page leaves room for it, the content
        /// it would cover moving to a new page.
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
    /// - Returns: The rendered PDF data.
    public func render() throws -> Data {

        let rendererFormat = UIGraphicsPDFRendererFormat()
        rendererFormat.documentInfo = [
            kCGPDFContextAuthor: authorName ?? "",
            kCGPDFContextCreator: website ?? "",
        ] as [String:Any]

        let renderer = UIGraphicsPDFRenderer(
            bounds: layout.bounds,
            format: rendererFormat
        )

        let pagedBlocks = try paginate()
        runningHeaders = pagedBlocks.map { $0.first?.runningHeader }

        return renderer.pdfData { context in

            let pageCount = pagedBlocks.count
            for (page, blocks) in pagedBlocks.enumerated() {

                context.beginPage()

                // A header or footer block is the only one of its area.
                let areaInfo = PDFDrawableElement.DrawingInfo(page: page, pageCount: pageCount, isFirstBlockOnPage: true, isLastBlockOnPage: true)

                // 1) Draw watermark

                if let watermark {
                    drawWatermark(watermark, in: context.cgContext)
                }

                // 2) Draw header

                switch headerStyle {
                    case .none:
                        break
                    case .firstPage(let height, let renderer):
                        if page == 0 {
                            let headerFrame = layout.contentFrame.topRect(height: height)
                            renderer(headerFrame).draw(at: headerFrame.origin, in: context.cgContext, info: areaInfo)
                        }
                    case .allPages(let height, let renderer):
                        let headerFrame = layout.contentFrame.topRect(height: height)
                        renderer(page, pageCount, headerFrame).draw(at: headerFrame.origin, in: context.cgContext, info: areaInfo)
                }

                // 3) Draw blocks

                for (index, positionedBlock) in blocks.enumerated() {
                    positionedBlock.block.draw(
                        at: positionedBlock.origin,
                        in: context.cgContext,
                        info: .init(
                            page: page,
                            pageCount: pageCount,
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
                        if page == pageCount - 1 {
                            let footerFrame = layout.contentFrame.bottomRect(height: height)
                            renderer(footerFrame).draw(at: footerFrame.origin, in: context.cgContext, info: areaInfo)
                        }
                    case .allPages(let height, let renderer):
                        let footerFrame = layout.contentFrame.bottomRect(height: height)
                        renderer(page, pageCount, footerFrame).draw(at: footerFrame.origin, in: context.cgContext, info: areaInfo)
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

    /// Draws the watermark diagonally, centered on the content frame.
    private func drawWatermark(_ watermark: String, in context: CGContext) {

        let contentFrame = layout.contentFrame
        let watermarkTextBox = PDFTextBox(
            attributedString: .init(string: watermark, font: watermarkFont, color: watermarkColor),
            // The diagonal is the longest line fitting the content frame once rotated.
            maxWidth: hypot(contentFrame.width, contentFrame.height),
            alignment: .center,
            borderColor: watermarkColor,
            borderThickness: 3,
            cornerRadius: 20,
            padding: .init(width: 15, height: 2)
        )

        context.saveGState()
        let centerPoint = contentFrame.center
        context.translateBy(x: centerPoint.x, y: centerPoint.y)
        context.rotate(by: -.pi/4)
        context.translateBy(x: -centerPoint.x, y: -centerPoint.y)

        let textOrigin = CGPoint(
            x: centerPoint.x - watermarkTextBox.outputSize.width / 2,
            y: centerPoint.y - watermarkTextBox.outputSize.height / 2
        )

        watermarkTextBox.draw(at: textOrigin, in: context)

        context.restoreGState()
    }

    /// The width of each column of a section.
    private func columnsWidth(of section: PDFSection) -> CGFloat {
        let columns = CGFloat(max(1, section.columns))
        return (layout.contentFrame.width - (columns - 1) * section.columnsSpacing) / columns
    }

    /// The height the header takes on a page.
    private func headerHeight(onPage page: Int) -> CGFloat {
        switch headerStyle {
            case .none:
                0
            case .firstPage(let height, _):
                page == 0 ? height : 0
            case .allPages(let height, _):
                height
        }
    }

    /// The height the footer takes on a page.
    ///
    /// - Parameter lastPageFooterFrom: The first page leaving room for a last-page footer,
    ///   `nil` for none.
    private func footerHeight(onPage page: Int, lastPageFooterFrom: Int?) -> CGFloat {
        switch footerStyle {
            case .none:
                0
            case .lastPage(let height, _):
                lastPageFooterFrom.map { page >= $0 } == true ? height : 0
            case .allPages(let height, _):
                height
        }
    }

    /// Lays out the sections' blocks across pages and columns.
    private func paginate() throws -> [[PositionedBlock]] {

        // The templates are asked for their blocks once, whatever the pagination passes.
        let sectionsBlocks = try sections.map { section in
            try section.template.renderBlocks(maxWidth: columnsWidth(of: section), renderer: self)
        }

        // Which page is the last is only known once paginated: a first pass leaves no room
        // for a last-page footer. If its last page's content would run under the footer, a
        // second pass leaves room for it from that page on: the earlier pages lay out the
        // same, and the content the footer would cover moves to a new page.
        let pages = paginate(sectionsBlocks, lastPageFooterFrom: nil)
        if case .lastPage(let height, _) = footerStyle,
           let lastPage = pages.last,
           let contentBottom = lastPage.map({ $0.origin.y + $0.block.size.height }).max(),
           contentBottom > layout.contentFrame.maxY - height
        {
            return paginate(sectionsBlocks, lastPageFooterFrom: pages.count - 1)
        }
        return pages
    }

    private func paginate(_ sectionsBlocks: [[PDFBlock]], lastPageFooterFrom: Int?) -> [[PositionedBlock]] {

        let contentFrame = layout.contentFrame

        var pages = [[PositionedBlock]]()
        var currentPage = [PositionedBlock]()

        func pageTop() -> CGFloat {
            contentFrame.minY + headerHeight(onPage: pages.count)
        }
        func pageBottom() -> CGFloat {
            contentFrame.maxY - footerHeight(onPage: pages.count, lastPageFooterFrom: lastPageFooterFrom)
        }

        var origin = CGPoint(x: contentFrame.minX, y: pageTop())
        var runningHeader: String?

        for (section, blocks) in zip(sections, sectionsBlocks) {

            if let sectionRunningHeader = section.runningHeader {
                runningHeader = sectionRunningHeader
            }

            guard !blocks.isEmpty else { continue }

            let columnsWidth = columnsWidth(of: section)
            let columns = max(1, section.columns)

            // The section's top on the current page, where its columns start.
            var sectionTop = origin.y
            // The bottom of the section's tallest column on the current page.
            var sectionBottom = origin.y
            var column = 0
            var columnHasBlocks = false

            func startNewPage() {
                pages.append(currentPage)
                currentPage = []
                origin = CGPoint(x: contentFrame.minX, y: pageTop())
                sectionTop = origin.y
                sectionBottom = origin.y
                column = 0
                columnHasBlocks = false
            }

            switch section.position {
                case .newPage:
                    if !currentPage.isEmpty {
                        startNewPage()
                    }
                case .automatic(let topMargin):
                    if !currentPage.isEmpty {
                        origin.y += topMargin
                        sectionTop = origin.y
                        sectionBottom = origin.y
                    }
            }

            for (blockIndex, block) in blocks.enumerated() {

                // Moves to the next column, then the next page, until the block fits or
                // moving on can't give it more room.
                while true {

                    var block = block
                    if block.clearsTopMarginWhenIsTopBlock, !columnHasBlocks {
                        block.margins.top = .zero
                    }
                    let blockHeight = block.size.height
                    let bottom = pageBottom()

                    var fits = origin.y + blockHeight <= bottom
                    if fits, block.prefersNotBeingLastBlock, blockIndex < blocks.count - 1 {
                        fits = origin.y + blockHeight + blocks[blockIndex + 1].size.height <= bottom
                    }

                    if !fits, columnHasBlocks, column < columns - 1 {
                        // New column
                        column += 1
                        columnHasBlocks = false
                        origin = CGPoint(x: contentFrame.minX + (columnsWidth + section.columnsSpacing) * CGFloat(column), y: sectionTop)
                    }
                    else if !fits, origin.y > pageTop() {
                        // New page: the column doesn't start at the top of the page, a new
                        // one gives more room.
                        startNewPage()
                    }
                    else {
                        // The block fits, or nothing gives it more room: it is placed here,
                        // overflowing if it must, rather than leaving a blank page.
                        currentPage.append(PositionedBlock(block: block, origin: origin, runningHeader: runningHeader))
                        origin.y += blockHeight
                        sectionBottom = max(sectionBottom, origin.y)
                        columnHasBlocks = true
                        break
                    }
                }
            }

            // The next section starts at the left edge, below the tallest column.
            origin = CGPoint(x: contentFrame.minX, y: sectionBottom)
        }

        if !currentPage.isEmpty {
            pages.append(currentPage)
        }

        return pages
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
