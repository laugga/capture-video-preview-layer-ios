# AGENTS.md

## What this is

**`CaptureVideoPreviewLayer`** is a Swift package whose one class,
`LMCaptureVideoPreviewLayer`, is a preview layer for an `AVCaptureSession`
with a GPU blur filter — a near-drop-in replacement for AVFoundation's
`AVCaptureVideoPreviewLayer` that adds one animatable `blur` property in
`[0,1]`. It is a `CAMetalLayer` subclass; the blur is a separable Gaussian
written in the Metal Shading Language.

It does not sit in the capture session the way Apple's layer does. It adds an
`AVCaptureVideoDataOutput` to the session you hand it, and renders each frame
from `captureOutput(_:didOutput:from:)`. If the session already has an
`AVCaptureVideoDataOutput`, it hijacks that one and forwards the delegate
callback on to you.

**Swift, Metal and Swift Package Manager.** The library, the tests and the
example are Swift. The only non-Swift sources are the `.metal` shaders and the
one C header whose structures both Swift and the shaders read — see
[Project layout](#project-layout). There is no CocoaPods, no podspec, no
Rakefile and no library xcodeproj any more; `Package.swift` is the build.

**Nothing depends on this component today.** It is a standalone Lightmate
component, not a dependency of any repository in the organisation:
`lightmate-app-ios` uses Apple's own `AVCaptureVideoPreviewLayer`, and no other
laugga repository references this one. The only release is the `0.1.0` tag,
the old OpenGL ES CocoaPod, which predates the package entirely. Treat the
public API as unpublished: no consumer is pinned to it.

It is, in the author's own words in the README, an R&D project.

## Build and test

Run from the repository root:

```bash
# Build and run the 4 tests
xcodebuild test -scheme CaptureVideoPreviewLayer \
  -destination 'platform=iOS Simulator,name=iPhone SE (3rd generation)'

# Build the example app
xcodebuild build \
  -project Example/CaptureVideoPreviewLayer.xcodeproj \
  -scheme Example \
  -destination 'platform=iOS Simulator,name=iPhone SE (3rd generation)'
```

The `Makefile`s wrap the same commands: `make build`, `make test` and `clean`
at the root are the package's; `make -C Example build`, `make -C Example test`
and `make -C Example archive` are the Example app's.

These are the same two steps `.github/workflows/ci.yml` runs on every pull
request (`Build and test`). If the simulator name is ambiguous because it is
installed for more than one runtime, use `id=<udid>` from
`xcrun simctl list devices available` instead of `name=`.

**`swift build` and `swift test` do not work.** The package is iOS-only and
needs UIKit, AVFoundation and a Metal device, so it has to go through
`xcodebuild` with an iOS Simulator destination.

**Use a 2x simulator, such as the iPhone SE.** Two of the four tests compare
the rendered blur against reference PNGs captured at a 2x scale, and they
`XCTSkipUnless(UIScreen.main.nativeScale == 2)`. On an iPhone 15 or 17 (3x)
they are *skipped*, not failed, so a green run there tests almost nothing. All
four pass on an iPhone SE. If `make test` prints `Testing on: platform=iOS
Simulator,id=` and fails, the machine has no iPhone SE simulator: create one
with `xcrun simctl create "iPhone SE (3rd generation)"
com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation`, or pass a 2x
iPad's udid as `TEST_DEVICE` — all four pass on an iPad (A16) too.

**The Metal toolchain can be missing.** Recent Xcode versions ship it as a
separate component, and without it the `.metal` sources do not compile. CI
downloads it with `xcodebuild -downloadComponent MetalToolchain`; do the same
locally if the build fails on the shaders.

**There is no lint step.** No SwiftLint, no swift-format. The commands above
are the whole gate.

## Run the example app

`Example/CaptureVideoPreviewLayer.xcodeproj` is the example app, laid out
after the *UI Component Repository Example App Pattern* note in Notion, the
same shape as `HorizontalPicker`'s. It is the only place the layer is exercised
on screen. The project references the package at the repository root as a
local package (`..`), so there is nothing to install; open it and run the
shared `Example` scheme.

- **Naming** — the app is called *CaptureVideoPreviewLayer*, but its target
  is `Example`. The target, its product and its Swift module are all
  `Example` — `PRODUCT_NAME = $(TARGET_NAME)`, so the build is `Example.app`
  and `deploy` uploads `Example.ipa`. The name on the home screen is the
  display name, `INFOPLIST_KEY_CFBundleDisplayName = CaptureVideoPreviewLayer`,
  set in both configurations. That is `template-library-swift`'s Example
  exactly: a module named `CaptureVideoPreviewLayer` would clash with the
  package it imports, so only the display name carries the library's Name. The
  project and `Example/CaptureVideoPreviewLayer/` keep the library's name, as
  the template's do. The display name is also what the Firebase app is
  nicknamed — whatever the build calls itself (ops `CONVENTIONS.md` →
  *Firebase app nickname*) — so drop it and the app is called `Example`, on a
  phone and in Firebase. The bundle identifier is
  `com.laugga.capture-video-preview-layer-example` (`CONVENTIONS.md` → *Names*
  → *Bundle identifier*), which the Firebase app is registered for.
- **Layout** — `Example/CaptureVideoPreviewLayer/` is a synchronized folder,
  so a file added under it is in the target with no project edit. `App/` is
  the app and scene delegates; `Catalog/` is the index the app opens on and
  nothing else; `Scenarios/<Section>/` holds one view controller per scenario,
  each with a `#Preview`; `Resources/` holds the asset catalog and the launch
  storyboard. The Info.plist is generated from `INFOPLIST_KEY_*` build settings.
- **Scenarios** — one so far, `Basics → Default`: a capture session, the back
  camera, press to blur in, drag up to ease it off, release to blur out, and a
  button to pause the session. Add a scenario by writing its view controller
  and listing it in `Catalog/Catalog.swift`; do not add a section with nothing
  in it.

Each visit to a scenario creates a new preview layer, and the `CADisplayLink`
gotcha below means none of them is freed, so opening a scenario repeatedly in
one run leaks.

The Simulator has no camera. Under `#if targetEnvironment(simulator)` the
example swaps in `MockCaptureVideoPreviewLayerInternal`, which feeds the layer a
generated colour grid, so the on-screen path can still be checked there. The
real camera path only runs on a device.

## Try it

The Example app has a root `deploy`, so opening a pull request or pushing to
one builds, archives and uploads it to Firebase App Distribution — the same
contract every UI-surface repository follows (`CONVENTIONS.md` → *UI surfaces
only*).

```bash
make deploy   # delegates to $(MAKE) -C Example deploy
```

- **Configuration** — `Example/Makefile` names the destination directly as
  `FIREBASE_PROJECT`/`FIREBASE_APP`/`FIREBASE_GROUPS`: project
  `lightmate-development-390f6` ("Lightmate Development"), app
  `com.laugga.capture-video-preview-layer-example`, nicknamed
  *CaptureVideoPreviewLayer* (`1:480717957783:ios:332799481e2ba7648f97d2`).
  The Example app links no Firebase SDK, so there is no
  `GoogleService-Info.plist` to read these from instead.
- **Renaming the Firebase app** — a nickname is an edit in place that keeps
  the app id, its testers and its releases; a bundle identifier cannot change,
  and a new one is a new app. The `firebase` CLI has no rename command, so it
  is `PATCH
  https://firebase.googleapis.com/v1beta1/projects/<project>/iosApps/<app id>?updateMask=displayName`
  with `{"displayName": "…"}`, sent with a `gcloud auth print-access-token`
  bearer token and `x-goog-user-project` set to the project.
- **Build and signing** — Debug configuration, automatic signing, team
  `JJC3QT2D2L`. `Example/Support/ExportOptions.plist` exports with
  `method = debugging`, so only devices registered in that Apple team can
  install the build.
- **Version** — `Example/Scripts/Version/version.sh`, vendored unchanged from
  `laugga/ops`'s `share/version/` (`CONVENTIONS.md` → *Versioning*).
  `make -C Example deploy` refuses a dirty tree or unpushed commits before
  archiving.
- **Goes to** — Firebase App Distribution, group `internal`. The group and
  the machine's Firebase CLI login are host setup; `deploy` never creates
  either.
- **One-time setup** — the machine running `deploy` must be signed in to
  Apple team `JJC3QT2D2L` in Xcode, and to the Firebase CLI
  (`firebase login`). A new tester's device is registered in that Apple team
  by hand before it can install a build.
- **What it prints** — a tester install link, which goes in this section of
  the pull request description, replaced wholesale on the next build rather
  than appended.

## Project layout

| Path | What's there |
|---|---|
| `Package.swift` | The build. Two targets and a test target, iOS 17.0. |
| `Makefile` | The package's `build`, `test` and `clean`, wrapping `xcodebuild` (CONVENTIONS.md → Swift library). `deploy` is the only one of the Example's targets exposed here, and it delegates to `Example/Makefile`. |
| `Sources/CaptureVideoPreviewLayer/` | The library. `LMCaptureVideoPreviewLayer.swift` is the layer and the render pipeline; `…Internal.swift` owns the capture session and the sample buffer; `…Utilities.swift` has `TextureInstance`, metallib loading and pipeline state creation; `…Shaders.swift` holds the shader function names; `…GaussianFilterKernel.swift` the kernel tables. |
| `Sources/CaptureVideoPreviewLayer/LMCaptureVideoPreviewLayerShaders.metal` | The shaders, compiled at build time into the target's default metallib. |
| `Sources/CaptureVideoPreviewLayerShaderTypes/` | A C target whose only job is `include/LMCaptureVideoPreviewLayerStructures.h`: the buffer indices, `VertexData_t` and `FilterUniforms_t`, read by both Swift and the `.metal` file. The `.c` file is empty on purpose — SwiftPM will not build a target without a compilation unit. |
| `Tests/CaptureVideoPreviewLayerTests/` | The 4 tests, the `UIImage` comparison helper, a mock pipeline and `Samples.xcassets` with the source and reference images. |
| `Example/CaptureVideoPreviewLayer.xcodeproj`, `Example/CaptureVideoPreviewLayer/` | The example app, with its shared `Example` scheme, and its `App/`, `Catalog/`, `Scenarios/` and `Resources/`. `Example/Makefile` owns its `build`, `test`, `archive` and `deploy`; `Example/Scripts/Version/` is vendored unchanged from `ops`'s `share/version/`; `Example/Support/ExportOptions.plist` configures the archive export. |
| `Docs/` | `features.md`, `figures/` (the README's GIF) and `matlab/` — the MATLAB script that generates the filter kernels, plus its plots. |
| `CHANGELOG.md` | Human-written; the Metal, Swift and SPM changes sit under `Unreleased`. |

## Conventions

Branch names, pull request titles and bodies, and how a pull request references
its task are the same in every Laugga Practice repository and are documented in
[`laugga/ops`](https://github.com/laugga/ops). What is specific here:

- **The default and integration branch is `main`.** Open pull requests against
  it.
- **Every type carries the `LM` prefix; the repository and the module do
  not.** The repository is `capture-video-preview-layer-ios` and the package,
  product and module are `CaptureVideoPreviewLayer`, both as the Components row
  names them (`CONVENTIONS.md` → *Names*); the class is
  `LMCaptureVideoPreviewLayer`, and the mismatch is deliberate. Keep public
  types on `LM`; do not rename them toward the module name. Files are named
  after the type they hold, so they keep `LM` too. (The repository was
  `VisualEffectCaptureVideoPreviewLayer` and the module
  `LMCaptureVideoPreviewLayer` until `LM-641`; the types were renamed from the
  original `LAU` prefix before that. No consumer was pinned to either name.)
- **Every file under `Sources/` opens with the MIT-style license header block**
  carrying the file name and the module, `CaptureVideoPreviewLayer`. Copy it
  into new files.
- **Document with `///`**, and keep the public surface small. What is public is
  what is implemented: `init(session:)`, `session`, `blur`,
  `setBlur(_:animated:)` and `videoGravity`. Do not add stubs that only mirror
  `AVCaptureVideoPreviewLayer`'s interface.
- **Log through the module's `log`** (`os.Logger`, in `…Utilities.swift`), not
  `print`.
- **Anything both Swift and the shaders read goes in
  `LMCaptureVideoPreviewLayerStructures.h`**, and must be valid in both C and
  the Metal Shading Language. Do not duplicate a layout as a Swift struct: the
  shared header is what guarantees the two sides agree.

## Gotchas

- **The metallib is looked up in `Bundle.module`, then `Bundle.main`.** SwiftPM
  compiles the `.metal` file into the resource bundle it generates for the
  target. If the layer draws nothing, check the log for `Could not load the
  default metallib` before suspecting the rendering code.

- **The offscreen quads flip the texture coordinates vertically, on purpose.**
  Metal draws a texture's first row at the top of the viewport, so the flip is
  what keeps every offscreen pass an exact copy of its source. And
  `render(in:)` flips the context, because `getBytes` returns rows top-down.
  Removing either "fix" turns the image upside down on alternate passes or in
  snapshots.

- **Round offscreen texture sizes to whole pixels, and clear them.** A
  fractional size left the last pixel column unrasterized, and clamp-to-edge
  sampling smeared that uninitialised memory into the blur. It showed up as two
  renders of the same frame differing by about 2%.

- **The blur implementation is selected by two flags at the top of
  `LMCaptureVideoPreviewLayer.swift`.** `filterBoundsEnabled = false` and
  `filterBilinearTextureSamplingEnabled = true` choose which of three fragment
  functions the blur pipeline uses. At these settings the other two are
  unreachable. Behaviour you cannot reproduce may be behind a flag that is off.

- **The kernel tables are generated.** `…GaussianFilterKernel.swift` holds the
  output of `docs/matlab/LMCaptureVideoPreviewLayer.m`. Regenerate rather than
  hand-edit, and keep `kFilterKernelMaxSamples` and `kFilterKernelMaxWeights` in
  the shared header large enough for them.

- **The tests reach into internal API.** They inject
  `MockLMCaptureVideoPreviewLayerInternal` through the public `internal`
  property and call `drawPixelBuffer()` through `@testable import`. Changing
  either breaks the tests although neither is API anyone was meant to use. The
  example has its own, similar stand-in in
  `MockCaptureVideoPreviewLayerInternal.swift`; update both.

- **The `CADisplayLink` retains its target**, so a layer never deallocates and
  its textures leak if preview layers are created repeatedly. Known, not yet
  fixed.

- **`Docs/matlab/LMCaptureVideoPreviewLayer` is a Photoshop file with no
  extension**, sitting next to the `.m` script of the same name. Not a
  directory, not MATLAB. Leave it alone.

## Definition of done

Before opening a pull request, confirm:

- [ ] `xcodebuild test -scheme CaptureVideoPreviewLayer -destination 'platform=iOS Simulator,name=iPhone SE (3rd generation)'` runs 4 tests with 0 failures and 0 skipped
- [ ] The example builds with the command above, or `make -C Example build`
- [ ] If a structure shared with the shaders changed, it changed in `LMCaptureVideoPreviewLayerStructures.h`, not in a Swift copy
- [ ] `CHANGELOG.md` has an `Unreleased` line if a user of the package would notice the change
- [ ] `make deploy` ran and the pull request description's `## Try it` section carries the fresh install link
