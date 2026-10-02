vim.opt.runtimepath:prepend(vim.fn.getcwd())
local KeyboardSound = require("keyboard-sound")
local Native = require("keyboard-sound.native")
local notices, clicks, volumes = {}, {}, {}
local start_count, stop_count, load_count = 0, 0, 0
local error_code = 0
local should_fail_loading = false
rawset(vim, "notify", function(message)
  table.insert(notices, message)
end)
rawset(Native, "load", function(_)
  load_count = load_count + 1
  assert(not should_fail_loading, "test missing library")
  return {
    keyboard_sound_start = function()
      start_count = start_count + 1
      return 0
    end,
    keyboard_sound_shutdown = function()
      stop_count = stop_count + 1
      return 0
    end,
    keyboard_sound_configure = function(volume)
      table.insert(volumes, volume)
      return 0
    end,
    keyboard_sound_play = function(sound, timestamp)
      table.insert(clicks, { sound = sound, timestamp = timestamp })
      return 0
    end,
    keyboard_sound_poll_error = function()
      return error_code
    end,
  }
end)

local function type_keys(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
  vim.wait(30, function()
    return false
  end)
end

local function run_tests()
  local options = { is_enabled = false, volume = 37, library_path = "/fake/library" }
  KeyboardSound.setup(options)
  assert(not KeyboardSound.get_status().is_running and load_count == 0)
  KeyboardSound.enable()
  assert(start_count == 1 and volumes[1] == 37 and KeyboardSound.get_status().is_running)
  type_keys("iajn<Esc>")
  assert(#clicks == 3)
  for index, sound in ipairs({ 0, 6, 7 }) do
    assert(clicks[index].sound == sound and clicks[index].timestamp > 0)
  end
  KeyboardSound.set_volume(0)
  assert(stop_count == 1 and not KeyboardSound.get_status().is_running)
  assert(KeyboardSound.get_status().volume == 37)
  type_keys("iajn<Esc>")
  assert(#clicks == 3)
  KeyboardSound.enable()
  assert(start_count == 2 and volumes[2] == 37)
  KeyboardSound.set_volume(25)
  assert(volumes[3] == 25)
  options.is_enabled = true
  options.volume = 25
  KeyboardSound.setup(options)
  type_keys("ia<Esc>")
  assert(#clicks == 4, "repeat setup duplicated clicks")
  type_keys("ia<Esc>:KeyboardSoundDisable<CR>:KeyboardSoundEnable<CR>")
  assert(#clicks == 4, "old click survived mute and re-enable")
  error_code = 2
  assert(vim.wait(1000, function()
    return KeyboardSound.get_status().is_failed
  end))
  vim.wait(200, function()
    return false
  end)
  assert(#notices == 1, "device error did not warn exactly once")
  type_keys("iajn<Esc>")
  assert(#clicks == 4, "failed device still received clicks")
  error_code = 0
  KeyboardSound.enable()
  assert(not KeyboardSound.get_status().is_failed)
  type_keys("in<Esc>")
  assert(#clicks == 5 and clicks[5].sound == 7)
  KeyboardSound.stop()
  vim.wait(200, function()
    return false
  end)
  assert(#notices == 1, "stopped timer produced spurious warning")

  should_fail_loading = true
  KeyboardSound.setup(options)
  vim.wait(30, function()
    return false
  end)
  assert(KeyboardSound.get_status().is_failed and not KeyboardSound.get_status().is_running)
  assert(#notices == 2)
  should_fail_loading = false
  KeyboardSound.enable()
  assert(not KeyboardSound.get_status().is_failed and KeyboardSound.get_status().is_running)
  KeyboardSound.stop()

  local valid = {
    keyboard_sound_abi_version = function()
      return 1
    end,
    keyboard_sound_version = function()
      return "0.2.0"
    end,
    keyboard_sound_check_samples = true,
    keyboard_sound_start = true,
    keyboard_sound_configure = true,
    keyboard_sound_play = true,
    keyboard_sound_poll_error = true,
    keyboard_sound_shutdown = true,
  }
  local validation = {
    library = valid,
    read_string = function(value)
      return value
    end,
  }
  Native.validate(validation)
  rawset(valid, "keyboard_sound_abi_version", function()
    return 2
  end)
  assert(not pcall(Native.validate, validation))
  rawset(valid, "keyboard_sound_abi_version", function()
    return 1
  end)
  valid.keyboard_sound_version = function()
    return "0.1.0"
  end
  assert(not pcall(Native.validate, validation))
  print("All keyboard-sound.nvim native backend tests passed.")
end

local is_successful, error_message = xpcall(run_tests, debug.traceback)
KeyboardSound.stop()
if not is_successful then
  io.stderr:write(error_message .. "\n")
  vim.cmd("cquit 1")
end
vim.cmd("qa!")
