local Native = {}
local loaded_libraries = {}

local declarations = [[
unsigned int keyboard_sound_abi_version(void);
const char *keyboard_sound_version(void);
unsigned int keyboard_sound_check_samples(void);
unsigned int keyboard_sound_start(void);
unsigned int keyboard_sound_configure(unsigned int volume);
unsigned int keyboard_sound_play(unsigned int sound, unsigned long long queued_at_millis);
unsigned int keyboard_sound_poll_error(void);
unsigned int keyboard_sound_shutdown(void);
]]

function Native.validate(options)
  local release = require("keyboard-sound.release")
  assert(
    tonumber(options.library.keyboard_sound_abi_version()) == release.abi_version,
    "Incompatible audio ABI; reinstall the library."
  )
  assert(
    options.read_string(options.library.keyboard_sound_version()) == release.version,
    "Audio library version differs from the plugin; reinstall it."
  )
  for _, symbol in ipairs({
    "keyboard_sound_check_samples",
    "keyboard_sound_start",
    "keyboard_sound_configure",
    "keyboard_sound_play",
    "keyboard_sound_poll_error",
    "keyboard_sound_shutdown",
  }) do
    assert(options.library[symbol], "Missing audio symbol: " .. symbol)
  end
end

function Native.load(path)
  if loaded_libraries[path] then
    return loaded_libraries[path]
  end
  local is_available, ffi = pcall(require, "ffi")
  assert(is_available, "Audio requires a LuaJIT build of Neovim.")
  assert(
    vim.fn.filereadable(path) == 1,
    "Audio library missing. Run require('keyboard-sound.install').install(), or build_from_source()."
  )
  ffi.cdef(declarations)
  local library = ffi.load(path)
  Native.validate({ library = library, read_string = ffi.string })
  -- Pin loaded code for the lifetime of Neovim; native audio threads must never outlive their library.
  loaded_libraries[path] = library
  return library
end

return Native
