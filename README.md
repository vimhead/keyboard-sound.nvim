# keyboard-sound.nvim

Low-latency keyboard clicks for Neovim. Eight bundled samples have stable,
case-insensitive key assignments. Only actual insert-mode edits click;
navigation, normal-mode commands, macros, dot-repeat, and paste stay silent.

## Install

Requires Neovim 0.10+, Rust 1.88+, and an audio output device.
Linux builds also need a C compiler, pkg-config, and ALSA development headers
(`libasound2-dev` on Debian/Ubuntu). macOS uses CoreAudio; Windows uses WASAPI.

With lazy.nvim and a local checkout:

```lua
{
  dir = vim.fn.expand("~/development/nvim/keyboard-sound.nvim"),
  build = "cargo build --release --locked --manifest-path worker/Cargo.toml",
  opts = { is_enabled = true, volume = 50 },
  config = function(_, opts)
    require("keyboard-sound").setup(opts)
  end,
}
```

Without a plugin manager, add this directory to your runtimepath, build the
worker from the plugin directory, then call `require("keyboard-sound").setup`
with the same options.

`is_enabled` and integer `volume` (0–100) are required. An optional
`worker_path` selects an existing worker executable instead of the bundled build.
Building is explicit: the plugin never downloads or compiles anything on startup.

## Controls

- `:KeyboardSoundEnable` — enable sound or retry a failed audio device.
- `:KeyboardSoundDisable` — mute, remembering the volume.
- `:KeyboardSoundToggle` — toggle sound.
- `:KeyboardSoundVolume 25` — set volume; positive values enable sound, zero mutes.

The Lua API also provides `enable()`, `disable()`, `toggle()`,
`set_volume(volume)`, `get_status()`, and `stop()`.
Settings are session-local; startup options are the source of truth.

Tab, Enter, Backspace, Ctrl-H, and Ctrl-W click only if they change the buffer.
Special buffers and Replace mode are silent. Insert mappings that produce several
edits emit at most one click per typed key. Multi-key mapping triggers are silent.

A persistent Rust worker preloads the samples, mixes up to eight voices, keeps a
bounded eight-click queue, and discards requests older than 80 ms. Muting releases
the worker and audio device. Audio failures warn once and never block editing.

## Checks

Run from the plugin directory:

```sh
cargo test --locked --manifest-path worker/Cargo.toml
cargo clippy --locked --manifest-path worker/Cargo.toml --all-targets -- -D warnings
cargo build --release --locked --manifest-path worker/Cargo.toml
worker/target/release/keyboard-sound-worker --check
python3 tests/test_worker.py
nvim --headless -u NONE -l tests/run.lua
nvim --headless -u NONE -l tests/backend.lua
```

The subprocess tests require Python 3; they use a fake audio worker and do not
play sound. `--check` decodes samples without opening an audio device.

Code is [MIT licensed](LICENSE). Samples are CC0;
[provenance](assets/sounds/provenance.json) identifies their original creator,
source, preparation, and checksums. The [CC0 text](assets/licenses/cc0.txt) is bundled.
