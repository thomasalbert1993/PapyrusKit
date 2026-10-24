import Foundation
import PDFKit
import Testing
import UIKit
@testable import PapyrusKit

struct PaginationTests {

    /// Collects where each block is drawn, and the widths the template is asked for.
    final class Recorder: @unchecked Sendable {
        struct Entry {
            let origin: CGPoint
            let page: Int
            let pageCount: Int
        }
        var entries: [Entry] = []
        var widths: [CGFloat] = []
    }

    /// Blocks of the given heights, each recording where it is drawn.
    struct RecordingTemplate: PDFTemplate {
        let heights: [CGFloat]
        let recorder: Recorder

        func renderBlocks(maxWidth: CGFloat, renderer: PDFRenderer) throws -> [PDFBlock] {
            recorder.widths.append(maxWidth)
            return heights.map { height in
                PDFBlock(elements: [
                    PDFDrawableElement(relativeFrame: CGRect(x: 0, y: 0, width: maxWidth, height: height)) { [recorder] _, offset, info in
                        recorder.entries.append(.init(origin: CGPoint(x: offset.dx, y: offset.dy), page: info.page, pageCount: info.pageCount))
                    }
                ])
            }
        }
    }

    private let layout = PDFLayout.default
    private var content: CGRect { layout.contentFrame }

    private func render(_ sections: [PDFSection], configure: (PDFRenderer) -> Void = { _ in }) throws -> Data {
        let renderer = PDFRenderer(layout: layout)
        renderer.sections = sections
        configure(renderer)
        return try renderer.render()
    }

    private func isClose(_ a: CGPoint, _ b: CGPoint) -> Bool {
        abs(a.x - b.x) < 0.001 && abs(a.y - b.y) < 0.001
    }


    //---------------
    // MARK: Columns
    //---------------

    @Test("Columns share the content width, with the spacing between them") func columnsWidth() throws {
        let recorder = Recorder()
        let spacing: CGFloat = 20
        _ = try render([
            PDFSection(template: RecordingTemplate(heights: [content.height * 0.6, content.height * 0.6], recorder: recorder), columns: 2, columnsSpacing: spacing),
        ])

        let width = (content.width - spacing) / 2
        let widths = recorder.widths
        #expect(widths.count == 1 && abs(widths[0] - width) < 0.001, "columns \(widths) wide, expected \(width)")

        let origins = recorder.entries.map(\.origin)
        #expect(origins.count == 2)
        #expect(isClose(origins[0], content.origin))
        #expect(isClose(origins[1], CGPoint(x: content.minX + width + spacing, y: content.minY)), "second column at \(origins[1])")
    }

    @Test("A section after a multi-column one starts below its tallest column, at the left edge") func afterColumns() throws {
        let recorder = Recorder()
        let height = content.height
        _ = try render([
            // The first column holds the two first blocks, the second one the third.
            PDFSection(template: RecordingTemplate(heights: [height * 0.5, height * 0.4, height * 0.3], recorder: recorder), columns: 2),
            PDFSection(template: RecordingTemplate(heights: [50], recorder: recorder)),
        ])

        let entries = recorder.entries
        #expect(entries.count == 4)
        #expect(entries.map(\.page) == [0, 0, 0, 0])
        #expect(isClose(entries[3].origin, CGPoint(x: content.minX, y: content.minY + height * 0.9)), "next section at \(entries[3].origin)")
    }


    //--------------------
    // MARK: Blank pages
    //--------------------

    @Test("A block taller than a page opens no blank page before it") func oversizedFirstBlock() throws {
        let recorder = Recorder()
        _ = try render([PDFSection(template: RecordingTemplate(heights: [content.height * 1.5], recorder: recorder))])

        #expect(recorder.entries.map(\.page) == [0])
        #expect(recorder.entries.map(\.pageCount) == [1])
    }

    @Test("A block taller than a page goes to the next page, and only there") func oversizedNextBlock() throws {
        let recorder = Recorder()
        _ = try render([PDFSection(template: RecordingTemplate(heights: [100, content.height * 1.5, 50], recorder: recorder))])

        #expect(recorder.entries.map(\.page) == [0, 1, 2])
        #expect(recorder.entries.map(\.pageCount) == [3, 3, 3])
    }

    @Test("A new-page section after an empty one opens no blank page") func newPageAfterEmptySection() throws {
        let recorder = Recorder()
        _ = try render([
            PDFSection(template: RecordingTemplate(heights: [], recorder: recorder)),
            PDFSection(template: RecordingTemplate(heights: [100], recorder: recorder), position: .newPage),
        ])

        #expect(recorder.entries.map(\.page) == [0])
        #expect(recorder.entries.map(\.pageCount) == [1])
    }


    //------------------------
    // MARK: Last-page footer
    //------------------------

    @Test("A last-page footer leaves the earlier pages their full height") func lastPageFooterRoom() throws {
        let recorder = Recorder()
        let half = content.height * 0.48
        _ = try render([PDFSection(template: RecordingTemplate(heights: [half, half, half, half, 50], recorder: recorder))]) { renderer in
            renderer.footerStyle = .lastPage(height: 100) { _ in PDFBlock(elements: []) }
        }

        #expect(recorder.entries.map(\.page) == [0, 0, 1, 1, 2])
    }

    @Test("A last-page footer moves the content it would cover to a new page") func lastPageFooterOverlap() throws {
        let recorder = Recorder()
        let half = content.height * 0.48
        _ = try render([PDFSection(template: RecordingTemplate(heights: [half, half], recorder: recorder))]) { renderer in
            renderer.footerStyle = .lastPage(height: 100) { _ in PDFBlock(elements: []) }
        }

        let entries = recorder.entries
        #expect(entries.map(\.page) == [0, 1])
        let lastBottom = try #require(entries.last).origin.y + half
        #expect(lastBottom <= content.maxY - 100)
    }


    //----------------
    // MARK: Metadata
    //----------------

    @Test("The author and the website land in their own metadata fields") func metadata() throws {
        let data = try render([]) { renderer in
            renderer.authorName = "Jane Doe"
            renderer.website = "https://example.com"
        }
        let attributes = try #require(PDFKit.PDFDocument(data: data)?.documentAttributes)

        #expect(attributes[PDFDocumentAttribute.authorAttribute] as? String == "Jane Doe")
        #expect(attributes[PDFDocumentAttribute.creatorAttribute] as? String == "https://example.com")
    }


    //----------------------
    // MARK: Graphics state
    //----------------------

    @Test("An element's drawing settings don't leak into the next one") func graphicsStateIsolation() throws {
        let block = PDFBlock(elements: [
            .rect(frame: CGRect(x: 0, y: 0, width: 10, height: 10), fillColor: .red),
            // Fills without setting a color: the context's default black.
            PDFDrawableElement(relativeFrame: CGRect(x: 10, y: 0, width: 10, height: 10)) { context, offset in
                context.fill(CGRect(x: 10 + offset.dx, y: offset.dy, width: 10, height: 10))
            },
        ])

        var pixels = [UInt8](repeating: 0, count: 20 * 10 * 4)
        let context = try #require(CGContext(
            data: &pixels,
            width: 20,
            height: 10,
            bitsPerComponent: 8,
            bytesPerRow: 20 * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        block.draw(at: .zero, in: context)

        let index = (5 * 20 + 15) * 4
        #expect(pixels[index] < 50, "second element drawn in red \(pixels[index])")
    }
}
