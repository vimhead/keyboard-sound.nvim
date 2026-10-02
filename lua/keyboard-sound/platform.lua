local Platform = {}

function Platform.detect(options)
  local targets = {
    OSX = { x64 = "x86_64-apple-darwin", arm64 = "aarch64-apple-darwin" },
    Linux = { x64 = "x86_64-unknown-linux-gnu", arm64 = "aarch64-unknown-linux-gnu" },
    Windows = { x64 = "x86_64-pc-windows-msvc" },
  }
  local target = targets[options.os] and targets[options.os][options.arch]
  assert(
    target,
    "Unsupported audio platform: " .. options.os .. "/" .. options.arch .. ". Build from source explicitly."
  )
  local extension = ({ OSX = ".dylib", Linux = ".so", Windows = ".dll" })[options.os]
  return {
    target = target,
    extension = extension,
    library_file = (options.os == "Windows" and "" or "lib") .. "keyboard_sound" .. extension,
    asset = "keyboard-sound-" .. target .. extension,
  }
end

function Platform.current()
  local is_available, ffi = pcall(require, "ffi")
  assert(is_available, "keyboard-sound.nvim requires a LuaJIT build of Neovim")
  return Platform.detect({ os = ffi.os, arch = ffi.arch })
end

function Platform.get_cache_path(platform)
  local release = require("keyboard-sound.release")
  return vim.fn.stdpath("data") .. "/keyboard-sound.nvim/" .. release.version .. "/" .. platform.asset
end

function Platform.get_plugin_root()
  return vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
end

function Platform.find_library()
  local platform = Platform.current()
  local built_library = Platform.get_plugin_root() .. "/native/target/release/" .. platform.library_file
  if vim.fn.filereadable(built_library) == 1 then
    return built_library
  end
  return Platform.get_cache_path(platform)
end

return Platform
