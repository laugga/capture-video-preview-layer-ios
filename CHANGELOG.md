## Unreleased

* Renamed the repository from `VisualEffectCaptureVideoPreviewLayer` to `capture-video-preview-layer-ios`, and the package, product and module from `LMCaptureVideoPreviewLayer` to `CaptureVideoPreviewLayer`: depend on `https://github.com/laugga/capture-video-preview-layer-ios.git` and `import CaptureVideoPreviewLayer`. The `LMCaptureVideoPreviewLayer` class keeps its name
* Renamed every public type and file from the `LAU` prefix to `LM` (e.g. `LAUCaptureVideoPreviewLayer` → `LMCaptureVideoPreviewLayer`); no consumer was pinned to the old name
* Metal based implementation, replacing OpenGL ES 2.0
* Written in Swift
* Distributed with Swift Package Manager, CocoaPods support removed
* Minimum deployment target raised to iOS 17.0
* Only the implemented part of the AVCaptureVideoPreviewLayer interface is exposed
* The layer reacts to its session starting and stopping on the main queue, whichever thread started or stopped it

## 0.1.0

* OpenGL ES 2.0 based implementation
