/*

 CatalogViewController.swift
 CaptureVideoPreviewLayerExample

 Copyright (c) 2016 Luis Laugga.
 Some rights reserved, all wrongs deserved.

*/

import UIKit

/// The index of the example app: every scenario a reviewer can open, grouped
/// into sections.
final class CatalogViewController: UITableViewController {

    private static let cellIdentifier = "CatalogCell"

    private let sections = Catalog.sections

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Not a large title: the component name does not fit one on a 4.7" screen
        title = "LMCaptureVideoPreviewLayer"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.cellIdentifier)
    }

    // MARK: - UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].scenarios.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellIdentifier, for: indexPath)
        let scenario = self.scenario(at: indexPath)

        var content = cell.defaultContentConfiguration()
        content.text = scenario.title
        content.secondaryText = scenario.description
        content.secondaryTextProperties.numberOfLines = 0
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator

        return cell
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let scenario = self.scenario(at: indexPath)
        let viewController = scenario.makeViewController()
        viewController.title = scenario.title

        navigationController?.pushViewController(viewController, animated: true)
    }

    // MARK: - Scenarios

    private func scenario(at indexPath: IndexPath) -> CatalogScenario {
        sections[indexPath.section].scenarios[indexPath.row]
    }
}

#if DEBUG
#Preview("Catalog") {
    UINavigationController(rootViewController: CatalogViewController())
}
#endif
