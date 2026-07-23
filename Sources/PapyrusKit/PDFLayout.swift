#if canImport(PDFKit)

import Foundation
import UIKit

/// The layout settings of a PDF document.
///
/// It's defined by an orientation (portrait vs. landscape), a format (A4, US Letter...),
/// and some margins.
///
public struct PDFLayout: Sendable {
    
    public enum Orientation: CaseIterable, Equatable, Sendable {
        case portrait
        case landscape
    }
    
    public enum Format: CaseIterable, Equatable, Sendable {
        case a4
        case usLetter
        
        /// Gets the corresponding size for a given orientation.
        ///
        /// - Parameter orientation: The document orientation.
        ///
        /// - Returns: The corresponding size.
        public func size(for orientation: Orientation) -> CGSize {
            switch orientation {
                
                case .portrait:
                    switch self {
                        case .a4:       .init(width: .centimeters(21), height: .centimeters(29.7))
                        case .usLetter: .init(width: .inches(8.5),     height: .inches(11))
                    }
                
                case .landscape:
                    switch self {
                        case .a4:       .init(width: .centimeters(29.7), height: .centimeters(21))
                        case .usLetter: .init(width: .inches(11),        height: .inches(8.5))
                    }
            }
        }
    }
    
    /// The document format.
    public var format: Format
    /// The document orientation.
    public var orientation: Orientation
    /// The document margins.
    public var margins: UIEdgeInsets
    
    /// The page bounds (in dots).
    public var bounds: CGRect {
        .init(origin: .zero, size: format.size(for: orientation))
    }
    
    public init(
        format: Format,
        orientation: Orientation,
        margins: UIEdgeInsets
    ) {
        self.format = format
        self.orientation = orientation
        self.margins = margins
    }
    
    /// The pages content frame (in dots).
    public var contentFrame: CGRect {
        let size = format.size(for: orientation)
        return .init(
            x: margins.left,
            y: margins.top,
            width: size.width - margins.left - margins.right,
            height: size.height - margins.top - margins.bottom
        )
    }
    
    /// The default layout.
    public static let `default` = PDFLayout(
        format: .a4,
        orientation: .portrait,
        margins: .init(
            top: .inches(0.5),
            left: .inches(0.5),
            bottom: .inches(0.5),
            right: .inches(0.5)
        )
    )
}

#endif
