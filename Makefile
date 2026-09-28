# `make` lists the targets. This Makefile is the package's build, test and
# clean (CONVENTIONS.md → Swift library, OPS-12); the Example app has its own
# in Example/. UIKit-only, so `swift build`/`swift test` build for macOS and
# fail on `import UIKit`/`import AVFoundation` — every target goes through
# xcodebuild and an iOS Simulator instead.
#
# deploy is the only one of the Example's targets exposed here, and it
# delegates — it is the try-it signal an agent and repo-doctor read off this
# file.

SCHEME := CaptureVideoPreviewLayer

BUILD_DEST := generic/platform=iOS Simulator

.DEFAULT_GOAL := help
.PHONY: help build test clean deploy

help: ## List the targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  make %-8s %s\n", $$1, $$2}'

build: ## Build the library for iOS Simulator
	xcodebuild build -scheme $(SCHEME) -destination '$(BUILD_DEST)'

# Defaults to the iPhone SE, not the newest available simulator: two of the
# four tests compare against reference images captured at a 2x scale and are
# *skipped*, not failed, on a 3x device (iPhone 15/16/17) — a green run there
# tests almost nothing. Selected by id, not name=: an unqualified name= picks
# OS=latest, and the SE isn't offered on every runtime, so name= alone can
# fail to resolve. Override with TEST_DEVICE (a udid) for a different 2x device.
test: ## Run the package's unit tests on a 2x iPhone simulator (TEST_DEVICE= picks a udid)
	@id="$${TEST_DEVICE:-$$(xcrun simctl list devices available -j | \
		jq -r '.devices | to_entries[] | .key as $$rt | .value[] | \
			select(.name | test("iPhone SE")) | "\($$rt)\t\(.udid)"' | \
		sort | tail -1 | cut -f2)}"; \
	dest="$${TEST_DEST:-platform=iOS Simulator,id=$$id}"; \
	echo "Testing on: $$dest"; \
	xcodebuild test -scheme $(SCHEME) -destination "$$dest"

clean: ## Remove the package's build products
	xcodebuild clean -scheme $(SCHEME)
	rm -rf .build

# Work on the Example app directly with `make -C Example build|test|archive`,
# including `make -C Example clean` — this root clean is the package's only.
# Only deploy is exposed here, because only deploy is the convention's promise
# to the outside: it says this repository has something to try.

deploy: ## Build and upload the Example app to Firebase App Distribution
	$(MAKE) -C Example deploy
