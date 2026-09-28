/*

 LMCaptureVideoPreviewLayerInternal.swift
 CaptureVideoPreviewLayer

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

/// Informs the delegate object about state changes in the capture pipeline.
///
/// The delegate is always called on the main queue.
public protocol LMCaptureVideoPreviewLayerInternalDelegate: AnyObject {

    func captureVideoPreviewLayerInternal(_ internalPipeline: LMCaptureVideoPreviewLayerInternal,
                                          sessionDidStopRunning session: AVCaptureSession?)

    func captureVideoPreviewLayerInternal(_ internalPipeline: LMCaptureVideoPreviewLayerInternal,
                                          sessionDidStartRunning session: AVCaptureSession?)
}

/// The capture side of the preview layer.
///
/// It adds an `AVCaptureVideoDataOutput` to the session, or hijacks the one already
/// there, and keeps the most recent sample buffers in a small circular array for the
/// renderer to pick up.
///
/// It is open so that it can be replaced by a stand-in that feeds the preview layer
/// without a capture device, which is what the tests and the example do.
open class LMCaptureVideoPreviewLayerInternal: NSObject {

    private static let sampleBuffersSize = 2

    /// The AVCaptureSession instance being previewed by the receiver.
    open var session: AVCaptureSession? {
        didSet {
            sessionDidChange(from: oldValue)
        }
    }

    /// The sample buffer being currently displayed.
    open var sampleBuffer: CMSampleBuffer? {
        lock.lock()
        defer { lock.unlock() }

        // Check if the circular array is not empty
        guard headIndex != tailIndex else {
            return nil
        }

        // Remove an existing sample buffer from the head
        let sampleBuffer = sampleBuffers[headIndex]

        // Move head +1
        headIndex = (headIndex + 1) % Self.sampleBuffersSize

        return sampleBuffer
    }

    /// YES if the session is running. NO for all other possible states:
    /// RuntimeError, Interrupted, Stopped.
    open var sessionIsRunning: Bool {
        session?.isRunning ?? false
    }

    open weak var delegate: LMCaptureVideoPreviewLayerInternalDelegate?

    // AVCaptureVideoDataOutput and delegate queue
    private var videoDataOutput: AVCaptureVideoDataOutput?
    private lazy var videoDataOutputSampleBufferDelegateQueue: DispatchQueue = {
        // In a multi-threaded producer consumer system it's generally a good idea to
        // make sure that producers do not get starved of CPU time by their consumers.
        // We start with VideoDataOutput frames on a high priority queue, and
        // downstream consumers use default priority queues.
        DispatchQueue(label: "com.laugga.LMCaptureVideoPreviewLayerInternal.videoDataOutputSampleBufferDelegateQueue",
                      qos: .userInitiated)
    }()

    // Circular array used to keep the sample buffers
    private let lock = NSLock()
    private var headIndex = 0
    private var tailIndex = 0
    private var sampleBuffers = [CMSampleBuffer?](repeating: nil, count: sampleBuffersSize)

    // Hijacked AVCaptureVideoDataOutput
    private weak var hijackedSampleBufferDelegate: AVCaptureVideoDataOutputSampleBufferDelegate?
    private var hijackedSampleBufferDelegateQueue: DispatchQueue?

    public override init() {
        super.init()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - AVCaptureSession

    private func sessionDidChange(from oldSession: AVCaptureSession?) {

        if let oldSession {
            // Stop observing the old session
            NotificationCenter.default.removeObserver(self, name: nil, object: oldSession)
        }

        guard let session else {
            return
        }

        // Set the session's AVCaptureVideoDataOutput
        let videoDataOutput = makeVideoDataOutput()

        if session.canAddOutput(videoDataOutput) {
            log.debug("Added AVCaptureVideoDataOutput to AVCaptureSession")
            session.addOutput(videoDataOutput)
            configure(videoDataOutput)
            self.videoDataOutput = videoDataOutput
        } else {
            // TODO improve this. After setSession the hijackedSession will prevent canAddOutput...
            log.debug("Can NOT add AVCaptureVideoDataOutput to AVCaptureSession")
            hijackSessionVideoDataOutput()
        }

        // Observe for specific notifications related with the session
        for name in [AVCaptureSession.wasInterruptedNotification,
                     AVCaptureSession.runtimeErrorNotification,
                     AVCaptureSession.didStopRunningNotification,
                     AVCaptureSession.didStartRunningNotification,
                     AVCaptureSession.interruptionEndedNotification] {
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(sessionDidPostNotification(_:)),
                                                   name: name,
                                                   object: session)
        }
    }

    private func hijackSessionVideoDataOutput() {

        log.debug("Hijacking current AVCaptureVideoDataOutput of AVCaptureSession")

        // Look for an instance of AVCaptureVideoDataOutput in session's outputs
        guard let currentVideoDataOutput = session?.outputs.compactMap({ $0 as? AVCaptureVideoDataOutput }).first else {
            return
        }

        // Copy a reference of current delegate and queue
        hijackedSampleBufferDelegate = currentVideoDataOutput.sampleBufferDelegate
        hijackedSampleBufferDelegateQueue = currentVideoDataOutput.sampleBufferCallbackQueue

        configure(currentVideoDataOutput)

        videoDataOutput = currentVideoDataOutput
    }

    // MARK: - AVCaptureSession notifications

    @objc private func sessionDidPostNotification(_ notification: Notification) {

        // AVCaptureSession posts these on whichever thread called startRunning() or
        // stopRunning(), which is a background queue since both block. The delegate
        // changes layers and draws, so it has to be called on the main queue.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.sessionDidPostNotification(notification)
            }
            return
        }

        switch notification.name {
        case AVCaptureSession.wasInterruptedNotification,
             AVCaptureSession.runtimeErrorNotification,
             AVCaptureSession.didStopRunningNotification:
            delegate?.captureVideoPreviewLayerInternal(self, sessionDidStopRunning: session)
        default:
            delegate?.captureVideoPreviewLayerInternal(self, sessionDidStartRunning: session)
        }
    }

    // MARK: - AVCaptureVideoDataOutput

    private func makeVideoDataOutput() -> AVCaptureVideoDataOutput {
        videoDataOutput ?? AVCaptureVideoDataOutput()
    }

    private func configure(_ videoDataOutput: AVCaptureVideoDataOutput) {

        // We want BGRA, both CoreGraphics and Metal work well with 'BGRA'
        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]

        // Discard if the data output queue is blocked
        videoDataOutput.alwaysDiscardsLateVideoFrames = true

        // Set the video data output delegate
        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputSampleBufferDelegateQueue)

        // Enable the video data output
        videoDataOutput.connection(with: .video)?.isEnabled = true
    }

    // MARK: - Ping-pong buffering for the video data output sample buffers

    private func add(_ newSampleBuffer: CMSampleBuffer) {
        lock.lock()
        defer { lock.unlock() }

        // Add the new sample buffer to the tail
        sampleBuffers[tailIndex] = newSampleBuffer

        // Move tail +1
        tailIndex = (tailIndex + 1) % Self.sampleBuffersSize

        // As a circular array we make sure old unused sample buffers are discarded by
        // moving head forwards +1
        if tailIndex == headIndex {
            headIndex = (tailIndex + 1) % Self.sampleBuffersSize
        }
    }

    open func flushSampleBuffer() {
        lock.lock()
        defer { lock.unlock() }

        sampleBuffers = [CMSampleBuffer?](repeating: nil, count: Self.sampleBuffersSize)
        headIndex = 0
        tailIndex = 0
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension LMCaptureVideoPreviewLayerInternal: AVCaptureVideoDataOutputSampleBufferDelegate {

    public func captureOutput(_ output: AVCaptureOutput,
                              didOutput sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {

        // Add the sample buffer to the circular array
        add(sampleBuffer)

        // Was the AVCaptureVideoDataOutput hijacked?
        guard let hijackedSampleBufferDelegate,
              let hijackedSampleBufferDelegateQueue else {
            return
        }

        hijackedSampleBufferDelegateQueue.async {
            // Forward the delegate method to the hijacked sample buffer delegate
            hijackedSampleBufferDelegate.captureOutput?(output, didOutput: sampleBuffer, from: connection)
        }
    }
}
