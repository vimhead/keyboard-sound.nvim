# keyboard-sound.nvim

Keyboard clicks for Neovim, with stable, case-insensitive key assignments.
Only actual insert-mode edits click; navigation, normal-mode commands, macros,
dot-repeat, and paste stay silent.

The plugin is Lua. A small rodio shared library preloads eight samples and mixes
up to eight voices on a native audio thread. There is no worker process, JSON
protocol, or per-keystroke player startup. Requests older than 80 ms are discarded.

## LazyVim / lazy.nvim

Create `~/.config/nvim/lua/plugins/keyboard-sound.lua`:

```lua
return {
  {
    "vimhead/keyboard-sound.nvim",
    main = "keyboard-sound",
    build = "build.lua",
    opts = { is_enabled = true, volume = 50 },
  },
}
```

Restart Neovim. The installation hook downloads the version-matched shared library
over HTTPS and verifies its SHA-256 against the release manifest before installing.
An existing verified cache is reused. Updating the plugin runs the hook again;
restart Neovim afterward to load the new library.

Requires Neovim 0.10+ built with LuaJIT, an audio output device, curl, and a checksum
utility (sha256sum on Linux, shasum on macOS, PowerShell on Windows).
No Rust toolchain or Nix is required for prebuilt installations.

Prebuilt libraries are provided for:
- macOS 12+ — Apple Silicon and Intel.
- Linux — x86_64 and aarch64, glibc 2.35+ with libasound.so.2 installed.
- Windows — x86_64.

musl Linux requires an explicit source build. On other architectures, build manually
and supply `library_path`. Failed downloads or unsupported platforms never silently invoke Cargo. The checksum manifest and
library are fetched from the same pinned GitHub release; checksums provide integrity
checking, not independent artifact signatures.

lazy.nvim also recognizes the included `build.lua` automatically. Without a plugin
manager, add this directory to your runtimepath, run
`require("keyboard-sound.install").install()` once, then call
`require("keyboard-sound").setup({ is_enabled = true, volume = 50 })`.

## Source builds and Nix

For an explicit source build, replace the build hook with:

```lua
build = function()
  require("keyboard-sound.install").build_from_source()
end,
```

Source builds require Rust 1.88+ and a platform C toolchain. Linux also needs
pkg-config and ALSA development headers (`libasound2-dev` on Debian/Ubuntu).
Or build manually from the plugin directory:

```sh
cargo build --release --locked --manifest-path native/Cargo.toml
```

`nix build` produces a Neovim plugin with its native library bundled.
Use that store directory as a lazy.nvim `dir` and set `build = false`;
no startup download or compilation is needed. `nix build .#native` builds just the library.

`is_enabled` and integer `volume` (0–100) are required setup options. Optional
`library_path` selects an existing shared library. ABI and release versions are checked
before starting audio. Loading a missing/incompatible library warns without interrupting
editing. Libraries stay loaded until Neovim exits, even after muting, to keep native
thread code valid.

## Controls

- `:KeyboardSoundEnable` — enable sound or retry a failed audio device.
- `:KeyboardSoundDisable` — mute, remembering the volume.
- `:KeyboardSoundToggle` — toggle sound.
- `:KeyboardSoundVolume 25` — set volume; positive values enable sound, zero mutes.

The Lua API provides `enable()`, `disable()`, `toggle()`, `set_volume(volume)`,
`get_status()`, and `stop()`. Settings are session-local.

Tab, Enter, Backspace, Ctrl-H, and Ctrl-W click only if they change the buffer.
Special buffers and Replace mode are silent. Insert mappings emit at most one click
per typed key; multi-key mapping triggers are silent. Muting stops the audio thread
and releases the audio device. Errors warn once and never prevent text editing.

## Checks

Run from the plugin directory:

```sh
cargo fmt --manifest-path native/Cargo.toml --check
cargo test --locked --manifest-path native/Cargo.toml
cargo clippy --locked --manifest-path native/Cargo.toml --all-targets -- -D warnings
cargo build --release --locked --manifest-path native/Cargo.toml
nvim --headless -u NONE -l tests/run.lua
nvim --headless -u NONE -l tests/backend.lua
nvim --headless -u NONE -l tests/installer.lua
nvim --headless -u NONE -l tests/native.lua
nix flake check
```

Tests do not play sound. Native smoke tests validate the actual C ABI and sample
decoding without opening an audio device.

Code is [MIT licensed](LICENSE). Samples are CC0;
[provenance](assets/sounds/provenance.json) records their creator, source,
preparation, and checksums. The [CC0 text](assets/licenses/cc0.txt) is bundled.
