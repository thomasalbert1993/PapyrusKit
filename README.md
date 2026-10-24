# PapyrusKit

A lightweight Swift package for building rich, multi-page PDF documents on iOS and iPadOS.

PapyrusKit gives you a small, composable layout system on top of `PDFKit` and Core Graphics. You describe your document as a stack of reusable **templates**, and the renderer takes care of the tedious parts: pagination, multi-column flow, headers, footers, watermarks, and text measurement.

## Features

- **Automatic pagination** — content flows across as many pages as needed.
- **Composable layout hierarchy** — `PDFSection` › `PDFBlock` › `PDFDrawableElement`.
- **Reusable templates** — encapsulate document fragments behind the `PDFTemplate` protocol.
- **Multi-column sections** — split a section into any number of columns with configurable spacing.
- **Rich text rendering** — `PDFTextBox` handles attributed strings, wrapping, alignment, padding, borders, and backgrounds.
- **Headers & footers** — first-page, last-page, or every-page variants with page numbering and running headers.
- **Watermarks** — diagonal, styleable watermark stamped on every page.
- **Convenient units** — build layouts in inches or centimeters, with A4 and US Letter formats out of the box.
- **Vector images** — SF Symbols and SVG assets drawn as vector paths, never as bitmaps.
- **Primitive drawables** — lines, rects, and ellipses for anything the built-ins don't cover.

## Requirements

- Swift 6.3+
- iOS 17+ or iPadOS 17+. macOS and Mac Catalyst are not supported.

## Installation

Add PapyrusKit to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/thomasalbert1993/PapyrusKit.git", from: "0.4.0")
]
```

Then add it to your target's dependencies:

```swift
.target(
    name: "YourTarget",
    dependencies: ["PapyrusKit"]
)
```

Or, in Xcode, use **File › Add Package Dependencies…** and paste the repository URL.

## Concepts

PapyrusKit organizes a document into three nested layers:

| Layer | Type | Role |
| --- | --- | --- |
| Section | `PDFSection` | Top-level unit. Stacks vertically, spans the full content width, and can be split into columns. |
| Block | `PDFBlock` | A group of elements that is kept together and flowed across pages/columns as a unit. |
| Element | `PDFDrawableElement` | The lowest level — the actual drawing (text, line, rect, ellipse, or custom Core Graphics). |

Sections are produced by **templates** (`PDFTemplate`), which generate their blocks for a given column width. The `PDFRenderer` walks your sections, asks each template for its blocks, and lays them out across pages and columns.

## Usage

### 1. Define a template

A template conforms to `PDFTemplate` and returns the blocks that make up a fragment of your document:

```swift
import PapyrusKit
import UIKit

struct TitleTemplate: PDFTemplate {

    let title: String

    func renderBlocks(maxWidth: CGFloat, renderer: PDFRenderer) throws -> [PDFBlock] {

        let textBox = PDFTextBox(
            attributedString: .init(
                string: title,
                font: .systemFont(ofSize: 24, weight: .bold)
            ),
            maxWidth: maxWidth,
            alignment: .center
        )

        let block = PDFBlock(
            elements: [textBox.makeDrawableElement(at: .zero)],
            margins: .init(top: 0, left: 0, bottom: 20, right: 0)
        )

        return [block]
    }
}
```

### 2. Configure the renderer and render

```swift
let layout = PDFLayout(
    format: .a4,
    orientation: .portrait,
    margins: .init(
        top: .inches(0.5),
        left: .inches(0.5),
        bottom: .inches(0.5),
        right: .inches(0.5)
    )
)

let renderer = PDFRenderer(layout: layout)
renderer.authorName = "Jane Doe"
renderer.website = "https://example.com"

renderer.sections = [
    PDFSection(template: TitleTemplate(title: "Invoice #1234")),
    PDFSection(template: BodyTemplate(), columns: 2, columnsSpacing: .centimeters(1)),
]

let data = try renderer.render()
try data.write(to: outputURL)
```

`PDFLayout.default` is also available as a ready-made A4, portrait, half-inch-margin layout.

### 3. Add headers and footers

Headers and footers are driven by closures that return a `PDFBlock` for a given frame. Choose where they appear:

```swift
renderer.headerStyle = .firstPage(height: 60) { frame in
    // Build a header block sized to `frame`.
    HeaderTemplate().makeBlock(in: frame)
}

renderer.footerStyle = .allPages(height: 30) { page, pageCount, frame in
    let text = PDFTextBox(
        attributedString: .init(
            string: "Page \(page + 1) / \(pageCount)",
            font: .systemFont(ofSize: 10)
        ),
        alignment: .right
    )
    return PDFBlock(elements: [text.makeDrawableElement(at: frame.origin)])
}
```

`HeaderStyle` and `FooterStyle` each offer `.none`, a single-page variant (`.firstPage` / `.lastPage`), and an `.allPages` variant that receives the current page index and total page count. A `.lastPage` footer only takes room on the last page: the content it would cover moves to a new page.

#### Running headers

Like a book showing its chapter title at the top of each page, a section can set a running header that the page headers show:

```swift
renderer.sections = [
    PDFSection(template: ChapterTemplate(title: "Act I"), position: .newPage, runningHeader: "Act I"),
    PDFSection(template: ScenesTemplate()), // no running header of its own: "Act I" stays in effect
    PDFSection(template: ChapterTemplate(title: "Act II"), position: .newPage, runningHeader: "Act II"),
]

