/*

 LMCaptureVideoPreviewLayerUtilities.swift
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

import Metal
import os

let log = Logger(subsystem: "com.laugga.CaptureVideoPreviewLayer", category: "preview")

// MARK: - Texture instance

/// Everything needed to sample a texture and to draw a quad with it.
///
/// Where the OpenGL implementation kept a framebuffer object per instance, this
/// keeps a render pass descriptor: in Metal the destination texture is itself the
/// render target.
final class TextureInstance {

    /// Texture dimensions, kept apart from the texture because the pixel buffer
    /// instance is asked to be drawn at a downsampled size
    var textureWidth: Float = 0
    var textureHeight: Float = 0

    /// Texture binding
    var texture: MTLTexture?

    /// Geometry, vertex positions and texture coordinates (aspect-fit)
    var vertexBuffer: MTLBuffer?
    var vertexCount: Int = 0
    var primitiveType: MTLPrimitiveType = .triangleStrip

    /// Drawing render pass, the equivalent of the framebuffer
    var renderPassDescriptor: MTLRenderPassDescriptor?
}

// MARK: - Library loading

/// Loads the default metallib holding the compiled shaders.
///
/// Swift Package Manager compiles the .metal sources into the default metallib of
/// the resource bundle it generates for this target. The main bundle is tried as
/// well, for the case where the sources are compiled straight into an application.
func loadLibrary(_ device: MTLDevice) -> MTLLibrary? {

    var bundles: [Bundle] = [Bundle.module]

    if !bundles.contains(Bundle.main) {
        bundles.append(Bundle.main)
    }

    for bundle in bundles {
        if let library = try? device.makeDefaultLibrary(bundle: bundle) {
            return library
        }

        log.debug("No default metallib in bundle \(bundle.bundlePath, privacy: .public)")
    }

    log.error("Could not load the default metallib. Make sure LMCaptureVideoPreviewLayerShaders.metal is compiled into the target.")

    return nil
}

// MARK: - Render pipeline state

/// The equivalent of a linked glsl program.
func loadRenderPipelineState(device: MTLDevice,
                             library: MTLLibrary,
                             vertexFunctionName: String,
                             fragmentFunctionName: String,
                             pixelFormat: MTLPixelFormat,
                             label: String) -> MTLRenderPipelineState? {

    guard let vertexFunction = library.makeFunction(name: vertexFunctionName),
          let fragmentFunction = library.makeFunction(name: fragmentFunctionName) else {
        log.error("Could not find the shader functions \(vertexFunctionName, privacy: .public) and \(fragmentFunctionName, privacy: .public)")
        return nil
    }

    let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
    renderPipelineDescriptor.label = label
    renderPipelineDescriptor.vertexFunction = vertexFunction
    renderPipelineDescriptor.fragmentFunction = fragmentFunction
    renderPipelineDescriptor.colorAttachments[0].pixelFormat = pixelFormat

    do {
        return try device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
    } catch {
        log.error("Failed to create the render pipeline state \(label, privacy: .public): \(error.localizedDescription, privacy: .public)")
        return nil
    }
}

// MARK: - Sampler state

/// The equivalent of the GL_TEXTURE_2D texture parameters.
func loadSamplerState(_ device: MTLDevice) -> MTLSamplerState? {

    let samplerDescriptor = MTLSamplerDescriptor()
    samplerDescriptor.label = "LMCaptureVideoPreviewLayer Sampler"
    samplerDescriptor.minFilter = .linear
    samplerDescriptor.magFilter = .linear
    samplerDescriptor.sAddressMode = .clampToEdge
    samplerDescriptor.tAddressMode = .clampToEdge

    return device.makeSamplerState(descriptor: samplerDescriptor)
}

// MARK: - Render target

/// The equivalent of a texture backed framebuffer.
func loadRenderTargetTexture(device: MTLDevice,
                             width: Int,
                             height: Int,
                             pixelFormat: MTLPixelFormat,
                             storageMode: MTLStorageMode) -> MTLTexture? {

    let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat,
                                                                     width: max(1, width),
                                                                     height: max(1, height),
                                                                     mipmapped: false)
    textureDescriptor.usage = [.renderTarget, .shaderRead]
    textureDescriptor.storageMode = storageMode

    guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
        log.error("Failed to create a \(width)x\(height) render target texture")
        return nil
    }

    return texture
}

/// Render pass descriptor for drawing into a render target texture.
///
/// The target is cleared rather than loaded with MTLLoadActionDontCare: the pass is
/// expected to cover the whole render target, but a target that is only partially
/// rasterized would otherwise expose uninitialized memory, which the next filter
/// pass would sample and spread.
func loadRenderPassDescriptor(_ texture: MTLTexture) -> MTLRenderPassDescriptor {

    let renderPassDescriptor = MTLRenderPassDescriptor()
    renderPassDescriptor.colorAttachments[0].texture = texture
    renderPassDescriptor.colorAttachments[0].loadAction = .clear
    renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0)
    renderPassDescriptor.colorAttachments[0].storeAction = .store

    return renderPassDescriptor
}
