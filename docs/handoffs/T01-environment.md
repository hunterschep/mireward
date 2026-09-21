# T01 environment handoff

Status: VERIFIED for editor, templates, hardware inventory, and standalone headless export probe. Project import, visible gameplay, and the game export remain integration gates.
Repository checkpoint: environment verification against working tree based on `102f6f9`; this task owns only this handoff inside the repository.
Verified: 21 September 2026, approximately 04:00 UTC.

## Delivered environment

- Pin: **Godot 4.5.2.stable**, standard GDScript edition. The executing editor reports `4.5.2.stable.official.6ce3de25a`, matching `.godot-version`.
- Editor: `$HOME/.local/share/mireward-tools/godot-4.5.2/Godot.app/Contents/MacOS/Godot`.
- Installed matching templates: `$HOME/Library/Application Support/Godot/export_templates/4.5.2.stable`. All 36 official archive members are installed; `version.txt` contains `4.5.2.stable`.
- Download archives, freshly rechecked official SHA512 list, and release metadata: `$HOME/.local/share/mireward-tools/godot-4.5.2/downloads/`.
- Host: MacBook Pro Mac15,11, Apple M3 Max, 14 CPU cores, 30 GPU cores, 36 GB RAM, macOS 26.6.2 (25G83), native arm64. The built-in 3456 × 2234 Retina display is online. Xcode command-line tools are installed at `/Library/Developer/CommandLineTools`.
- Installation is user-local. No system security or permission settings were changed. No game files depend on an absolute machine path.

## Verification actually performed

The official stable release is `4.5.2-stable`, published 19 March 2026. Both downloaded archives match its freshly retrieved SHA512 list. The initial template file was incomplete at 1,050,718,208 of 1,353,063,159 bytes. No downloader was running. `curl --continue-at -` resumed the same official URL and fetched the remaining 302,344,951 bytes. The completed archive passed SHA512 and every member's ZIP CRC before installation through a staging directory. No duplicate large download was made.

Published and locally verified SHA512 values:

```text
Godot_v4.5.2-stable_macos.universal.zip
0b309feb20b5d6169abbb3a01563dbec0779c2172308c91f0183d0b141b15b5a6a072b388ae2dfc762f7c04da8ae2da9e1e7475d23bc3d24b1824aded2b5d7c0
Godot_v4.5.2-stable_export_templates.tpz
003aa33743f58fb657717f090fc872ed3975e48d08a6012201a2259970d458a63d4d8a83090585307c23455ebfa4e6e0050e1057761c34863536095e3fcfab6c
```

These editor checks ran successfully:

```sh
TOOLS="$HOME/.local/share/mireward-tools/godot-4.5.2"
GODOT="$TOOLS/Godot.app/Contents/MacOS/Godot"
"$GODOT" --headless --version
"$GODOT" --headless --help
codesign --verify --deep --strict "$TOOLS/Godot.app"
file "$GODOT"
cat "$HOME/Library/Application Support/Godot/export_templates/4.5.2.stable/version.txt"
```

The editor is a universal arm64/x86_64 binary. Installed template members and their sizes/CRCs are recorded in `$TOOLS/template-install-manifest.json`; command-line options are saved in `$TOOLS/command-line-help.txt`.

An earlier visible editor probe is preserved in `$TOOLS/display-probe.log`. Its command was `"$GODOT" --project-manager --rendering-method gl_compatibility --rendering-driver opengl3 --quit-after 60`; it exited 0 and initialized `OpenGL API 4.1 Metal - 90.5 - Compatibility - Using Device: Apple - Apple M3 Max`. This establishes earlier display startup, not inspected game visuals. This follow-up did not take over the application UI.

### Standalone template usability probe

A tiny source fixture outside the repository, `$TOOLS/export-probe`, imports, runs, exports, and runs independently of the editor. It writes and reads a JSON file in its own `user://` directory and exits nonzero on failure. The commands below actually ran with exit 0 after correcting the texture-import prerequisite described below:

```sh
cd "$TOOLS/export-probe"
"$GODOT" --headless --path . --import
"$GODOT" --headless --path .
"$GODOT" --headless --path . --export-release macOS builds/EnvironmentProbe.app
./builds/EnvironmentProbe.app/Contents/MacOS/'MIREWARD Environment Probe' --headless
codesign --verify --deep --strict builds/EnvironmentProbe.app
```

Independent exported process output:

```text
ENVIRONMENT_PROBE_PASS engine=4.5.2-stable (official) release=true architecture=arm64 save_roundtrip=true
```

The probe app contains both arm64 and x86_64; only arm64 was executed. Logs: `$TOOLS/export-probe/{import,source-run,export,export-run}.log`. None contains `ERROR`, `SCRIPT ERROR`, or `WARNING`. The initial failed export is retained separately in `export-initial-failure.log`. This fixture proves template usability; it is not the MIREWARD build or its gameplay/save verification.

## Integration instructions

Use the same editor for project import, tests, and export. Create the output directory first and match preset names in `export_presets.cfg`.

For local macOS export, use `binary_format/architecture="universal"`, `codesign/codesign=1` (built-in ad-hoc signing), and `notarization/notarization=0`. **The project also requires `rendering/textures/vram_compression/import_etc2_astc=true`.** Without that setting the pinned engine rejects universal/arm64 export with: `Cannot export for universal or arm64 if ETC2 ASTC texture format is disabled.` Enabling it in the probe resolved the failure and was communicated to the integration lead. The relevant setting appears under `[rendering]` as `textures/vram_compression/import_etc2_astc=true` in `project.godot`.

No Apple developer credentials or publication step was used. The probe's ad-hoc signature passes local verification; distribution signing/notarization is not established.

Compatibility uses `gl_compatibility` with OpenGL. Do not require volumetric fog, SSAO, SSR, SDFGI, decals, or compute shaders. Headless execution uses a dummy display and cannot establish visual quality.

## Input and remaining gates

- `cua.getState()` successfully enumerated enabled native applications and browsers. Native APIs expose screenshots, accessibility state, `pressKey`, click, drag, and scroll. No click or keystroke was sent during this task. Sustained key holding and relative mouse movement are not described by the available API; continuous first-person control remains **UNVERIFIED** until exercised through supported inputs.
- Game import, title launch, actual gameplay, audio, and final host export smoke are owned by integration and remain **UNVERIFIED** here. No game acceptance scenario was run by this environment task.
- R03 disconnected-network gameplay/save/load/settings checks remain **UNVERIFIED**. Network settings were not changed, and a standalone file round trip is not proof of offline quest completion.
- Windows/Linux runtime verification and x86_64 execution remain **UNVERIFIED** on this arm64 macOS host. Their matching official templates are installed.

## Official references checked

- [Official 4.5.2 release and download assets](https://github.com/godotengine/godot-builds/releases/tag/4.5.2-stable)
- [Published SHA512 sums](https://github.com/godotengine/godot-builds/releases/download/4.5.2-stable/SHA512-SUMS.txt)
- [Godot 4.5 command-line workflow](https://docs.godotengine.org/en/4.5/tutorials/editor/command_line_tutorial.html)
- [Godot 4.5 macOS export](https://docs.godotengine.org/en/4.5/tutorials/export/exporting_for_macos.html)
- [Godot 4.5 renderer capabilities](https://docs.godotengine.org/en/4.5/tutorials/rendering/renderers.html)
- [Pinned macOS export implementation](https://github.com/godotengine/godot/blob/4.5.2-stable/platform/macos/export/export_plugin.cpp)
