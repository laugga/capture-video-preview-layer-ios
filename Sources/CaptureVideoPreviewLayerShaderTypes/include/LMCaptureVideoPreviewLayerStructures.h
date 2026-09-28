/*

 LMCaptureVideoPreviewLayerStructures.h
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

#ifndef LMCaptureVideoPreviewLayerStructures_h
#define LMCaptureVideoPreviewLayerStructures_h

/*
 This header is shared between the Swift sources, which import it through the
 CaptureVideoPreviewLayerShaderTypes module, and the Metal shading language
 sources (LMCaptureVideoPreviewLayerShaders.metal). Everything in it must be
 valid in both C and the Metal shading language, so that the uniform and vertex
 layouts are guaranteed to match on both sides.
 */

#include <simd/simd.h>

#pragma mark -
#pragma mark Shader argument indices

/*!
 Indices used to bind the vertex and fragment shader arguments.
 These replace the OpenGL uniform/attribute handles, which had to be looked up
 by name after linking the program.
 */
typedef enum BufferIndex {
    BufferIndexVertices = 0,
    BufferIndexFilterUniforms = 1,
} BufferIndex;

typedef enum TextureIndex {
    TextureIndexSource = 0,
} TextureIndex;

typedef enum SamplerIndex {
    SamplerIndexSource = 0,
} SamplerIndex;

#pragma mark -
#pragma mark Filter kernel limits

// Maximum number of bilinear texture sampling samples (offsets) per kernel
#define kFilterKernelMaxSamples 14

// Maximum number of discrete texture sampling weights per kernel
#define kFilterKernelMaxWeights 50

#pragma mark -
#pragma mark Shader arguments

/*!
 Per-vertex data. Uploaded once per texture instance in a MTLBuffer and read by
 the vertex function through BufferIndexVertices.
 */
typedef struct {
    vector_float2 position;
    vector_float2 textureCoordinate;
} VertexData_t;

/*!
 Filter arguments, the Metal equivalent of the old struct UniformHandles.
 Instead of holding uniform locations, the struct now holds the values
 themselves and is uploaded per draw call with setFragmentBytes(_:length:index:).

 The vector members come first so that the layout matches on both the
 Swift and the Metal side (vector_float4 is 16-byte aligned).
 */
typedef struct {

    vector_float4 filterBounds; // Bounds = { xMin, yMin, xMax, yMax }

    vector_float2 filterSplitPassDirectionVector; // Separable filter, x or y step direction

    int filterKernelSamples; // s, number of bilinear samples
    int filterKernelRadius;
    int filterKernelSize; // m

    float filterKernelOffsets[kFilterKernelMaxSamples];
    float filterKernelWeights[kFilterKernelMaxWeights];

} FilterUniforms_t;

#endif /* LMCaptureVideoPreviewLayerStructures_h */
