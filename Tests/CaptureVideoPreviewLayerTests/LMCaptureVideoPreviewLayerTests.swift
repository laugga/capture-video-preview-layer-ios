/*

 LMCaptureVideoPreviewLayerTests.swift
 CaptureVideoPreviewLayer Tests

 Copyright (c) 2016 Luis Laugga.
 Some rights reserved, all wrongs deserved.

*/

import AVFoundation
import UIKit
import XCTest

@testable import CaptureVideoPreviewLayer

final class LMCaptureVideoPreviewLayerTests: XCTestCase {

    private var videoPreviewLayer: LMCaptureVideoPreviewLayer!
    private var mockInternal: MockLMCaptureVideoPreviewLayerInternal!

    override func setUp() {
        super.setUp()

        // Create the session video preview layer
        videoPreviewLayer = LMCaptureVideoPreviewLayer(session: nil)
        videoPreviewLayer.backgroundColor = UIColor.black.cgColor
        videoPreviewLayer.videoGravity = .resizeAspectFill // fill the layer

        // Inject the stand-in for the capture pipeline
        mockInternal = MockLMCaptureVideoPreviewLayerInternal()
        mockInternal.sampleBufferImage = image(named: "source-image")
        videoPreviewLayer.internal = mockInternal

        // Set bounds and draw once
        videoPreviewLayer.bounds = CGRect(x: 0, y: 0, width: 375, height: 667)
        videoPreviewLayer.layoutIfNeeded()
        videoPreviewLayer.drawPixelBuffer()
        videoPreviewLayer.blur = 1.0
    }

    override func tearDown() {
        videoPreviewLayer = nil
        mockInternal = nil

        super.tearDown()
    }

    func testSourceImageIsNotNil() {

        let sourceImage = UIImage.image(from: videoPreviewLayer)

        XCTAssertEqual(sourceImage.similarity(with: sourceImage), 0.0, "Images must be the same")
    }

    func testRenderedImageSimilarityWithTargetImage() throws {

        // The reference images were captured at a 2x scale, and the comparison walks
        // both images linearly, so it is only meaningful on a 2x screen
        try XCTSkipUnless(UIScreen.main.nativeScale == 2, "Needs a device with a 2x screen, such as the iPhone SE")

        let targetImage1 = try XCTUnwrap(image(named: "target-image-12px-radius"))
        let targetImage2 = try XCTUnwrap(image(named: "target-image-36px-radius"))
        let targetImage3 = try XCTUnwrap(image(named: "target-image-48px-radius"))

        let renderedImage = UIImage.image(from: videoPreviewLayer)

        let similarity1 = renderedImage.similarity(with: targetImage1)
        let similarity2 = renderedImage.similarity(with: targetImage2)
        let similarity3 = renderedImage.similarity(with: targetImage3)

        print("*** Similarity between rendered image and reference image 1 is \(similarity1) ***")
        print("*** Similarity between rendered image and reference image 2 is \(similarity2) ***")
        print("*** Similarity between rendered image and reference image 3 is \(similarity3) ***")

        XCTAssertLessThan(similarity2, 0.1, "For Radius = 36px the images must be similar within 0.1 tolerance")
        XCTAssertLessThan(similarity3, 0.08, "For Radius = 48px the images must be similar within 0.08 tolerance")
    }

    func testRenderedImageSimilarityWithAnotherRenderedImage() {

        let renderedImage1 = UIImage.image(from: videoPreviewLayer)
        let renderedImage2 = UIImage.image(from: videoPreviewLayer)

        XCTAssertEqual(renderedImage1.similarity(with: renderedImage2), 0.0)
    }

    func testRenderPerformance() {

        measure {
            _ = UIImage.image(from: videoPreviewLayer)
        }
    }

    private func image(named name: String) -> UIImage? {
        UIImage(named: name, in: .module, compatibleWith: nil)
    }
}
