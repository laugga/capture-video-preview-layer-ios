/*

 LMCaptureVideoPreviewLayerShaders.metal
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

#include <metal_stdlib>

// The path is relative on purpose. Swift Package Manager does not pass the include
// directories of the dependencies to the Metal compiler, and declaring them with
// unsafeFlags would stop the package from being usable as a versioned dependency.
#include "../CaptureVideoPreviewLayerShaderTypes/include/LMCaptureVideoPreviewLayerStructures.h"

using namespace metal;

/*!
 Data passed from the vertex function to the fragment function.

 The OpenGL ES 2.0 implementation had a dedicated blur filter vertex shader that
 pre-calculated the sampling offsets and passed them down as varyings, because
 the fragment shader was limited to 32 varying floats and because the offsets
 were expensive to recompute per fragment. Metal does not allow arrays in a
 stage_out struct, and the offsets are two multiply-adds, so all the variants
 below share the same passthrough vertex function and compute the offsets in the
 fragment function instead. The result is identical.
 */
typedef struct {
    float4 position [[position]];
    float2 textureCoordinate;
} RasterizerData_t;

#pragma mark -
#pragma mark Vertex

/*!
 Vertex Shader

 Implementation:
 - Passthrough, the quad is already in normalized device coordinates
 */
vertex RasterizerData_t defaultVertexShader(uint vertexId [[vertex_id]],
                                            constant VertexData_t * vertices [[buffer(BufferIndexVertices)]])
{
    RasterizerData_t out;

    out.position = float4(vertices[vertexId].position, 0.0, 1.0);
    out.textureCoordinate = vertices[vertexId].textureCoordinate;

    return out;
}

#pragma mark -
#pragma mark Fragment

/*!
 Fragment Shader

 Implementation:
 - Filter is disabled
 */
fragment float4 defaultFragmentShader(RasterizerData_t in [[stage_in]],
                                      texture2d<float> textureData [[texture(TextureIndexSource)]],
                                      sampler textureSampler [[sampler(SamplerIndexSource)]])
{
    return textureData.sample(textureSampler, in.textureCoordinate);
}

/*!
 Fragment Shader

 Implementation:
 - Filter is enabled
 - Bilinear texture sampling enabled
 - Filter bounds disabled
 */
fragment float4 blurFilterBtsFragmentShader(RasterizerData_t in [[stage_in]],
                                            constant FilterUniforms_t & uniforms [[buffer(BufferIndexFilterUniforms)]],
                                            texture2d<float> textureData [[texture(TextureIndexSource)]],
                                            sampler textureSampler [[sampler(SamplerIndexSource)]])
{
    // Weighted color sum of all the neighbour pixel
    float4 weightedColor = float4(0.0);

    // Sample with the provided weights and offsets in one direction
    for (int s = 0; s < uniforms.filterKernelSamples; ++s)
    {
        float weight = uniforms.filterKernelWeights[s];
        float2 offset = uniforms.filterKernelOffsets[s] * uniforms.filterSplitPassDirectionVector;
        weightedColor += weight * textureData.sample(textureSampler, in.textureCoordinate - offset) +
                         weight * textureData.sample(textureSampler, in.textureCoordinate + offset);
    }

    return weightedColor;
}

/*!
 Fragment Shader

 Implementation:
 - Filter is enabled
 - Bilinear texture sampling enabled
 - Filter bounds enabled
 */
fragment float4 blurFilterBtsBoundsFragmentShader(RasterizerData_t in [[stage_in]],
                                                  constant FilterUniforms_t & uniforms [[buffer(BufferIndexFilterUniforms)]],
                                                  texture2d<float> textureData [[texture(TextureIndexSource)]],
                                                  sampler textureSampler [[sampler(SamplerIndexSource)]])
{
    // Bounds = { xMin, yMin, xMax, yMax }
    if (in.textureCoordinate.x < uniforms.filterBounds.x ||
        in.textureCoordinate.y < uniforms.filterBounds.y ||
        in.textureCoordinate.x > uniforms.filterBounds.z ||
        in.textureCoordinate.y > uniforms.filterBounds.w)
    {
        return textureData.sample(textureSampler, in.textureCoordinate);
    }

    // Weighted color sum of all the neighbour pixel
    float4 weightedColor = float4(0.0);

    // Sample with the provided weights and offsets in one direction
    for (int s = 0; s < uniforms.filterKernelSamples; ++s)
    {
        float weight = uniforms.filterKernelWeights[s];
        float2 offset = uniforms.filterKernelOffsets[s] * uniforms.filterSplitPassDirectionVector;
        weightedColor += weight * textureData.sample(textureSampler, in.textureCoordinate - offset) +
                         weight * textureData.sample(textureSampler, in.textureCoordinate + offset);
    }

    return weightedColor;
}

/*!
 Fragment Shader

 Implementation:
 - Discrete Texture Sampling
 - Bounds disabled
 */
fragment float4 blurFilterDtsFragmentShader(RasterizerData_t in [[stage_in]],
                                            constant FilterUniforms_t & uniforms [[buffer(BufferIndexFilterUniforms)]],
                                            texture2d<float> textureData [[texture(TextureIndexSource)]],
                                            sampler textureSampler [[sampler(SamplerIndexSource)]])
{
    // Weighted color sum of all the neighbour pixel
    float4 weightedColor = float4(0.0);

    // Convolve with the provided Kernel in one direction
    int radius = uniforms.filterKernelRadius;
    for (int offset = -radius; offset <= radius; ++offset)
    {
        float weight = uniforms.filterKernelWeights[radius + offset];
        weightedColor += weight * textureData.sample(textureSampler, in.textureCoordinate + (float(offset) * uniforms.filterSplitPassDirectionVector));
    }

    return weightedColor;
}