renderer.headerStyle = .allPages(height: 30) { [unowned renderer] page, pageCount, frame in
    let title = renderer.runningHeader(onPage: page) ?? "My document"
    // Build the header block with `title`.
}
```

A page shows the running header in effect at its top: the latest one set up to the section of its first block. A section starting further down a page shows from the next one.

### 4. Add a watermark

```swift
renderer.watermark = "CONFIDENTIAL"
renderer.watermarkColor = UIColor.red.withAlphaComponent(0.2)
renderer.watermarkFont = .systemFont(ofSize: 52, weight: .bold)
```

The watermark is drawn diagonally, centered on every page.

## Text rendering

`PDFTextBox` is the workhorse for text. It measures and lays out an `AttributedString`, and exposes styling for the surrounding box:

```swift
let box = PDFTextBox(
    attributedString: .init(string: "Hello, world", font: .systemFont(ofSize: 14)),
    maxWidth: 300,
    alignment: .left,
    backgroundColor: .systemGray6,
    borderColor: .separator,
    borderThickness: 1,
    cornerRadius: 8,
    padding: .init(width: 12, height: 8)
)
```

A convenience `AttributedString` initializer makes styling quick, underline and strikethrough included:

```swift
let string = AttributedString(
    string: "Underlined title",
    font: .boldSystemFont(ofSize: 18),
    color: .label,
    underlined: true,
    strikethrough: false
)
```

## Vector images

`PDFVectorImage` draws an SF Symbol, or an image from an asset catalog stored as vectors (an SVG, or a PDF with *Preserve Vector Data* checked), as vector paths. A `UIImage` drawn into a PDF context is embedded as a bitmap; this goes through SwiftUI's `ImageRenderer`, which keeps the image resolution-independent.

```swift
// An SF Symbol, sized like text
let warning = PDFVectorImage(.symbol("exclamationmark.triangle.fill", pointSize: 10, weight: .semibold), color: .black)

// An SVG from an asset catalog, at its own size and in its own colors
let logo = PDFVectorImage(.asset("Logo"))

// The same, at a given size and tinted
let badge = PDFVectorImage(.asset("Logo", bundle: .module, size: CGSize(width: 40, height: 20)), color: .systemBlue)

if let warning {
    elements.append(warning.makeDrawableElement(at: .init(x: 0, y: 0)))
    // `warning.outputSize` is the drawn size, to lay out what follows.
}
```

The initializer returns `nil` when the source names no symbol or asset. `ImageRenderer` only runs on the main thread: rendering a PDF on another thread hops to the main one for each vector image, so don't render on a background thread the main thread is waiting on.

## Primitive drawables

For custom drawing, `PDFDrawableElement` provides ready-made factories:

```swift
// A horizontal rule
.line(from: .init(x: 0, y: 0), to: .init(x: 200, y: 0), thickness: 1, color: .gray)

// A rounded, filled rectangle
.rect(frame: box, cornerRadius: 6, fillColor: .systemBlue, borderColor: .clear)

// An ellipse
.ellipse(frame: box, fillColor: .systemGreen)
```

You can also build a fully custom element from a raw Core Graphics closure. It draws between a save and a restore of the graphics state, so its settings don't leak into the next elements:

```swift
PDFDrawableElement(relativeFrame: frame) { context, offset in
    // Draw anything into `context`, translated by `offset`.
}
```

An element can also learn where it lands once paginated — its page, and whether its block opens or closes that page — to adapt to page breaks, like a bar running down several blocks that should stop short at the bottom of a page:

```swift
PDFDrawableElement(relativeFrame: frame) { context, offset, info in
    let bottom = info.isLastBlockOnPage ? contentBottom : contentBottom + gap
    // info.page, info.pageCount, info.isFirstBlockOnPage are available too.
}
```

## Units & geometry helpers

PapyrusKit adds convenience helpers for working in print units and Core Graphics geometry:

```swift
CGFloat.inches(1)        // 72 dots (at 72 DPI)
CGFloat.centimeters(2.54) // 72 dots

frame.center             // center point
frame.topRect(height: 60)    // crop from the top
frame.bottomRect(height: 30) // crop from the bottom
point.adding(vector: offset) // translate a point
```

## Layout notes

- Sections stack vertically — you cannot place two sections side by side.
- Within a section, blocks stack vertically and flow into the next column (then the next page) when they no longer fit.
- A section following a multi-column one starts at the left edge, below its tallest column.
- Use `PDFSection.Position.newPage` to force a section to start on a fresh page.
- A block taller than a page is placed at the top of a page and overflows it: blocks are never split.
- `PDFBlock.prefersNotBeingLastBlock` avoids orphaning a block at the bottom of a column, and `clearsTopMarginWhenIsTopBlock` drops the top margin when a block lands at the top of a column or page.

## License

PapyrusKit is available under the MIT license. See the [LICENSE](LICENSE) file for
details.
