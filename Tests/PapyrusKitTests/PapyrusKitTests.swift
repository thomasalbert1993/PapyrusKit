import Foundation
import PDFKit
import Testing
import UIKit
@testable import PapyrusKit

@MainActor
struct PDFVectorImageTests {

    /// A template drawing a single element at the top-left corner of the content frame.
    struct ElementTemplate: PDFTemplate {
        let element: PDFDrawableElement

        func renderBlocks(maxWidth: CGFloat, renderer: PDFRenderer) throws -> [PDFBlock] {
            [PDFBlock(elements: [element])]
        }
    }

    @Test("A symbol is measured from its point size") func symbolSize() throws {
        let small = try #require(PDFVectorImage(.symbol("square.fill", pointSize: 10)))
        let large = try #require(PDFVectorImage(.symbol("square.fill", pointSize: 40)))

        #expect(small.outputSize.width > 0)
        #expect(large.outputSize.width > small.outputSize.width * 3)
    }

    @Test("An asset is measured at its own size, or at the given one") func assetSize() throws {
        let natural = try #require(PDFVectorImage(.asset("Star", bundle: .module)))
        let sized = try #require(PDFVectorImage(.asset("Star", bundle: .module, size: CGSize(width: 50, height: 30))))

        #expect(natural.outputSize == CGSize(width: 24, height: 24))
        #expect(sized.outputSize == CGSize(width: 50, height: 30))
    }

    @Test("An unknown symbol or asset makes no image") func unknownSource() {
        #expect(PDFVectorImage(.symbol("not.a.symbol", pointSize: 10)) == nil)
        #expect(PDFVectorImage(.asset("Missing", bundle: .module)) == nil)
    }

    @Test("A symbol is drawn as vectors, in its color", arguments: [false, true])
    func symbolIsVector(offMainThread: Bool) async throws {
        let image = try #require(PDFVectorImage(.symbol("square.fill", pointSize: 60), color: .red))
        let data = try await render(image, offMainThread: offMainThread)

        #expect(bitmapImageCount(in: data) == 0)
        let center = try centerColor(of: image, in: data)
        #expect(center.red > 0.9 && center.green < 0.2 && center.blue < 0.2)
    }

    @Test("An SVG asset is drawn as vectors, in its own colors or tinted") func assetIsVector() async throws {
        let original = try #require(PDFVectorImage(.asset("Star", bundle: .module, size: CGSize(width: 120, height: 120))))
        let originalData = try await render(original, offMainThread: false)

        #expect(bitmapImageCount(in: originalData) == 0)
        let orange = try centerColor(of: original, in: originalData)
        #expect(orange.red > 0.9 && orange.green > 0.4 && orange.green < 0.8 && orange.blue < 0.2)

        let tinted = try #require(PDFVectorImage(.asset("Star", bundle: .module, size: CGSize(width: 120, height: 120)), color: .blue))
        let tintedData = try await render(tinted, offMainThread: false)

        #expect(bitmapImageCount(in: tintedData) == 0)
        let blue = try centerColor(of: tinted, in: tintedData)
        #expect(blue.blue > 0.9 && blue.red < 0.2)
    }


    //---------------
    // MARK: Helpers
    //---------------

    private let layout = PDFLayout.default

    /// Renders a one-page PDF with the image at the top-left of the content frame — on a
    /// background thread when asked, the drawing then hopping to the main one.
    private func render(_ image: PDFVectorImage, offMainThread: Bool) async throws -> Data {
        let layout = layout
        let element = image.makeDrawableElement(at: .zero)
        let template = ElementTemplate(element: element)
        let work: @Sendable () throws -> Data = {
            var renderer = PDFRenderer(layout: layout)
            renderer.sections = [PDFSection(template: template)]
            return try renderer.render()
        }
        if offMainThread {
            return try await Task.detached(operation: work).value
        }
        return try work()
    }

    /// The number of bitmap images embedded in the PDF.
    private func bitmapImageCount(in data: Data) -> Int {
        let pattern = Data("/Subtype /Image".utf8)
        var count = 0
        var range = data.startIndex..<data.endIndex
        while let found = data.range(of: pattern, in: range) {
            count += 1
            range = found.upperBound..<data.endIndex
        }
        return count
    }

    /// The color at the image center, rasterizing the first page at 2×.
    private func centerColor(of image: PDFVectorImage, in data: Data) throws -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let page = try #require(PDFKit.PDFDocument(data: data)?.page(at: 0))
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2
        let thumbnail = page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
        let cgImage = try #require(thumbnail.cgImage)

        let center = CGPoint(
            x: (layout.contentFrame.minX + image.outputSize.width / 2) * scale,
            y: (layout.contentFrame.minY + image.outputSize.height / 2) * scale
        )

        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        // Draws the thumbnail so that the sampled point lands on the single pixel.
        context.draw(cgImage, in: CGRect(
            x: -center.x,
            y: -(CGFloat(cgImage.height) - center.y),
            width: CGFloat(cgImage.width),
            height: CGFloat(cgImage.height)
        ))
        return (CGFloat(pixel[0]) / 255, CGFloat(pixel[1]) / 255, CGFloat(pixel[2]) / 255)
    }
}
