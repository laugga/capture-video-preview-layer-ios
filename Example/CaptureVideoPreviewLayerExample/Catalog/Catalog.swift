/*

 Catalog.swift
 CaptureVideoPreviewLayerExample

 Copyright (c) 2016 Luis Laugga.
 Some rights reserved, all wrongs deserved.

*/

import Foundation

/// Everything the reviewer can open, in the order it is listed.
///
/// The catalog holds the index and nothing else — each entry hands back a
/// scenario that sets itself up.
enum Catalog {

    static let sections: [CatalogSection] = [

        CatalogSection(title: "Basics", scenarios: [
            CatalogScenario(
                title: "Default",
                description: "The back camera through the preview layer. Press to blur in, drag up to ease it off, release to blur out."
            ) {
                DefaultScenarioViewController()
            }
        ])
    ]
}
