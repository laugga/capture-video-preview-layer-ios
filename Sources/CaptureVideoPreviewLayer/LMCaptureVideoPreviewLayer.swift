/*

 LMCaptureVideoPreviewLayer.swift
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
import CaptureVideoPreviewLayerShaderTypes
import Metal
import QuartzCore
import UIKit

/// A CoreAnimation layer for previewing the visual output of an AVCaptureSession,
/// with a gaussian blur that can be changed, and animated, in real time.
///
/// It is used like an `AVCaptureVideoPreviewLayer`, created with the capture session
/// to be previewed. Under the hood it is a `CAMetalLayer`: an `AVCaptureVideoDataOutput`
/// is added to the session, and every frame is filtered and drawn with Metal.
public final class LMCaptureVideoPreviewLayer: CAMetalLayer {

    // MARK: - Filter configuration

    private static let filterBoundsEnabled = false
    private static let filterBilinearTextureSamplingEnabled = true

    // MARK: - Public

    /// The intensity of the gaussian blur effect, from 0.0 to 1.0. If the value is 0
    /// no blur effect is applied to the preview layer.
    ///
    /// Internally the layer has multiple gaussian blur kernels with different radius
    /// and standard deviation.
    public var blur: CGFloat {
        get { storedBlur }
        set { setBlur(newValue, animated: false) }
    }

    /// Changes the blur effect with an animated transition from the current value to
    /// the specified value.
    public func setBlur(_ blur: CGFloat, animated: Bool) {
        storedBlur = min(1.0, max(0.0, blur))
        setFilterIntensity(Float(storedBlur), animated: animated)
    }

    /// The AVCaptureSession instance being previewed by the receiver.
    public var session: AVCaptureSession? {
        get { self.internal.session }
        set { self.internal.session = newValue }
    }

    /// A string defining how the video is displayed within the layer bounds.
    public var videoGravity: AVLayerVideoGravity = .resizeAspect

    /// The capture pipeline feeding the receiver.
    ///
    /// Assigning a stand-in is what lets the preview be driven without a capture
    /// device, which is how the tests and the example render on the Simulator.
    public var `internal`: LMCaptureVideoPreviewLayerInternal {
        get {
            if let storedInternal {
                return storedInternal
            }

            let newInternal = LMCaptureVideoPreviewLayerInternal()
            newInternal.delegate = self
            storedInternal = newInternal

            return newInternal
        }
        set {
            storedInternal = newValue
        }
    }

    /// Creates a preview layer for the visual output of the specified session.
    public convenience init(session: AVCaptureSession?) {
        self.init()

        self.session = session
    }

    public override init() {
        super.init()
        commonInit()
    }

    public override init(layer: Any) {
        super.init(layer: layer)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    // MARK: - Private state

    private var storedBlur: CGFloat = 0
    private var storedInternal: LMCaptureVideoPreviewLayerInternal?

    // Metal command queue and shader library
    private var commandQueue: MTLCommandQueue?
    private var library: MTLLibrary?

    // Render pipeline states, the equivalent of the linked glsl programs
    private var defaultPipelineState: MTLRenderPipelineState?   // On-screen
    private var blurFilterPipelineState: MTLRenderPipelineState? // Off-screen

    // Texture sampling, shared by every render pipeline
    private var samplerState: MTLSamplerState?

    // Shader arguments
    private var filterUniforms = FilterUniforms_t()

    // Layer used to display a snapshot image of the current framebuffer
    private var onscreenSnapshotImageSublayer: CALayer?

    // CoreAnimation layer for previewing the visual output of an AVCaptureSession.
    // Used for normal rendering. More efficient (CPU and GPU) than our own...
    private var videoPreviewSublayer: AVCaptureVideoPreviewLayer?

    // Display link
    private var storedDisplayLink: CADisplayLink?

    // Metal texture cache (core video)
    private var metalTextureCache: CVMetalTextureCache?

    // Last pixel buffer set, waiting to be rendered or last one rendered
    private var pixelBufferTexture: CVMetalTexture?

    // Offscreen render targets
    private let pixelBufferTextureInstance = TextureInstance()
    private let offscreenTextureInstances = [TextureInstance(), TextureInstance()]

    // Pixel buffer dimensions, before any downsampling is applied
    private var pixelBufferTextureNativeWidth: Float = 0
    private var pixelBufferTextureNativeHeight: Float = 0

    // Onscreen drawable
    private var onscreenDrawableWidth = 0
    private var onscreenDrawableHeight = 0
    private let onscreenTextureInstance = TextureInstance()

    // Texture instance drawn by the last onscreen pass, used for the snapshot
    private var onscreenSourceTextureInstance: TextureInstance?

    // Texture used to read back the onscreen contents
    private var onscreenSnapshotTexture: MTLTexture?

    // Filter (kernel)
    private var filterKernels: [FilterKernel] = []
    private var filterKernelIndex = 0

    // Filter (parameters)
    private var filterSplitPassDirectionVector = SIMD2<Float>(0, 0)
    private var filterMultiplePassCount = 2
    private var filterDownsamplingFactor: Float = 4.0

    // Filter (intensity)
    private var filterIntensity: Float = 0
    private var filterIntensityNeedsUpdate = false
    private var filterIntensityTransitionTimer: DispatchSourceTimer?
    private var filterIntensityTransitionTarget: Float = 0

    // Filter (bounds)
    private var filterBounds = SIMD4<Float>(0, 0, 1, 1)
    private var filterBoundsNeedsUpdate = false

    // MARK: - Initialization

    private func commonInit() {

        // We use the native scale of the screen as our content scale factor. This
        // allows us to render to the exact pixel resolution of the screen which avoids
        // additional scaling and GPU rendering work. Since we are streaming 1080p
        // buffers from the camera we can render at 1:1 with no additional scaling if
        // we set everything up correctly.
        contentsScale = UIScreen.main.nativeScale

        isOpaque = true
        pixelFormat = .bgra8Unorm
        framebufferOnly = true

        // The Metal device replaces the EAGLContext
        guard let device = MTLCreateSystemDefaultDevice() else {
            log.error("Could not create a valid MTLDevice")
            return
        }

        self.device = device
        commandQueue = device.makeCommandQueue()
        library = loadLibrary(device)

        // Filter bounds default to the whole texture
        filterUniforms.filterBounds = filterBounds

        // Preemptively load filter in memory
        loadFilter()
    }

    public override func layoutSublayers() {
        super.layoutSublayers()

        // Keep the drawable in sync with the layer bounds
        updateDrawableSize()

        guard defaultPipelineState == nil else {
            return
        }

        // Load the render pipeline states and the sampler state
        loadBlurFilterPipelineState()
        loadDefaultPipelineState()
        loadSamplerStateIfNeeded()

        // Metal pre-warm
        if storedInternal?.sampleBuffer == nil {
            draw(color: backgroundColor)
        }

        // Set filter intensity from blur value
        setFilterIntensity(Float(storedBlur))

        if Self.filterBoundsEnabled {
            setFilterBoundsRect(CGRect(x: 0, y: 0, width: 1, height: 0.5))
        }
    }

    private func loadDefaultPipelineState() {
        guard defaultPipelineState == nil, let device, let library else {
            return
        }

        defaultPipelineState = loadRenderPipelineState(device: device,
                                                       library: library,
                                                       vertexFunctionName: ShaderFunctionName.defaultVertex,
                                                       fragmentFunctionName: ShaderFunctionName.defaultFragment,
                                                       pixelFormat: pixelFormat,
                                                       label: "Default")
    }

    private func loadBlurFilterPipelineState() {
        guard blurFilterPipelineState == nil, let device, let library else {
            return
        }

        let fragmentFunctionName: String
        if Self.filterBilinearTextureSamplingEnabled {
            fragmentFunctionName = Self.filterBoundsEnabled ? ShaderFunctionName.blurFilterBtsBoundsFragment
                                                            : ShaderFunctionName.blurFilterBtsFragment
        } else {
            fragmentFunctionName = ShaderFunctionName.blurFilterDtsFragment
        }

        blurFilterPipelineState = loadRenderPipelineState(device: device,
                                                          library: library,
                                                          vertexFunctionName: ShaderFunctionName.defaultVertex,
                                                          fragmentFunctionName: fragmentFunctionName,
                                                          pixelFormat: pixelFormat,
                                                          label: "Blur Filter")
    }

    private func loadSamplerStateIfNeeded() {
        guard samplerState == nil, let device else {
            return
        }

        // Linear filtering and clamp to edge, for every texture sampled by the shaders
        samplerState = loadSamplerState(device)
    }

    // MARK: - Snapshot

    public override func render(in ctx: CGContext) {
        render(in: ctx, redrawPixelBuffer: true)
    }

    private func render(in context: CGContext, redrawPixelBuffer: Bool) {

        // Redraw the pixel buffer, otherwise the last drawn texture instance is used
        if redrawPixelBuffer {
            drawPixelBuffer()
        }

        // The contents of a CAMetalDrawable can not be read back after being presented,
        // so the onscreen pass is drawn once more into a texture we own
        guard let onscreenSourceTextureInstance,
              let snapshotTexture = makeOnscreenSnapshotTextureIfNeeded(),
              let commandBuffer = commandQueue?.makeCommandBuffer() else {
            log.debug("Nothing was drawn yet, there is nothing to read back")
            return
        }

        drawOnscreen(onscreenSourceTextureInstance, into: snapshotTexture, commandBuffer: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // Assuming MTLPixelFormatBGRA8Unorm is used
        let bytesPerRow = onscreenDrawableWidth * 4
        let byteCount = bytesPerRow * onscreenDrawableHeight
        let pixelsData = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 4)

        snapshotTexture.getBytes(pixelsData,
                                 bytesPerRow: bytesPerRow,
                                 from: MTLRegionMake2D(0, 0, onscreenDrawableWidth, onscreenDrawableHeight),
                                 mipmapLevel: 0)

        // Metal gives us BGRA, which is 32 bits little-endian with the alpha first
        let bitmapInfo = CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue |
                                                CGImageAlphaInfo.premultipliedFirst.rawValue)

        guard let dataProvider = CGDataProvider(dataInfo: nil,
                                                data: pixelsData,
                                                size: byteCount,
                                                releaseData: { _, data, _ in
                                                    UnsafeMutableRawPointer(mutating: data).deallocate()
                                                }),
              let image = CGImage(width: onscreenDrawableWidth,
                                  height: onscreenDrawableHeight,
                                  bitsPerComponent: 8,
                                  bitsPerPixel: 32,
                                  bytesPerRow: bytesPerRow,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: bitmapInfo,
                                  provider: dataProvider,
                                  decode: nil,
                                  shouldInterpolate: true,
                                  intent: .defaultIntent) else {
            return
        }

        let width = CGFloat(onscreenDrawableWidth) / contentsScale
        let height = CGFloat(onscreenDrawableHeight) / contentsScale

        // Unlike glReadPixels, which returned the rows bottom-up, the first row read
        // from a MTLTexture is the top one. Flip the context so the image is not drawn
        // upside down (the UIKit coordinate system is the inverse of the Quartz one).
        context.saveGState()
        context.setBlendMode(.copy)
        context.translateBy(x: 0, y: height)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.restoreGState()
    }

    private func makeOnscreenSnapshotTextureIfNeeded() -> MTLTexture? {
        guard onscreenSnapshotTexture == nil else {
            return onscreenSnapshotTexture
        }

        guard let device, onscreenDrawableWidth > 0, onscreenDrawableHeight > 0 else {
            return nil
        }

        // Shared storage so the contents can be read back with getBytes
        onscreenSnapshotTexture = loadRenderTargetTexture(device: device,
                                                          width: onscreenDrawableWidth,
                                                          height: onscreenDrawableHeight,
                                                          pixelFormat: pixelFormat,
                                                          storageMode: .shared)

        return onscreenSnapshotTexture
    }

    private var imageFromOnscreenFramebuffer: UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true

        return UIGraphicsImageRenderer(bounds: bounds, format: format).image { context in
            render(in: context.cgContext, redrawPixelBuffer: false)
        }
    }

    // MARK: - CADisplayLink

    private var displayLink: CADisplayLink {
        if let storedDisplayLink {
            return storedDisplayLink
        }

        let newDisplayLink = CADisplayLink(target: self, selector: #selector(displayLinkDidFire))
        newDisplayLink.add(to: .current, forMode: .common)
        newDisplayLink.isPaused = true
        storedDisplayLink = newDisplayLink

        return newDisplayLink
    }

    @objc private func displayLinkDidFire() {
        drawPixelBuffer()
    }

    private func setDisplayLinkPaused(_ paused: Bool) {
        // The display link is only ours to control while the AVCaptureVideoPreviewLayer
        // sublayer is not the one on screen. When there is no such sublayer at all,
        // which is the case for a session that AVFoundation can not preview, we are the
        // only thing that can draw.
        if videoPreviewSublayer == nil || videoPreviewSublayer?.isHidden == true {
            displayLink.isPaused = paused
        }
    }

    // MARK: - AVCaptureVideoPreviewLayer

    private func addAVCaptureVideoPreviewSublayer() {

        guard let session = storedInternal?.session else {
            return
        }

        if videoPreviewSublayer == nil {
            // Create the session video preview layer from AVFoundation
            let newVideoPreviewSublayer = AVCaptureVideoPreviewLayer(session: session)
            newVideoPreviewSublayer.backgroundColor = backgroundColor
            newVideoPreviewSublayer.videoGravity = .resizeAspectFill // TODO videoGravity
            newVideoPreviewSublayer.bounds = bounds
            newVideoPreviewSublayer.anchorPoint = CGPoint(x: 0, y: 0)
            newVideoPreviewSublayer.isHidden = true

            addSublayer(newVideoPreviewSublayer)
            videoPreviewSublayer = newVideoPreviewSublayer
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoPreviewSublayer?.isHidden = false
        CATransaction.commit()

        displayLink.isPaused = true
        flushPixelBufferCache()
    }

    private func removeAVCaptureVideoPreviewSublayer() {

        guard videoPreviewSublayer != nil else {
            return
        }

        drawPixelBuffer()
        displayLink.isPaused = false

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoPreviewSublayer?.isHidden = true
        CATransaction.commit()
    }

    // MARK: - Onscreen framebuffer snapshot

    private func addOnscreenSnapshotImageSublayer() {

        guard pixelBufferTexture != nil else {
            return
        }

        let sublayer = CALayer()
        sublayer.bounds = bounds
        sublayer.contentsScale = contentsScale
        sublayer.anchorPoint = CGPoint(x: 0, y: 0)
        sublayer.backgroundColor = backgroundColor
        sublayer.contents = imageFromOnscreenFramebuffer.cgImage
        sublayer.opacity = 1.0

        addSublayer(sublayer)
        onscreenSnapshotImageSublayer = sublayer
    }

    private func removeOnscreenSnapshotImageSublayer() {

        guard let onscreenSnapshotImageSublayer else {
            return
        }

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            onscreenSnapshotImageSublayer.removeFromSuperlayer()
            self?.onscreenSnapshotImageSublayer = nil
        }
        CATransaction.setAnimationDuration(0.25)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeIn))

        onscreenSnapshotImageSublayer.opacity = 0.0

        CATransaction.commit()
    }

    // MARK: - Texture instance (CVPixelBuffer)

    private func metalTexture(from pixelBuffer: CVPixelBuffer) -> CVMetalTexture? {

        // Create a new CVMetalTexture cache
        if metalTextureCache == nil, let device {
            let cacheAttributes = [kCVMetalTextureCacheMaximumTextureAgeKey as String: 0.1] as CFDictionary
            let result = CVMetalTextureCacheCreate(kCFAllocatorDefault, cacheAttributes, device, nil, &metalTextureCache)

            guard result == kCVReturnSuccess else {
                log.error("Error at CVMetalTextureCacheCreate \(result)")
                return nil
            }
        }

        guard let metalTextureCache else {
            return nil
        }

        // Create a CVMetalTexture from a CVPixelBuffer
        var metalTexture: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                               metalTextureCache,
                                                               pixelBuffer,
                                                               nil,
                                                               .bgra8Unorm,
                                                               CVPixelBufferGetWidth(pixelBuffer),
                                                               CVPixelBufferGetHeight(pixelBuffer),
                                                               0,
                                                               &metalTexture)

        guard result == kCVReturnSuccess else {
            log.error("CVMetalTextureCacheCreateTextureFromImage failed (error \(result))")
            return nil
        }

        return metalTexture
    }

    private func flushPixelBufferCache() {
        pixelBufferTexture = nil

        if let metalTextureCache {
            CVMetalTextureCacheFlush(metalTextureCache, 0)
        }
    }

    // MARK: - Offscreen rendering

    private func loadOffscreenTextureInstance(_ textureInstance: TextureInstance) {

        guard let device else {
            return
        }

        // Create the texture to render, it doubles as the render target of the pass.
        // In Metal there is no framebuffer object to attach it to, the render pass
        // descriptor points at the texture directly.
        textureInstance.texture = loadRenderTargetTexture(device: device,
                                                          width: Int(textureInstance.textureWidth.rounded()),
                                                          height: Int(textureInstance.textureHeight.rounded()),
                                                          pixelFormat: pixelFormat,
                                                          storageMode: .private)

        if let texture = textureInstance.texture {
            textureInstance.renderPassDescriptor = loadRenderPassDescriptor(texture)
        }

        // Use triangle strip
        textureInstance.primitiveType = .triangleStrip

        // Vertex data.
        //
        // The texture coordinates are vertically flipped when compared with the OpenGL
        // ES implementation. Metal renders the first row of a texture at the top of the
        // viewport, while OpenGL rendered it at the bottom, so flipping the coordinates
        // here keeps every offscreen pass an exact copy of its source, whatever the
        // number of passes applied.
        let vertexData = [
            VertexData_t(position: [-1.0, -1.0], textureCoordinate: [0.0, 1.0]), // bottom left
            VertexData_t(position: [ 1.0, -1.0], textureCoordinate: [1.0, 1.0]), // bottom right
            VertexData_t(position: [-1.0,  1.0], textureCoordinate: [0.0, 0.0]), // top left
            VertexData_t(position: [ 1.0,  1.0], textureCoordinate: [1.0, 0.0])  // top right
        ]

        textureInstance.vertexCount = vertexData.count
        textureInstance.vertexBuffer = device.makeBuffer(bytes: vertexData,
                                                         length: MemoryLayout<VertexData_t>.stride * vertexData.count,
                                                         options: .storageModeShared)
    }

    private func scaleDownPixelBufferTextureInstanceDimensions() {

        // Pixel buffer dimensions and ratio.
        // The native dimensions are used, and not the ones currently set on the texture
        // instance, so that a pixel buffer which is drawn more than once, when no new
        // sample buffer is available, is not downsampled again on every draw call.
        let pixelBufferWidth = pixelBufferTextureNativeWidth
        let pixelBufferHeight = pixelBufferTextureNativeHeight

        guard pixelBufferWidth > 0, pixelBufferHeight > 0 else {
            return
        }

        let pixelBufferRatio = pixelBufferWidth / pixelBufferHeight // Usually w > h

        // Screen dimensions and ratio
        let onscreenWidth = Float(onscreenDrawableWidth)
        let onscreenHeight = Float(onscreenDrawableHeight)
        let onscreenRatio = onscreenHeight / onscreenWidth

        let textureDownsamplingFactor: Float
        if onscreenRatio > pixelBufferRatio {
            // Use height to calculate the downsampling effective factor
            textureDownsamplingFactor = pixelBufferWidth / (onscreenHeight / filterDownsamplingFactor)
        } else {
            // Use width to calculate the downsampling effective factor
            textureDownsamplingFactor = pixelBufferHeight / (onscreenWidth / filterDownsamplingFactor)
        }

        // Downsample the input pixel buffer by a specific factor.
        // The dimensions are rounded to whole pixels: they end up being both the size of
        // the offscreen texture and the size of the viewport drawn into it, and a
        // viewport narrower than its render target would leave the last row or column of
        // the texture unrasterized.
        pixelBufferTextureInstance.textureWidth = max(1, (pixelBufferWidth / textureDownsamplingFactor).rounded())
        pixelBufferTextureInstance.textureHeight = max(1, (pixelBufferHeight / textureDownsamplingFactor).rounded())
    }

    private func drawOffscreen(_ sourceTextureInstance: TextureInstance,
                               onto destinationTextureInstance: TextureInstance,
                               commandBuffer: MTLCommandBuffer) {

        // Check dimensions of the source texture instance
        let width = sourceTextureInstance.textureWidth
        let height = sourceTextureInstance.textureHeight

        // Check if dimensions changed and load again if needed
        if destinationTextureInstance.textureWidth != width || destinationTextureInstance.textureHeight != height {
            destinationTextureInstance.textureWidth = width
            destinationTextureInstance.textureHeight = height

            loadOffscreenTextureInstance(destinationTextureInstance)
        }

        guard let renderPassDescriptor = destinationTextureInstance.renderPassDescriptor,
              let destinationTexture = destinationTextureInstance.texture,
              let blurFilterPipelineState else {
            log.error("Invalid offscreen texture instance render target")
            return
        }

        // Set the filter split-pass direction vector
        setFilterSplitPassDirectionVector(for: destinationTextureInstance)

        guard let renderCommandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        renderCommandEncoder.label = "Offscreen Blur Filter Pass"

        // Set the view port to the entire destination texture. The texture dimensions
        // are used, and not the instance ones, so that the viewport always covers every
        // pixel of the render target.
        renderCommandEncoder.setViewport(MTLViewport(originX: 0,
                                                     originY: 0,
                                                     width: Double(destinationTexture.width),
                                                     height: Double(destinationTexture.height),
                                                     znear: 0,
                                                     zfar: 1))

        renderCommandEncoder.setRenderPipelineState(blurFilterPipelineState)
        renderCommandEncoder.setVertexBuffer(destinationTextureInstance.vertexBuffer, offset: 0, index: Int(BufferIndexVertices.rawValue))
        renderCommandEncoder.setFragmentBytes(&filterUniforms,
                                              length: MemoryLayout<FilterUniforms_t>.stride,
                                              index: Int(BufferIndexFilterUniforms.rawValue))
        renderCommandEncoder.setFragmentTexture(sourceTextureInstance.texture, index: Int(TextureIndexSource.rawValue))
        renderCommandEncoder.setFragmentSamplerState(samplerState, index: Int(SamplerIndexSource.rawValue))
        renderCommandEncoder.drawPrimitives(type: destinationTextureInstance.primitiveType,
                                            vertexStart: 0,
                                            vertexCount: destinationTextureInstance.vertexCount)
        renderCommandEncoder.endEncoding()
    }

    // MARK: - Onscreen rendering

    private func updateDrawableSize() {

        let width = Int((bounds.size.width * contentsScale).rounded())
        let height = Int((bounds.size.height * contentsScale).rounded())

        guard width > 0, height > 0 else {
            return
        }

        guard width != onscreenDrawableWidth || height != onscreenDrawableHeight else {
            return
        }

        onscreenDrawableWidth = width
        onscreenDrawableHeight = height

        drawableSize = CGSize(width: width, height: height)

        // The onscreen quad texture coordinates are aspect-fit against the drawable
        // dimensions, invalidate it so it is loaded again on the next draw call
        onscreenTextureInstance.textureWidth = 0
        onscreenTextureInstance.textureHeight = 0

        // The snapshot texture has to match the new drawable dimensions
        onscreenSnapshotTexture = nil
    }

    private func onscreenTextureCoordinatesOffsets(for textureInstance: TextureInstance) -> CGPoint {

        // We assume the pixel buffer is landscape, rotated 90 degrees anti-clockwise. So:
        // 1. We switch width and height
        // 2. Rotate 90 degrees clockwise by mapping the texture coordinates
        // The pixel buffer (and texture) remain unchanged. We only flip the view height
        // and width and map the texture to the appropriate vertices so it is rotated.
        onscreenTextureInstance.textureWidth = textureInstance.textureWidth
        onscreenTextureInstance.textureHeight = textureInstance.textureHeight

        // Ratio of view versus texture
        let viewRatio = Float(onscreenDrawableHeight) / Float(onscreenDrawableWidth)
        let textureRatio = onscreenTextureInstance.textureWidth / onscreenTextureInstance.textureHeight

        // Change S (T=1) if texture ratio <= view ratio
        // Change T (S=1) if texture ratio > view ratio
        let changeT = textureRatio > viewRatio

        // Calculate the texture scale factor
        let textureScale: Float
        if changeT {
            // Change T means we need to check view height versus texture height
            textureScale = Float(onscreenDrawableWidth) / onscreenTextureInstance.textureHeight
        } else {
            // Change S means we need to check view width versus texture width
            textureScale = Float(onscreenDrawableHeight) / onscreenTextureInstance.textureWidth
        }

        // Calculate texture scaled dimensions
        let scaledTextureWidth = onscreenTextureInstance.textureWidth * textureScale
        let scaledTextureHeight = onscreenTextureInstance.textureHeight * textureScale

        // Calculate the texture coordinates S and T deltas
        let deltaTextureCoordinateS = (scaledTextureWidth - Float(onscreenDrawableHeight)) / scaledTextureWidth / 2.0
        let deltaTextureCoordinateT = (scaledTextureHeight - Float(onscreenDrawableWidth)) / scaledTextureHeight / 2.0

        return CGPoint(x: CGFloat(deltaTextureCoordinateS), y: CGFloat(deltaTextureCoordinateT))
    }

    private func loadOnscreenTextureInstance(for textureInstance: TextureInstance) {

        guard let device else {
            return
        }

        // Use triangle strip
        onscreenTextureInstance.primitiveType = .triangleStrip

        // Calculate the texture coordinates offsets for the input texture instance
        let offsets = onscreenTextureCoordinatesOffsets(for: textureInstance)
        let offsetS = Float(offsets.x)
        let offsetT = Float(offsets.y)

        let vertexData = [
            VertexData_t(position: [-1.0, -1.0], textureCoordinate: [1.0 - offsetS, 1.0 - offsetT]), // bottom left
            VertexData_t(position: [ 1.0, -1.0], textureCoordinate: [1.0 - offsetS, 0.0 + offsetT]), // bottom right
            VertexData_t(position: [-1.0,  1.0], textureCoordinate: [0.0 + offsetS, 1.0 - offsetT]), // top left
            VertexData_t(position: [ 1.0,  1.0], textureCoordinate: [0.0 + offsetS, 0.0 + offsetT])  // top right
        ]

        onscreenTextureInstance.vertexCount = vertexData.count
        onscreenTextureInstance.vertexBuffer = device.makeBuffer(bytes: vertexData,
                                                                 length: MemoryLayout<VertexData_t>.stride * vertexData.count,
                                                                 options: .storageModeShared)
    }

    private func drawOnscreen(_ textureInstance: TextureInstance,
                              into texture: MTLTexture,
                              commandBuffer: MTLCommandBuffer) {

        // Check if dimensions changed and load again if needed
        if onscreenTextureInstance.textureWidth != textureInstance.textureWidth ||
           onscreenTextureInstance.textureHeight != textureInstance.textureHeight {
            loadOnscreenTextureInstance(for: textureInstance)
        }

        guard let defaultPipelineState,
              let renderCommandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: loadRenderPassDescriptor(texture)) else {
            return
        }

        renderCommandEncoder.label = "Onscreen Pass"

        // Set the view port to the entire view
        renderCommandEncoder.setViewport(MTLViewport(originX: 0,
                                                     originY: 0,
                                                     width: Double(onscreenDrawableWidth),
                                                     height: Double(onscreenDrawableHeight),
                                                     znear: 0,
                                                     zfar: 1))

        // Filtering is disabled for the final onscreen rendering
        renderCommandEncoder.setRenderPipelineState(defaultPipelineState)
        renderCommandEncoder.setVertexBuffer(onscreenTextureInstance.vertexBuffer, offset: 0, index: Int(BufferIndexVertices.rawValue))
        renderCommandEncoder.setFragmentTexture(textureInstance.texture, index: Int(TextureIndexSource.rawValue))
        renderCommandEncoder.setFragmentSamplerState(samplerState, index: Int(SamplerIndexSource.rawValue))
        renderCommandEncoder.drawPrimitives(type: onscreenTextureInstance.primitiveType,
                                            vertexStart: 0,
                                            vertexCount: onscreenTextureInstance.vertexCount)
        renderCommandEncoder.endEncoding()
    }

    // MARK: - Drawing

    private func draw(color: CGColor?) {

        guard let commandQueue else {
            log.error("Metal command queue not initialized")
            return
        }

        guard let drawable = nextDrawable() else {
            log.debug("No drawable available")
            return
        }

        let components = color?.components ?? [0, 0, 0, 1]
        let clearColor: MTLClearColor
        if components.count == 4 {
            clearColor = MTLClearColorMake(Double(components[0]), Double(components[1]), Double(components[2]), Double(components[3]))
        } else {
            clearColor = MTLClearColorMake(0, 0, 0, 1)
        }

        let renderPassDescriptor = loadRenderPassDescriptor(drawable.texture)
        renderPassDescriptor.colorAttachments[0].clearColor = clearColor

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderCommandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        renderCommandEncoder.label = "Clear Pass"
        renderCommandEncoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// Renders the most recent sample buffer, or the last one again when the capture
    /// pipeline has nothing new.
    func drawPixelBuffer() {

        if let sampleBuffer = storedInternal?.sampleBuffer {

            // New pixel buffer available to be rendered?
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                log.debug("The sample buffer has no image buffer")
                return
            }

            // Check dimensions of the pixel buffer
            let width = Float(CVPixelBufferGetWidth(pixelBuffer))
            let height = Float(CVPixelBufferGetHeight(pixelBuffer))

            // Get the Metal texture
            guard let newPixelBufferTexture = metalTexture(from: pixelBuffer) else {
                return
            }

            pixelBufferTexture = newPixelBufferTexture

            // Wrap the pixel buffer in a texture instance
            pixelBufferTextureNativeWidth = width
            pixelBufferTextureNativeHeight = height
            pixelBufferTextureInstance.textureWidth = width
            pixelBufferTextureInstance.textureHeight = height
            pixelBufferTextureInstance.texture = CVMetalTextureGetTexture(newPixelBufferTexture)

        } else if pixelBufferTexture != nil {
            // Re-using the last pixel buffer texture
        } else {
            log.debug("No sample buffer and no pixel buffer texture, not going to render")
            return
        }

        guard defaultPipelineState != nil, blurFilterPipelineState != nil else {
            log.debug("The render pipeline states are not loaded yet, not going to render")
            return
        }

        guard let drawable = nextDrawable(),
              let commandBuffer = commandQueue?.makeCommandBuffer() else {
            log.debug("No drawable available, not going to render")
            return
        }

        commandBuffer.label = "LMCaptureVideoPreviewLayer Frame"

        // Texture instance used by the final onscreen pass
        var onscreenSourceTextureInstance = pixelBufferTextureInstance

        // Only filter if the filter intensity is greater than 0
        if filterIntensity > 0 {

            // Update any filter argument that changed since the last frame
            updateBlurFilterUniforms()

            // Downsample the pixel buffer texture dimensions
            scaleDownPixelBufferTextureInstanceDimensions()

            // First draw the pixel buffer in an offscreen texture instance
            drawOffscreen(pixelBufferTextureInstance, onto: offscreenTextureInstances[0], commandBuffer: commandBuffer)

            // Draw the offscreen texture instances and keep applying the filter (ping,
            // pong, ping, pong). Because we already drew once, the number of draw calls
            // left is 2 * multiple-pass-count - 1.
            for pass in 1..<(2 * filterMultiplePassCount) {
                drawOffscreen(offscreenTextureInstances[(pass + 1) % 2],
                              onto: offscreenTextureInstances[pass % 2],
                              commandBuffer: commandBuffer)
            }

            onscreenSourceTextureInstance = offscreenTextureInstances[1]
        }

        // Keep a reference for the snapshot
        self.onscreenSourceTextureInstance = onscreenSourceTextureInstance

        drawOnscreen(onscreenSourceTextureInstance, into: drawable.texture, commandBuffer: commandBuffer)

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func updateBlurFilterUniforms() {

        if filterIntensityNeedsUpdate, filterKernelIndex < filterKernels.count {
            let filterKernel = filterKernels[filterKernelIndex]

            if Self.filterBilinearTextureSamplingEnabled {
                filterUniforms.filterKernelSamples = Int32(filterKernel.samples)
                withUnsafeMutableBytes(of: &filterUniforms.filterKernelOffsets) { copy(filterKernel.offsets, into: $0) }
                withUnsafeMutableBytes(of: &filterUniforms.filterKernelWeights) { copy(filterKernel.weights, into: $0) }
            } else {
                filterUniforms.filterKernelRadius = Int32(filterKernel.radius)
                filterUniforms.filterKernelSize = Int32(filterKernel.size)
                withUnsafeMutableBytes(of: &filterUniforms.filterKernelWeights) { copy(filterKernel.weights, into: $0) }
            }

            filterIntensityNeedsUpdate = false
        }

        if Self.filterBoundsEnabled, filterBoundsNeedsUpdate {
            filterUniforms.filterBounds = filterBounds
            filterBoundsNeedsUpdate = false
        }
    }

    /// Copies as many values as fit into the destination, which is a C array imported
    /// into Swift as a tuple.
    private func copy(_ values: [Float], into destination: UnsafeMutableRawBufferPointer) {
        let capacity = destination.count / MemoryLayout<Float>.size
        let count = min(values.count, capacity)

        values.withUnsafeBytes { source in
            destination.copyMemory(from: UnsafeRawBufferPointer(rebasing: source[0..<(count * MemoryLayout<Float>.size)]))
        }
    }

    // MARK: - Filtering (intensity)

    private func setFilterIntensity(_ intensity: Float) {

        // Bail out if the render pipeline state hasn't been loaded yet
        guard blurFilterPipelineState != nil, !filterKernels.isEmpty else {
            return
        }

        let oldIntensity = filterIntensity

        // Clamp the intensity between [0,1]
        let newIntensity = max(0, min(1, intensity))
        filterIntensity = newIntensity

        // Map the intensity to an integer kernel index
        let mappedIndex = Int((newIntensity * Float(filterKernels.count - 1)).rounded())
        filterKernelIndex = max(0, min(filterKernels.count - 1, mappedIndex))

        filterIntensityNeedsUpdate = true

        if newIntensity > 0.0 && oldIntensity == 0.0 {
            removeAVCaptureVideoPreviewSublayer()
        } else if newIntensity == 0.0 {
            addAVCaptureVideoPreviewSublayer()
        }
    }

    private func setFilterIntensity(_ intensity: Float, animated: Bool) {

        // A transition already under way would otherwise fight this one
        filterIntensityTransitionTimer?.cancel()
        filterIntensityTransitionTimer = nil

        guard animated else {
            setFilterIntensity(intensity)
            return
        }

        // Assign the target filter intensity
        filterIntensityTransitionTarget = intensity

        // Define the timer step based on the number of kernels available
        let step = 1.0 / Float(max(1, filterKernels.count))

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 1.0 / 60.0)
        timer.setEventHandler { [weak self] in
            guard let self else {
                return
            }

            guard filterIntensity != filterIntensityTransitionTarget else {
                filterIntensityTransitionTimer?.cancel()
                filterIntensityTransitionTimer = nil
                return
            }

            if filterIntensity < filterIntensityTransitionTarget {
                setFilterIntensity(min(filterIntensity + step, filterIntensityTransitionTarget))
            } else {
                setFilterIntensity(max(filterIntensity - step, filterIntensityTransitionTarget))
            }
        }

        filterIntensityTransitionTimer = timer
        timer.resume()
    }

    // MARK: - Filtering (bounds)

    private func setFilterBoundsRect(_ filterBoundsRect: CGRect) {

        let xMin = Float(filterBoundsRect.minX)
        let xMax = Float(filterBoundsRect.maxX)
        let yMin = Float(filterBoundsRect.minY)
        let yMax = Float(filterBoundsRect.maxY)

        // Bounds within the texture that are filtered [xMin, yMin, xMax, yMax].
        // The texture coordinates mapping rotates the texture 90 degrees clockwise, so
        // x and y are flipped here to work with the rotation.
        filterBounds = SIMD4<Float>(yMin, 1.0 - xMax, yMax, 1.0 - xMin)
        filterBoundsNeedsUpdate = true
    }

    // MARK: - Filtering (kernel)

    private func loadFilter() {

        guard filterKernels.isEmpty else {
            return
        }

        filterKernels = (0..<GaussianFilterKernel.count).map { index in
            Self.filterBilinearTextureSamplingEnabled ? GaussianFilterKernel.bts(at: index)
                                                      : GaussianFilterKernel.dts(at: index)
        }
    }

    private func setFilterSplitPassDirectionVector(for textureInstance: TextureInstance) {

        // Switch the previous vector
        if filterSplitPassDirectionVector.x == 0 {
            filterSplitPassDirectionVector = SIMD2<Float>(1, 0)
        } else {
            filterSplitPassDirectionVector = SIMD2<Float>(0, 1)
        }

        // Set the filter step argument
        filterUniforms.filterSplitPassDirectionVector = SIMD2<Float>(filterSplitPassDirectionVector.x / textureInstance.textureWidth,
                                                                     filterSplitPassDirectionVector.y / textureInstance.textureHeight)
    }
}

// MARK: - LMCaptureVideoPreviewLayerInternalDelegate

extension LMCaptureVideoPreviewLayer: LMCaptureVideoPreviewLayerInternalDelegate {

    public func captureVideoPreviewLayerInternal(_ internalPipeline: LMCaptureVideoPreviewLayerInternal,
                                                 sessionDidStopRunning session: AVCaptureSession?) {
        setBlur(1.0, animated: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            // TODO pause when the blur-in animation finishes
            self?.setDisplayLinkPaused(true)
        }
    }

    public func captureVideoPreviewLayerInternal(_ internalPipeline: LMCaptureVideoPreviewLayerInternal,
                                                 sessionDidStartRunning session: AVCaptureSession?) {

        // Delay the fade out transition because the first frames after the session
        // starts running are darker
        let fadeOutDelay = 0.7

        // This shows the snapshot image layer to hide the dark frames
        addOnscreenSnapshotImageSublayer()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.setDisplayLinkPaused(false)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + fadeOutDelay) { [weak self] in
            self?.removeOnscreenSnapshotImageSublayer()
            self?.setBlur(0.0, animated: true)
        }
    }
}
