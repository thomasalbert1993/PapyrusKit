import Foundation
import Testing
import UIKit
@testable import PapyrusKit

struct RunningHeaderTests {

    /// A template stacking `count` blocks of a given height.
    struct BlocksTemplate: PDFTemplate {
        let count: Int
        let height: CGFloat

        func renderBlocks(maxWidth: CGFloat, renderer: PDFRenderer) throws -> [PDFBlock] {
            (0..<count).map { _ in
                PDFBlock(elements: [.rect(frame: CGRect(x: 0, y: 0, width: maxWidth, height: height), fillColor: .gray)])
            }
        }
    }

    /// Renders the sections, returning the running header the header renderer read on each page.
    private func headers(for sections: [PDFSection]) throws -> [String?] {
        let renderer = PDFRenderer(layout: .default)
        var headers = [String?]()
        renderer.headerStyle = .allPages(height: 20) { [unowned renderer] page, _, _ in
            headers.append(renderer.runningHeader(onPage: page))
            return PDFBlock(elements: [])
        }
        renderer.sections = sections
        _ = try renderer.render()
        return headers
    }

    @Test("A section's running header carries over its pages and the sections leaving it nil") func carriesOver() throws {
        let pageHeight = PDFLayout.default.contentFrame.height

        let headers = try headers(for: [
            // Two pages' worth of blocks.
            PDFSection(template: BlocksTemplate(count: 4, height: pageHeight / 2 - 20), runningHeader: "One"),
            // No running header of its own: "One" stays in effect.
            PDFSection(template: BlocksTemplate(count: 1, height: pageHeight - 40), position: .newPage),
            PDFSection(template: BlocksTemplate(count: 1, height: 50), position: .newPage, runningHeader: "Two"),
        ])

        #expect(headers == ["One", "One", "One", "Two"])
    }

    @Test("A section starting down a page sets the running header from the next page") func startingMidPage() throws {
        let pageHeight = PDFLayout.default.contentFrame.height

        let headers = try headers(for: [
            PDFSection(template: BlocksTemplate(count: 1, height: 100), runningHeader: "One"),
            PDFSection(template: BlocksTemplate(count: 2, height: pageHeight / 2), runningHeader: "Two"),
        ])

        #expect(headers == ["One", "Two"])
    }

    @Test("No running header before a section sets one") func noneSet() throws {
        let headers = try headers(for: [
            PDFSection(template: BlocksTemplate(count: 1, height: 50)),
            PDFSection(template: BlocksTemplate(count: 1, height: 50), position: .newPage, runningHeader: "Two"),
        ])

        #expect(headers == [nil, "Two"])
    }
}
