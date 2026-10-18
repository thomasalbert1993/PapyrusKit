import Foundation
import Testing
import UIKit
@testable import PapyrusKit

struct DrawingInfoTests {

    /// Collects what each element is told at drawing time.
    final class Recorder: @unchecked Sendable {
        var infos: [PDFDrawableElement.DrawingInfo] = []
    }

    /// `count` blocks of a given height, each recording its drawing info.
    struct RecordingTemplate: PDFTemplate {
        let count: Int
        let height: CGFloat
        let recorder: Recorder

        func renderBlocks(maxWidth: CGFloat, renderer: PDFRenderer) throws -> [PDFBlock] {
            (0..<count).map { _ in
                PDFBlock(elements: [
                    PDFDrawableElement(relativeFrame: CGRect(x: 0, y: 0, width: maxWidth, height: height)) { _, _, info in
                        recorder.infos.append(info)
                    }
                ])
            }
        }
    }

    @Test("Elements learn their page and whether their block opens or closes it") func elementsLearnTheirPlace() throws {
        let layout = PDFLayout.default
        let recorder = Recorder()
        let renderer = PDFRenderer(layout: layout)
        // Two blocks fill a page, the third goes to the next.
        renderer.sections = [PDFSection(template: RecordingTemplate(count: 3, height: layout.contentFrame.height / 2 - 1, recorder: recorder))]
        _ = try renderer.render()

        #expect(recorder.infos.map(\.page) == [0, 0, 1])
        #expect(recorder.infos.map(\.pageCount) == [2, 2, 2])
        #expect(recorder.infos.map(\.isFirstBlockOnPage) == [true, false, true])
        #expect(recorder.infos.map(\.isLastBlockOnPage) == [false, true, true])
    }

    @Test("The two-argument renderer still works") func legacyRenderer() throws {
        let renderer = PDFRenderer(layout: .default)
        var drawn = false
        let element = PDFDrawableElement(relativeFrame: CGRect(x: 0, y: 0, width: 10, height: 10)) { _, _ in drawn = true }
        renderer.sections = [PDFSection(template: RunningHeaderTests.BlocksTemplate(count: 0, height: 0))]
        element.draw(at: .zero, in: CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!)
        #expect(drawn)
    }
}
