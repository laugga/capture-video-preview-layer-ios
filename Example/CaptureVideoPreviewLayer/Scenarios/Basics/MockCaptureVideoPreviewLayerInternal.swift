/*

 MockCaptureVideoPreviewLayerInternal.swift
 CaptureVideoPreviewLayerExample

 Copyright (c) 2016 Luis Laugga.
 Some rights reserved, all wrongs deserved.

*/

import AVFoundation
import CaptureVideoPreviewLayer
import UIKit

/// Feeds the preview layer with a generated still image instead of a capture session.
///
/// The Simulator has no capture device, so the example would show nothing there. This
/// stands in for the capture pipeline and lets the blur be seen without a camera.
final class MockCaptureVideoPreviewLayerInternal: LMCaptureVideoPreviewLayerInternal {

    private static let pixelBufferWidth = 1280
    private static let pixelBufferHeight = 720

    private var pixelBuffer: CVPixelBuffer?
    private var storedSampleBuffer: CMSampleBuffer?

    override var session: AVCaptureSession? {
        get { nil }
        set { /* Ignoring the session */ }
    }

    override var sampleBuffer: CMSampleBuffer? {

        // The same buffer is handed out on every call, the preview layer does not take
        // ownership of it and a new one per frame would be wasteful
        if let storedSampleBuffer {
            return storedSampleBuffer
        }

        guard let pixelBuffer = Self.makePixelBuffer() else {
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

    /// Draws a colour grid, so that the blur is easy to see without a capture device.
    private static func makePixelBuffer() -> CVPixelBuffer? {

        let attributes = [kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                          kCVPixelBufferMetalCompatibilityKey as String: true] as CFDictionary

        var pixelBuffer: CVPixelBuffer?
        let result = CVPixelBufferCreate(kCFAllocatorDefault,
                                         pixelBufferWidth,
                                         pixelBufferHeight,
                                         kCVPixelFormatType_32BGRA,
                                         attributes,
                                         &pixelBuffer)

        guard result == kCVReturnSuccess, let pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer),
                                      width: pixelBufferWidth,
                                      height: pixelBufferHeight,
                                      bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: bitmapInfo) else {
            return nil
        }

        let columns = 8
        let rows = 5
        let cellWidth = CGFloat(pixelBufferWidth) / CGFloat(columns)
        let cellHeight = CGFloat(pixelBufferHeight) / CGFloat(rows)

        for row in 0..<rows {
            for column in 0..<columns {
                let hue = CGFloat(row * columns + column) / CGFloat(rows * columns)
                let color = UIColor(hue: hue, saturation: 0.85, brightness: 0.95, alpha: 1.0)

                context.setFillColor(color.cgColor)
                context.fill(CGRect(x: CGFloat(column) * cellWidth + 8,
                                    y: CGFloat(row) * cellHeight + 8,
                                    width: cellWidth - 16,
                                    height: cellHeight - 16))
            }
        }

        return pixelBuffer
    }
}
