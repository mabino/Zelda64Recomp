# Building and packaging on macOS

This guide builds the macOS app locally from a ROM supplied by the user. The ROM is used to generate the recompiled game code. Neither the raw retail ROM nor its decompressed build input is copied into the `.app`, ZIP, or DMG. The finished app still asks for the standard retail ROM the first time it runs; do not select the decompressed build input there.

Use the North American Majora's Mask N64 revision 1 ROM. The build helper accepts a normal retail `.z64`, `.n64`, or `.v64` dump and also accepts the corresponding already-decompressed ROM. It validates the known ROM checksums before code generation. Other regions, revisions, modified ROMs, and incorrect dumps are rejected.

## Requirements

- macOS 13 or later and Xcode Command Line Tools (`xcode-select --install`).
- Git with submodule support, CMake, Ninja, and Python 3.
- Homebrew for CMake and Ninja if they are not already installed:

  ```sh
  brew install cmake ninja
  ```

- MacPorts with universal SDL2, FreeType, and libiconv, plus LLVM 18 tools. Install the MacPorts package definitions used by CI:

  ```sh
  sudo port selfupdate
  sudo port install libiconv +universal
  sudo port install libsdl2 +universal
  sudo port install freetype +universal
  sudo port install clang-18 llvm-18
  ```

  The CI MacPorts configuration selects the `aqua` and `metal` variants and deselects `x11` globally. Match those defaults in `/opt/local/etc/macports/variants.conf` when setting up MacPorts locally; merge `+aqua +metal -x11` into existing settings rather than replacing them.

The script installs the small Python dependencies it needs into a virtual environment under the build directory. It does not install Homebrew, MacPorts, or system packages for you.

## Clone and build

Clone this fork with all submodules, then run the helper with the path to your ROM dump:

```sh
git clone --recurse-submodules https://github.com/mabino/Zelda64Recomp.git
cd Zelda64Recomp
./.github/macos/build_local.sh "/path/to/your/Majora's Mask ROM.z64"
```

The helper validates/decompresses the input into the ignored `build-macos-local/rom/` directory, builds `N64Recomp` and `RSPRecomp`, generates the game code, and builds a universal Apple Silicon and Intel app bundle. It uses temporary TOML files so the checked-in build configs and the supplied ROM are left in place. The build and packaging outputs are:

- `build-macos-local/app/Zelda64Recompiled.app`
- `build-macos-local/package/Zelda64Recompiled-macOS-universal.zip`
- `build-macos-local/package/Zelda64Recompiled-macOS-universal.dmg`

An alternate build directory can be supplied as the second argument:

```sh
./.github/macos/build_local.sh "/path/to/your/Majora's Mask ROM.v64" "$HOME/Builds/mm-recomp"
```

Open the `.dmg` and drag `Zelda64Recompiled.app` to Applications. The app is ad hoc signed for local use and is not notarized; macOS may require Control-click > Open the first time. Distribution signing and notarization require the publisher's Apple Developer credentials. At first launch, select your normal retail ROM in the app. The generated decompressed ROM is a build input only.

## Run settings tests

After configuring the project with CMake, build and run the settings tests with:

```sh
cmake --build build-arm64 --target Zelda64SettingsTests
ctest --test-dir build-arm64 --output-on-failure
```

Replace `build-arm64` with the CMake build directory you configured. The tests cover control scan state, control mapping defaults and JSON persistence, and the quit-confirmation preference.

## Troubleshooting

- If the helper reports a checksum error, verify that the dump is the unmodified North American revision 1 ROM. Byte-swapped `.n64` and `.v64` dumps are accepted.
- If a MacPorts tool is installed outside `/opt/local`, set `MACPORTS_PREFIX` to its prefix. Individual paths can be overridden with `PATCHES_CC`, `PATCHES_LD`, and `PATCHES_AR`.
- Generated recompiler sources live in ignored `RecompiledFuncs/`, `RecompiledPatches/`, and `rsp/` paths. The ROM and binaries stay in the selected build directory. Do not delete the ROM if you plan to rerun the app build without redoing code generation.
