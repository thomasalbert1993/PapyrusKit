# Migrating from PapyrusKit 0.4 to 1.0

This guide covers the changes between 0.4.0 and 1.0.0. Update your package dependency:

```swift
.package(url: "https://github.com/thomasalbert1993/PapyrusKit.git", from: "1.0.0")
```

The changes fall in two groups:

- **Source-breaking changes.** The compiler flags them. Fix them with the steps below.
- **Behavior changes.** They compile as before but the PDF can look different. Check
  your documents visually afterwards.

## Source-breaking changes

### 1. `PDFRenderer` is a struct

`PDFRenderer` used to be a `final class`. It is now a `Sendable` struct, so it has value
semantics.

Declare it with `var` instead of `let`:

```swift
// Before
let renderer = PDFRenderer(layout: layout)
renderer.sections = [...]

// After
var renderer = PDFRenderer(layout: layout)
renderer.sections = [...]
```

A function configuring a renderer it is passed no longer compiles, since the parameter is
a constant copy. Make the parameter `inout`, or return the configured renderer:

```swift
// Before
func configureHeader(of renderer: PDFRenderer) {
    renderer.headerStyle = ...
}
configureHeader(of: renderer)

// After
func configureHeader(of renderer: inout PDFRenderer) {
    renderer.headerStyle = ...
}
configureHeader(of: &renderer)
```

> [!WARNING]
> A renderer stored somewhere else is a separate copy, and the compiler won't flag it.
> Configuring a renderer kept in a property, a collection, or another object no longer
> changes the one you render. The same goes for a template keeping the renderer it was
> given: it holds a copy, taken at the start of rendering.

The initializer is no longer `required`. That only matters if you referred to it through
a metatype, as in `type(of: renderer).init(layout:)`.

A renderer can now be rendered from another task:

```swift
let data = try await Task.detached { [renderer] in try renderer.render() }.value
```

### 2. Header and footer closures take a `PageInfo`

Every header and footer variant now takes the same closure, of type
`PDFRenderer.PageBlockRenderer`:

```swift
@Sendable (_ page: PDFRenderer.PageInfo, _ frame: CGRect) -> PDFBlock
```

`PageInfo` has three properties: `page`, the index from 0, `pageCount`, and
`runningHeader`.

| Variant | Before | After |
| --- | --- | --- |
| `HeaderStyle.firstPage` | `{ frame in ... }` | `{ page, frame in ... }` |
| `HeaderStyle.allPages` | `{ page, nbPages, frame in ... }` | `{ page, frame in ... }` |
| `FooterStyle.lastPage` | `{ frame in ... }` | `{ page, frame in ... }` |
| `FooterStyle.allPages` | `{ page, nbPages, frame in ... }` | `{ page, frame in ... }` |

```swift
// Before
renderer.footerStyle = .allPages(height: 30) { page, nbPages, frame in
    let text = PDFTextBox(
        attributedString: .init(string: "Page \(page + 1) / \(nbPages)", font: .systemFont(ofSize: 10)),
        alignment: .right,
        renderer: renderer
    )
    return PDFBlock(elements: [text.makeDrawableElement(at: .zero)])
}

// After
renderer.footerStyle = .allPages(height: 30) { page, frame in
    let text = PDFTextBox(
        attributedString: .init(string: "Page \(page.page + 1) / \(page.pageCount)", font: .systemFont(ofSize: 10)),
        alignment: .right
    )
    return PDFBlock(elements: [text.makeDrawableElement(at: .zero)])
}
```

For the single-page variants, ignore the page with `_` if you don't need it:
`.firstPage(height: 60) { _, frame in ... }`.

### 3. `runningHeader(onPage:)` is gone

Read the running header from the `PageInfo` the closure receives. The
`[unowned renderer]` capture is no longer needed.

```swift
// Before
renderer.headerStyle = .allPages(height: 30) { [unowned renderer] page, pageCount, frame in
    let title = renderer.runningHeader(onPage: page) ?? "My document"
    ...
}

// After
renderer.headerStyle = .allPages(height: 30) { page, frame in
    let title = page.runningHeader ?? "My document"
    ...
}
```

`PDFSection.runningHeader` itself is unchanged, and so is the rule picking a page's
running header.

### 4. `PDFTextBox` lost its `renderer:` and `strikethrough:` parameters

Remove the `renderer:` argument. It was never used.

```swift
// Before
PDFTextBox(attributedString: string, maxWidth: maxWidth, renderer: renderer)

// After
PDFTextBox(attributedString: string, maxWidth: maxWidth)
```

Strikethrough moved to the convenience `AttributedString` initializer, next to underline:

```swift
// Before
PDFTextBox(attributedString: .init(string: "Old price", font: font), strikethrough: true, renderer: renderer)

// After
PDFTextBox(attributedString: .init(string: "Old price", font: font, strikethrough: true))
```

For an `AttributedString` built another way, set the strikethrough on the string
yourself, for instance through `NSAttributedString.Key.strikethroughStyle`.

### 5. Templates, elements, and their closures are `Sendable`

These types are now `Sendable`:

