/*

 MockLMCaptureVideoPreviewLayerInternal.swift
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

import AVFoundation
import UIKit

@testable import CaptureVideoPreviewLayer

/// Stands in for the capture pipeline and feeds the preview layer with a still image.
final class MockLMCaptureVideoPreviewLayerInternal: LMCaptureVideoPreviewLayerInternal {

    var sampleBufferImage: UIImage?

    private var pixelBuffer: CVPixelBuffer?
    private var storedSampleBuffer: CMSampleBuffer?

    override var session: AVCaptureSession? {
        get { nil }
        set { /* Ignoring the session */ }
    }

    override var sampleBuffer: CMSampleBuffer? {

        // The same buffer is handed out on every call, the preview layer does not take
        // ownership of it
        if let storedSampleBuffer {
            return storedSampleBuffer
        }

        guard let image = sampleBufferImage?.cgImage,
              let pixelBuffer = Self.pixelBuffer(from: image) else {
            return nil
        }

        self.pixelBuffer = pixelBuffer

        var formatDescription: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                     imageBuffer: pixelBuffer,
                                                     formatDescriptionOut: &formatDescription)

        guard let formatDescription else {
            return nil
        }

        var timingInfo = CMSampleTimingInfo.invalid
        var sampleBuffer: CMSampleBuffer?

        CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                           imageBuffer: pixelBuffer,
                                           dataReady: true,
                                           makeDataReadyCallback: nil,
                                           refcon: nil,
                                           formatDescription: formatDescription,
                                           sampleTiming: &timingInfo,
                                           sampleBufferOut: &sampleBuffer)

        storedSampleBuffer = sampleBuffer

        return sampleBuffer
    }

    func simulateCaptureSessionDidStartRunningNotification() {
        delegate?.captureVideoPreviewLayerInternal(self, sessionDidStartRunning: nil)
    }

    func simulateCaptureSessionDidStopRunningNotification() {
        delegate?.captureVideoPreviewLayerInternal(self, sessionDidStopRunning: nil)
    }

    /// Draws the image into a pixel buffer with CoreGraphics, and not with a CIContext.
    /// A CIContext render is GPU backed and does not guarantee the write landed before
    /// the pixel buffer is wrapped in a MTLTexture and sampled, which made consecutive
    /// renders of the same image differ.
    private static func pixelBuffer(from image: CGImage) -> CVPixelBuffer? {

        let width = image.width
        let height = image.height

        let attributes = [kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                          kCVPixelBufferMetalCompatibilityKey as String: true] as CFDictionary

        var pixelBuffer: CVPixelBuffer?
        let result = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attributes, &pixelBuffer)

        guard result == kCVReturnSuccess, let pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer),
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: bitmapInfo) else {
            return nil
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        return pixelBuffer
    }
}
