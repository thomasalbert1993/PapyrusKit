import Foundation
import PDFKit
import Testing
import UIKit
@testable import PapyrusKit

struct PDFTextBoxTests {

    /// A template drawing a single element at the top-left corner of the content frame.
    struct ElementTemplate: PDFTemplate {
        let element: PDFDrawableElement

        func renderBlocks(maxWidth: CGFloat, renderer: PDFRenderer) throws -> [PDFBlock] {
            [PDFBlock(elements: [element])]
        }
    }

    @Test("A fixed-height box centers its text whatever its padding", arguments: [CGFloat(0), 20])
    func fixedHeightCentersText(verticalPadding: CGFloat) throws {
        let layout = PDFLayout.default
        let renderer = PDFRenderer(layout: layout)
        let box = PDFTextBox(
            attributedString: .init(string: "HH", font: .systemFont(ofSize: 30), color: .red),
            fixedHeight: 120,
            padding: .init(width: 10, height: verticalPadding)
        )
        renderer.sections = [PDFSection(template: ElementTemplate(element: box.makeDrawableElement(at: .zero)))]
        let data = try renderer.render()

        let textRows = try redRows(in: data, columns: layout.contentFrame.minX...(layout.contentFrame.minX + box.outputSize.width))
        let textCenter = try #require(textRows.map { ($0.lowerBound + $0.upperBound) / 2 })
        let boxCenter = layout.contentFrame.minY + box.outputSize.height / 2

        // Capitals sit a little above the line box's middle (the descender room is below
        // them): a few points of slack, far from the padding the centering used to add.
        #expect(abs(textCenter - boxCenter) < 5, "text centered at \(textCenter), box at \(boxCenter)")
    }

    @Test("A box is as wide as its text plus its padding, with no room around the lines") func widthIsTextPlusPadding() {
        let string = AttributedString(string: "Hello, world", font: .systemFont(ofSize: 14))
        let textWidth = NSAttributedString(string).size().width
        let box = PDFTextBox(attributedString: string, padding: .init(width: 12, height: 0))

        #expect(abs(box.outputSize.width - (textWidth + 24)) < 0.5, "box \(box.outputSize.width) wide for a \(textWidth) text")
    }

    @Test("Underline and strikethrough are set on the string") func underlineAndStrikethrough() {
        let string = NSAttributedString(AttributedString(string: "Struck", font: .systemFont(ofSize: 14), underlined: true, strikethrough: true))
        let attributes = string.attributes(at: 0, effectiveRange: nil)

        #expect(attributes[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue)
        #expect(attributes[.strikethroughStyle] as? Int == NSUnderlineStyle.single.rawValue)
    }


    //---------------
    // MARK: Helpers
    //---------------

    /// The vertical extent, in page points, of the red pixels across columns of the first page.
    private func redRows(in data: Data, columns: ClosedRange<CGFloat>) throws -> ClosedRange<CGFloat>? {
        let page = try #require(PDFKit.PDFDocument(data: data)?.page(at: 0))
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 4
        let width = Int(bounds.width * scale), height = Int(bounds.height * scale)

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.drawPDFPage(try #require(page.pageRef))

        // The bitmap's first row in memory is the page's top.
        let xs = Int(columns.lowerBound * scale)...Int(columns.upperBound * scale)
        let rows = (0..<height).filter { row in
            xs.contains { px in
                let index = (row * width + px) * 4
                return pixels[index] > 200 && pixels[index + 1] < 80 && pixels[index + 2] < 80
            }
        }
        guard let first = rows.first, let last = rows.last else { return nil }
        return CGFloat(first) / scale...CGFloat(last) / scale
    }
}
