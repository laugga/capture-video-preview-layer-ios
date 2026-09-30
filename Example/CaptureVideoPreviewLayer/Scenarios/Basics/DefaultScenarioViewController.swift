/*

 DefaultScenarioViewController.swift
 Example

 Copyright (c) 2016 Luis Laugga.
 Some rights reserved, all wrongs deserved.

*/

import AVFoundation
import UIKit
import os

private let log = Logger(subsystem: "com.laugga.capture-video-preview-layer-example", category: "camera")

/// The layer as it comes: the back camera, pressed to blur in and released to blur out,
/// with a button to pause and resume the capture session.
///
/// On the Simulator, which has no camera, the preview shows a generated colour grid.
final class DefaultScenarioViewController: UIViewController {

    private let sessionQueue = DispatchQueue(label: "com.laugga.lightmate.sessionQueue")

    private var session: AVCaptureSession?
    private var device: AVCaptureDevice?

    /// Whether the person paused the session. The button and the preview follow this
    /// rather than `AVCaptureSession.isRunning`, which only changes once the session
    /// queue has got round to starting or stopping it.
    private var isPaused = false

    private let previewView = CameraPreviewView(frame: .zero)
    private let pauseButton = UIButton(type: .system)

    // MARK: - View

    override func viewDidLoad() {
        super.viewDidLoad()

        // The preview runs under the navigation bar, so give the bar a background
        // of its own to keep the title and back button legible over it
        let navigationBarAppearance = UINavigationBarAppearance()
        navigationBarAppearance.configureWithDefaultBackground()
        navigationItem.scrollEdgeAppearance = navigationBarAppearance

        view.backgroundColor = .black

        previewView.backgroundColor = .black
        previewView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewView)

        pauseButton.setTitle("Pause", for: .normal)
        pauseButton.setTitleColor(.white, for: .normal)
        pauseButton.titleLabel?.font = .systemFont(ofSize: 20, weight: .medium)
        pauseButton.alpha = 0.9
        pauseButton.translatesAutoresizingMaskIntoConstraints = false
        pauseButton.addTarget(self, action: #selector(pauseSession), for: .touchUpInside)
        view.addSubview(pauseButton)

        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            pauseButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pauseButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        sessionQueue.sync {
            setupCaptureSession()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        startRunning()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        guard let session else {
            return
        }

        sessionQueue.async {
            session.stopRunning()
        }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .phone ? [.portrait, .landscapeLeft, .landscapeRight] : .all
    }

    // MARK: - AVCaptureSession

    private func setupCaptureSession() {

        guard session == nil else {
            return
        }

        #if targetEnvironment(simulator)
        // There is no capture device on the Simulator. The preview view falls back to a
        // stand-in that feeds the preview layer with a generated still image
        DispatchQueue.main.async {
            self.previewView.setCaptureSession(nil)
        }
        return
        #else

        let captureSession = AVCaptureSession()

        // Pick the session preset. The resolution is lowered to 720p so that all
        // devices can maintain real-time performance.
        if captureSession.canSetSessionPreset(.hd1280x720) {
            captureSession.sessionPreset = .hd1280x720
        } else {
            captureSession.sessionPreset = .photo
        }

        session = captureSession

        // Select a video device, make an input
        guard let captureDevice = captureDevice(for: .back) else {
            log.error("No capture device for the back position")
            teardownCaptureSession()
            return
        }

        device = captureDevice

        do {
            let deviceInput = try AVCaptureDeviceInput(device: captureDevice)

            guard captureSession.canAddInput(deviceInput) else {
                teardownCaptureSession()
                return
            }

            captureSession.addInput(deviceInput)
        } catch {
            log.error("Could not create the device input: \(error.localizedDescription, privacy: .public)")
            teardownCaptureSession()
            return
        }

        // Setup camera preview
        DispatchQueue.main.async {
            self.previewView.setCaptureSession(captureSession)
        }

        // Observe for specific notifications related with the session
        for name in [AVCaptureSession.wasInterruptedNotification,
                     AVCaptureSession.interruptionEndedNotification,
                     AVCaptureSession.runtimeErrorNotification,
                     AVCaptureSession.didStartRunningNotification,
                     AVCaptureSession.didStopRunningNotification] {
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(captureSessionDidPostNotification(_:)),
                                                   name: name,
                                                   object: captureSession)
        }
        #endif
    }

    private func teardownCaptureSession() {

        guard let session else {
            return
        }

        NotificationCenter.default.removeObserver(self, name: nil, object: session)

        DispatchQueue.main.async {
            self.previewView.setCaptureSession(nil)
        }

        device = nil
        self.session = nil
    }

    private func captureDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera],
                                         mediaType: .video,
                                         position: position).devices.first
    }

    private func startRunning() {
        guard let session, !isPaused else {
            return
        }

        sessionQueue.async {
            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    // MARK: - Actions

    @objc private func pauseSession() {

        guard let session else {
            return
        }

        isPaused.toggle()

        pauseButton.setTitle(isPaused ? "Resume" : "Pause", for: .normal)
        previewView.isPaused = isPaused

        // Start or stop the session. The queue runs these in the order they were
        // tapped, so a tap made while the last one is still under way is not lost
        let isPaused = isPaused
        sessionQueue.async {
            if isPaused {
                session.stopRunning()
            } else {
                session.startRunning()
            }
        }
    }

    // MARK: - AVCaptureSession notifications

    @objc private func captureSessionDidPostNotification(_ notification: Notification) {
        log.debug("Camera: \(notification.name.rawValue, privacy: .public)")
    }
}

#if DEBUG
#Preview("Default") {
    DefaultScenarioViewController()
}
#endif
