vim.opt.runtimepath:prepend(vim.fn.getcwd())
local Native = require("keyboard-sound.native")
local Platform = require("keyboard-sound.platform")
local function run_tests()
  local path = vim.env.KEYBOARD_SOUND_LIBRARY or Platform.find_library()
  local library = Native.load(path)
  assert(library == Native.load(path), "library was not pinned")
  assert(library.keyboard_sound_check_samples() == 0)
  assert(library.keyboard_sound_start() == 0)
  assert(library.keyboard_sound_start() == 0)
  assert(library.keyboard_sound_configure(0) == 0)
  assert(library.keyboard_sound_configure(101) == 5)
  assert(library.keyboard_sound_play(8, 0) == 5)
  for sound = 0, 7 do
    assert(library.keyboard_sound_play(sound, 0) == 0)
  end
  vim.wait(100, function()
    return false
  end)
  assert(library.keyboard_sound_poll_error() == 0)
  assert(library.keyboard_sound_shutdown() == 0)
  assert(library.keyboard_sound_shutdown() == 0)
  assert(library.keyboard_sound_play(0, 0) == 6)
  print("Shared-library FFI smoke passed without playing audio.")
end
local is_successful, error_message = xpcall(run_tests, debug.traceback)
if not is_successful then
  io.stderr:write(error_message .. "\n")
  vim.cmd("cquit 1")
end
vim.cmd("qa!")
