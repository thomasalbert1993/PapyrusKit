import Foundation

extension CGRect {
    
    /// The center point.
    public var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
    
    /// The top left point.
    public var topLeft: CGPoint {
        CGPoint(x: minX, y: minY)
    }
    
    /// The top right point.
    public var topRight: CGPoint {
        CGPoint(x: maxX, y: minY)
    }
    
    /// The bottom left point.
    public var bottomLeft: CGPoint {
        CGPoint(x: minX, y: maxY)
    }
    
    /// The bottom right point.
    public var bottomRight: CGPoint {
        CGPoint(x: maxX, y: maxY)
    }
    
    /// Translates the rect by a given vector.
    ///
    /// - Parameter vector: The translating vector.
    ///
    /// - Returns: The translated rect.
    public func offsetBy(vector: CGVector) -> CGRect {
        offsetBy(dx: vector.dx, dy: vector.dy)
    }
    
    /// Crops the rect from top, with a given height.
    ///
    /// - Parameter height: The output height.
    ///
    /// - Returns: The cropped rect.
    public func topRect(height: CGFloat) -> CGRect {
        var rect = self
        rect.size.height = height
        return rect
    }
    
    /// Crops the rect from bottom, with a given height.
    ///
    /// - Parameter height: The output height.
    ///
    /// - Returns: The cropped rect.
    public func bottomRect(height: CGFloat) -> CGRect {
        var rect = self
        rect.origin.y = rect.maxY - height
        rect.size.height = height
        return rect
    }
}

extension CGPoint {
    
    /// Translates the point by a given vector.
    ///
    /// - Parameter vector: The translating vector.
    public mutating func add(vector: CGVector) {
        x += vector.dx
        y += vector.dy
    }

    /// Gets the equivalent point translated by a given vector.
    ///
    /// - Parameter vector: The translating vector.
    ///
    /// - Returns: The translated point.
    public func adding(vector: CGVector) -> CGPoint {
        var point = self
        point.add(vector: vector)
        return point
    }

    /// Multiplies the point coordinate by a given factor.
    ///
    /// - Parameter value: The value to multiply the coordinate by.
    public mutating func multiply(by value: CGFloat) {
        x *= value
        y *= value
    }
    
    /// Gets the equivalent point with coordinate multiplied by a given factor.
    ///
    /// - Parameter value: The value to multiply the coordinate by.
    public func multiplied(by value: CGFloat) -> CGPoint {
        var point = self
        point.multiply(by: value)
        return point
    }
}
