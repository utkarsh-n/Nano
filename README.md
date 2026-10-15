# Nano

A native iPhone and iPad sandbox inspired by **The Little Nanoparticle That Could**. Explore several living glass toruses, change their conditions, inspect individual particles, and compare the different ways their worlds grow. The particle ecology is a fictional visual metaphor.

Based on the supplied story and simulation discussion, comic, and material references.

## Open and run

Open `Nano.xcodeproj` in Xcode, select the **Nano** scheme, and choose an iPhone or iPad running iOS 26 or later. Automatic signing is configured for your existing Apple development team. Other developers should select their own team before building for a physical device.

`project.yml` is the XcodeGen project definition. If target membership changes, regenerate the project with `xcodegen generate` when XcodeGen is available.

If iCloud file coordination delays a build from a synced folder, copy this project to a local, non-synced build directory and build there. Keep this checkout as the authoritative source and sync subsequent source changes into that temporary build copy.

## Play with your universe

The app opens on **Your universe**, with a living torus and a small set of gestures:

- **Scatter stardust** plants material at a clear place in the loop. A gold fleck response marks that spot; births happen only when the engine's real conditions are met.
- **Send a pulse** gives up to eight low-energy mobile particles a bounded boost and lights those recipients. It reports when no particle needs one.
- **Warmth**, **Flow**, and **Bonds** open native sheets with tactile dials, accessible step buttons, and explanations beside the control. Tick haptics accompany tuning; action and discovery haptics mark different events.
- **Discoveries** records six genuine milestones without a combined score or required path. Earned discoveries persist with each world.
- Use the world picker to switch, begin a new world, or make a twin. **Dive in** retains individual-particle control. **Lab** retains comparisons and advanced controls.

Actions work while paused; press **Let it unfold** to see time-dependent outcomes. Reduce Motion replaces moving cue effects with a short static fade. Existing world saves are retained; the optional progress field is backward compatible.

## Explore the Lab

- **Observe** shows all experiments; **Compare** displays the selected pair. Aster, Mica, and Nova start with identical particles and the same seed, under different parameter presets.
- **World controls** adjust dust input, energy, polarity bias, turbulence, and link strength. Inputs remain freely editable; there is no combined score or shared resource budget.
- **Inspect** opens one torus. Select a particle to change polarity, add energy, nudge its trajectory, or release its bonds. Mature particles remain at the rim and cannot be nudged.
- **Clone experiment** copies the complete current state and starts a fresh comparison baseline for both copies. Change one condition to observe the resulting divergence.
- **Pause**, **Step**, and **1× / 4× / 12×** control simulated time. Restarting one experiment retains its parameter settings and resets its population and history.

Dust forms new particles. Compatible motion can create bonds and lasting directional preferences. Sustained coherent arrivals become mature rim nodes, supporting expansion and helping later particles inherit tendencies with variation. Story entries are triggered by these events in the engine.

Population includes mature nodes. Coherence is the share of mobile particles above the coherence threshold. Other measures include mature rim count, radius, and radius growth per simulated minute. Growth rate uses the latest 30 simulated seconds, or the elapsed interval since a newer comparison baseline. Input efficiency includes material and energy added through local interventions.

## Source layout and tests

- `Core/`: deterministic, Codable simulation and experiment state; fixed 30 Hz steps; no rendering dependency.
- `App/`: app lifecycle, observation, clock, and local persistence.
- `Features/`: native SwiftUI controls, inspection, and comparison charts.
- `Rendering/` and `Resources/`: torus rendering and artwork.
- `Tests/`: Swift Testing checks for the simulation, run with `swift test`.
- `UITests/`: XCTest checks for world gestures, independent and retained dial settings, paused particle interventions, and native control values, run through the Nano scheme's Test action.

The UI test launch argument `-uitesting` creates a fresh paused lab and bypasses saved user data. Core tests cover clone determinism, parameter effects, inheritance, material accounting, finite state, persistence, story retention, and exact growth-rate windows.

The current sandbox supports up to six experiments and 96 particles per torus. Saves are local to the app's Application Support directory; no account or network service is required by the simulation.

## Rendering and build notes

The first version uses a 2.5D SpriteKit stage: an illustrated glass torus with live particle positions, bonds, dust, trails, and selection. The simulation is an annulus with fictional rules, rather than a 3D physics solver. New artwork uses faceless iridescent pearls, amber/ruby jewels, and sapphire/emerald crystals. Native SwiftUI controls follow the system's light or dark appearance.

The app target enables Swift optimization in development builds because high-speed runs process many fixed simulation steps. Offline measurements with three full worlds found a 24-step batch took about 4.5 ms optimized versus 102 ms unoptimized on this Mac. These are engine measurements, not device frame-rate guarantees. Optimized builds can make stepping through variables in the debugger less direct.

This build was validated on the iPhone 17 Pro simulator with iOS 27. On October 3, 2026, the signed Release build was also installed and successfully launched on your physical iPhone 15 Pro Max running iOS 27.2. The deployment target is iOS 26; sustained physical-device profiling, iPad layout checks, and iOS 26 runtime verification remain future checks.

The dedicated simulator is named **Nano Studio**, so it can run alongside other apps' development simulators. Charts refresh at about 2 Hz and display up to 80 recorded samples per world while retaining the complete stored history window. Numeric readings remain live. This bounds Swift Charts work during 12× playback.

Visual references and actual simulator screenshots are in `Design/`; `design-qa.md` records the review. Source generation prompts include the initial concept history and clearly label the current faceless material revision.


## Public snapshot

See [PUBLICATION.md](PUBLICATION.md) for publication exclusions and setup requirements.
