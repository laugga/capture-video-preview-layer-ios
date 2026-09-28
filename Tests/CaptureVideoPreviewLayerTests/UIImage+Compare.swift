/*

 UIImage+Compare.swift
 CaptureVideoPreviewLayer Tests

 Copyright (c) 2016 Luis Laugga.
 Some rights reserved, all wrongs deserved.

 Permission is hereby granted, free of charge, to any person obtaining a copy of
 this software and associated documentation files (the "Software"), to deal in
 the Software without restriction, including without limitation the rights to
 use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
 the Software, and to permit persons to whom the Software is furnished to do so,
 subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
 FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
 COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
 IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/

import UIKit

extension UIImage {

    /// Renders a layer into an image, the way the layer would be drawn on screen.
    static func image(from layer: CALayer) -> UIImage {

        precondition(layer.bounds.width > 0, "Layer width is zero")
        precondition(layer.bounds.height > 0, "Layer height is zero")

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false

        return UIGraphicsImageRenderer(bounds: layer.bounds, format: format).image { context in
            layer.layoutIfNeeded()
            layer.render(in: context.cgContext)
        }
    }

    /// Compares each pixel colour with the ones of another image.
    ///
    /// - Returns: 0 when every compared pixel is the same colour, 1 when they are all
    ///   completely different colours.
    func similarity(with image: UIImage) -> CGFloat {

        guard let lhs = pixelData(), let rhs = image.pixelData() else {
            return 1.0
        }

        // Both images are walked linearly, so a comparison is only meaningful when
        // they have the same dimensions
        let count = min(lhs.count, rhs.count) / 4

        guard count > 0 else {
            return 1.0
        }

        var sum: CGFloat = 0

        for pixel in 0..<count {
            let offset = pixel * 4

            // 0 they are the same rgb colours, 1 they are totally different colours
            let red = abs(Int(lhs[offset]) - Int(rhs[offset]))
            let green = abs(Int(lhs[offset + 1]) - Int(rhs[offset + 1]))
            let blue = abs(Int(lhs[offset + 2]) - Int(rhs[offset + 2]))

            sum += CGFloat(red + green + blue) / (3.0 * 255.0)
        }

        return sum / CGFloat(count)
    }

    private func pixelData() -> [UInt8]? {

        guard let cgImage else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4

        var data = [UInt8](repeating: 0, count: bytesPerRow * height)

        data.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: bytesPerRow,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return
            }

            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        return data
    }
}
