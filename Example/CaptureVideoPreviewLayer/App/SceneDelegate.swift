/*

 SceneDelegate.swift
 Example

 Copyright (c) 2016 Luis Laugga.
 Some rights reserved, all wrongs deserved.

*/

import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else {
            return
        }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UINavigationController(rootViewController: CatalogViewController())
        window.makeKeyAndVisible()

        self.window = window
    }
}