- `PDFDrawableElement`
- `PDFBlock`
- `PDFSection`
- `PDFTextBox`
- `PDFRenderer` and its header and footer styles

`PDFTemplate` now refines `Sendable`. Element, header, and footer closures are `@Sendable`.

**Templates.** A struct whose stored properties are all `Sendable` needs no change. For
other templates:

- **Template classes.** Make them `final` with immutable `let` properties of `Sendable`
  types. As a last resort, mark them `@unchecked Sendable` if you guarantee their safety
  yourself.
- **Properties of non-`Sendable` types.** Prefer a `Sendable` equivalent, such as
  `AttributedString` instead of `NSAttributedString`, or a value copied out of a model
  object.

**Closures.** A `@Sendable` closure can't capture a mutable local variable, nor a
non-`Sendable` value. This mostly hits two cases.

The first is a header or footer closure capturing `self` from a view model or a view
controller. Copy what it needs into local constants first:

```swift
// Before
renderer.headerStyle = .allPages(height: 30) { page, nbPages, frame in
    self.makeHeader(title: self.document.title, in: frame)
}

// After
let title = document.title
renderer.headerStyle = .allPages(height: 30) { page, frame in
    HeaderTemplate.makeHeader(title: title, in: frame)
}
```

The second is a custom element mutating a captured variable, often in tests. Collect into
a `Sendable` reference type instead:

```swift
// Before
var drawn = false
let element = PDFDrawableElement(relativeFrame: frame) { _, _ in drawn = true }

// After
final class Flag: @unchecked Sendable { var isSet = false }
let drawn = Flag()
let element = PDFDrawableElement(relativeFrame: frame) { _, _ in drawn.isSet = true }
```

## Behavior changes

These compile unchanged. Render your documents before and after, and compare them.

- **Columns are wider.** Each column used to lose the whole spacing, which left an extra
  margin on the right. Columns now share the content width minus the spacing between
  them, and the last one ends at the right margin. Layouts tuned to the old, narrower
  width will reflow.
- **Sections after a multi-column section move.** The next section used to start below
  the last column, at that column's left edge. It could then overlap a taller first
  column. It now starts at the left margin, below the tallest column.
- **No more blank pages.** A block taller than the page used to produce an empty page
  before it. It now goes at the top of a page and overflows it. A `.newPage` section
  after an empty section no longer opens an empty page either. Drop any workaround that
  removed these pages.
- **A last-page footer no longer shrinks every page.** Only the last page leaves room for
  a `.lastPage` footer. Earlier pages hold more content, so page breaks and page counts
  can change. If the last page's content would run under the footer, that content moves
  to a new page.
- **Metadata fields are no longer swapped.** `authorName` now goes to the PDF's Author
  field, and `website` to its Creator field. If you swapped the values to compensate,
  swap them back.
- **Drawing settings no longer leak between elements.** Each element draws between a
  save and a restore of the graphics state. A custom element that relied on a color,
  line width, or transform left by a previous element now starts from the defaults,
  black fill and stroke included. Set what it needs explicitly.
- **Header and footer elements get their real page.** An element using
  `PDFDrawableElement.DrawingInfo` inside a header or footer used to always see page 0
  of 1. It now sees its page and the page count. Both `isFirstBlockOnPage` and
  `isLastBlockOnPage` are `true` there.
- **Long watermarks wrap at the content diagonal.** The wrapping width used to be a fixed
  1000 points. Short watermarks look the same.
- **Fixed-height boxes report their last glyph where it is drawn.**
  `PDFTextBox.lastGlyphBottomRightPosition(whenDrawingAt:)` now includes the vertical
  centering of a box with a `fixedHeight`. Anything positioned after such a box moves
  down to match the drawn text.

Text measurement doesn't change. Removing the internal -5 point offset of `PDFTextBox`
gives the same sizes and glyph positions as before.

## Platforms

PapyrusKit supports iOS and iPadOS 17 and later. macOS and Mac Catalyst were never
built nor tested, and are no longer advertised. Nothing changes for iOS projects.

## Checklist

1. Point the package dependency at `from: "1.0.0"`.
2. Change `let renderer = PDFRenderer(...)` to `var`, and make the functions configuring
   a renderer take it `inout`.
3. Update every `headerStyle` and `footerStyle` closure to `{ page, frame in ... }`.
4. Replace `renderer.runningHeader(onPage: page)` with `page.runningHeader`.
5. Remove the `renderer:` arguments of `PDFTextBox`, and move `strikethrough:` to the
   `AttributedString` initializer.
6. Fix the `Sendable` errors in templates and closures.
7. Render your documents and compare them with the previous version, using the list of
   behavior changes above.

These searches find most of the places to update:

```sh
grep -rn "PDFRenderer(layout" --include=*.swift .
grep -rn "headerStyle\|footerStyle" --include=*.swift .
grep -rn "runningHeader(onPage" --include=*.swift .
grep -rn "renderer: renderer\|renderer: self\|strikethrough:" --include=*.swift .
grep -rn ": PDFTemplate" --include=*.swift .
```
