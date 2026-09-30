/*

 CameraPreviewView.swift
 Example

 Copyright (c) 2016 Luis Laugga.
 Some rights reserved, all wrongs deserved.

*/

import AVFoundation
import CaptureVideoPreviewLayer
import UIKit

/// Hosts the preview layer and turns a long press into a blur value.
final class CameraPreviewView: UIView {

    private static let longPressBeganLocationLayerWidth: CGFloat = 80.0

    private var videoPreviewLayer: LMCaptureVideoPreviewLayer?

    /// Debug layer showing the initial location of the long press gesture
    private let longPressBeganLocationLayer = CALayer()

    private var longPressBeganLocation: CGPoint = .zero

    /// Whether the capture session is paused. The preview layer stays blurred while it
    /// is, so a press does not blur it in and out, which would look like it resumed.
    var isPaused = false

    override init(frame: CGRect) {
        super.init(frame: frame)

        // Long press gesture used to blur-in/out the preview
        let longPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(userDidLongPress))
        longPressGestureRecognizer.minimumPressDuration = 0.001
        addGestureRecognizer(longPressGestureRecognizer)

        longPressBeganLocationLayer.bounds = CGRect(x: 0,
                                                    y: 0,
                                                    width: Self.longPressBeganLocationLayerWidth,
                                                    height: Self.longPressBeganLocationLayerWidth)
        longPressBeganLocationLayer.cornerRadius = Self.longPressBeganLocationLayerWidth / 2.0
        longPressBeganLocationLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        longPressBeganLocationLayer.backgroundColor = UIColor.white.cgColor
        longPressBeganLocationLayer.opacity = 0.9
        longPressBeganLocationLayer.isHidden = true
        layer.addSublayer(longPressBeganLocationLayer)

        layer.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // IMPORTANT
        videoPreviewLayer?.frame = bounds
    }

    // MARK: - Preview layer

    func setCaptureSession(_ captureSession: AVCaptureSession?) {

        #if targetEnvironment(simulator)
        // The Simulator has no capture device, so the preview is fed with a generated
        // still image instead of a capture session
        let shouldCreatePreviewLayer = true
        #else
        let shouldCreatePreviewLayer = captureSession != nil
        #endif

        guard shouldCreatePreviewLayer else {
            // Remove the preview layer
            videoPreviewLayer?.removeFromSuperlayer()
            videoPreviewLayer = nil
            return
        }

        // Create the session video preview layer
        let videoPreviewLayer = LMCaptureVideoPreviewLayer(session: captureSession)
        videoPreviewLayer.backgroundColor = backgroundColor?.cgColor
        videoPreviewLayer.videoGravity = .resizeAspectFill // fill the layer

        #if targetEnvironment(simulator)
        let mockInternal = MockCaptureVideoPreviewLayerInternal()
        mockInternal.delegate = videoPreviewLayer
        videoPreviewLayer.internal = mockInternal
        #endif

        layer.insertSublayer(videoPreviewLayer, below: longPressBeganLocationLayer)
        videoPreviewLayer.frame = bounds
        self.videoPreviewLayer = videoPreviewLayer

        #if targetEnvironment(simulator)
        // Start the preview once the layer has been laid out, the same notification the
        // layer would get from a capture session that started running
        DispatchQueue.main.async {
            mockInternal.simulateCaptureSessionDidStartRunningNotification()
        }
        #endif
    }

    // MARK: - Interactions

    @objc private func userDidLongPress(_ sender: UILongPressGestureRecognizer) {

        switch sender.state {
        case .began:
            longPressBeganLocation = sender.location(in: self)

            // Switch to blur = 1.0 when the user presses
            if !isPaused {
                videoPreviewLayer?.setBlur(1.0, animated: true)
            }

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            longPressBeganLocationLayer.position = longPressBeganLocation
            longPressBeganLocationLayer.isHidden = false
            CATransaction.commit()

        case .changed:
            guard !isPaused else {
                break
            }

            // Pull up to gradually decrease the blur value
            let changedLocation = sender.location(in: self)
            let offsetPercent = (longPressBeganLocation.y - changedLocation.y) / 100.0

            videoPreviewLayer?.setBlur(1.0 + offsetPercent, animated: true)

        case .ended, .failed, .cancelled:
            // Turn the blur off when the user stops pressing
            if !isPaused {
                videoPreviewLayer?.setBlur(0.0, animated: true)
            }

            longPressBeganLocationLayer.isHidden = true

        default:
            break
        }
    }
}
