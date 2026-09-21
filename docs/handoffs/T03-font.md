# T03 font provenance follow-up

Status: VERIFIED provenance and local notice. Export inclusion is root/T28 integration.

## Finding

Pinned Godot source revision: `6ce3de25aa58466e14ef354703ba8d9791a417da` (4.5.2-stable).

The built-in runtime font in the actual pinned Godot executable is **Open Sans SemiBold version 1.10, Apache-2.0**. Its embedded copyright record is **Digitized data copyright © 2011, Google Corporation.** Manufacturer: Ascender Corporation.

Godot's pinned [thirdparty README](https://github.com/godotengine/godot/blob/4.5.2-stable/thirdparty/README.md#fonts), source lines 325-328, explicitly records this font version, February 2021 Google Fonts acquisition, and Apache 2.0 license. Source lines 334-335 describe unhinted TTF-to-WOFF2 conversion. [SCsub](https://github.com/godotengine/godot/blob/4.5.2-stable/scene/theme/SCsub) compiles that WOFF2 into the default font header; [default_theme.cpp](https://github.com/godotengine/godot/blob/4.5.2-stable/scene/theme/default_theme.cpp) uses `_font_OpenSans_SemiBold`.

The missing OpenSans entry in the pinned COPYRIGHT.txt does not leave the provenance unresolved: the pinned README and exact font binary both identify Apache 2.0. Current master uses a newer Open Sans with different licensing; its license was not copied.

## Files added or changed

- `assets/fonts/NOTICE-OpenSans.txt`: copyright, trademark, attribution, exact binary name records, hashes and source links.
- `assets/fonts/LICENSE-OpenSans-Apache-2.0.txt`: full unmodified Apache 2.0 text from [the Apache Software Foundation](https://www.apache.org/licenses/LICENSE-2.0.txt).
- `docs/asset_manifest.md`: separate embedded-font provenance entry and release inclusion instructions.
- This handoff. No runtime, font binary, export preset, or shared progress file changed.

## Verification actually performed

1. Downloaded the [exact pinned WOFF2](https://raw.githubusercontent.com/godotengine/godot/4.5.2-stable/thirdparty/fonts/OpenSans_SemiBold.woff2) into `/tmp/mireward-OpenSans_SemiBold.woff2`. Size 46,392 bytes; SHA-256 `661e2d9975d3029aeb32bf37b1b963c31c7c3ce08ac1bab2c8ebe27e135c4ec2`.
2. Extracted its name table with existing fontTools 4.54.1 and Brotli installed only into `/tmp/mireward-font-inspect`. Name ID 0 is the Google 2011 copyright, ID 5 is Version 1.10, ID 13 names Apache 2.0, and ID 14 points to the Apache license. No inspection dependency was added to the game.
3. Ran the pinned Godot executable with `--headless --path . --script /tmp/mireward-font-probe.gd`. The probe reads `ThemeDB.fallback_font`, obtains `FontFile.data`, and hashes it using `HashingContext.HASH_SHA256`. Output: `Open Sans SemiBold / SemiBold`, 46,392 bytes, and the identical SHA-256 above. Exit 0.
4. Downloaded the full license text over HTTPS directly from Apache. SHA-256 `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30`.

## Root integration

Add `assets/fonts/*.txt` to the export include filter, preserving existing filters. Include these two notices alongside the release's third-party license files so they are available without development tools. No additional `.woff2`, `.ttf`, or font import is required. Recheck font provenance if the pinned engine or the project theme font changes. Export/package verification remains with root/T28; this task has not exported a build.
