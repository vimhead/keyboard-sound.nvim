local Backend = require("keyboard-sound.backend")
local KeySounds = require("keyboard-sound.keys")
local Listener = require("keyboard-sound.listener")
local Native = require("keyboard-sound.native")
local Platform = require("keyboard-sound.platform")

local KeyboardSound = {}
local active_instance = nil

local function validate_volume(volume)
  assert(
    type(volume) == "number" and volume % 1 == 0 and volume >= 0 and volume <= 100,
    "volume must be an integer from 0 to 100"
  )
end

local function configure_backend(options)
  local instance = options.instance
  instance.listener:reset_feedback()
  if instance.is_enabled and instance.volume > 0 then
    instance.listener:start()
  else
    instance.listener:stop()
  end
  instance.backend:configure({
    is_enabled = instance.is_enabled,
    volume = instance.volume,
    should_retry = options.should_retry,
  })
end

function KeyboardSound.enable()
  assert(active_instance, "Call require('keyboard-sound').setup first")
  active_instance.is_enabled = true
  if active_instance.volume == 0 then
    active_instance.volume = 50
  end
  configure_backend({ instance = active_instance, should_retry = true })
end

function KeyboardSound.disable()
  assert(active_instance, "Call require('keyboard-sound').setup first")
  active_instance.is_enabled = false
  configure_backend({ instance = active_instance, should_retry = false })
end

function KeyboardSound.toggle()
  assert(active_instance, "Call require('keyboard-sound').setup first")
  if active_instance.is_enabled then
    KeyboardSound.disable()
  else
    KeyboardSound.enable()
  end
end

function KeyboardSound.set_volume(volume)
  validate_volume(volume)
  assert(active_instance, "Call require('keyboard-sound').setup first")
  active_instance.is_enabled = volume > 0
  if volume > 0 then
    active_instance.volume = volume
  end
  configure_backend({ instance = active_instance, should_retry = true })
end

function KeyboardSound.get_status()
  assert(active_instance, "Call require('keyboard-sound').setup first")
  return {
    is_enabled = active_instance.is_enabled,
    volume = active_instance.volume,
    is_failed = active_instance.backend.is_failed,
    is_running = active_instance.backend.is_running,
  }
end

function KeyboardSound.stop()
  if active_instance then
    active_instance.listener:stop()
    active_instance.backend:stop()
    vim.api.nvim_del_augroup_by_id(active_instance.augroup)
    active_instance = nil
  end
end

function KeyboardSound.setup(options)
  assert(vim.fn.has("nvim-0.10") == 1, "keyboard-sound.nvim requires Neovim 0.10 or newer")
  assert(type(options) == "table", "setup requires an options table")
  assert(type(options.is_enabled) == "boolean", "is_enabled must be a boolean")
  validate_volume(options.volume)
  assert(options.library_path == nil or type(options.library_path) == "string", "library_path must be a string")
  KeyboardSound.stop()
  local library_path = options.library_path or Platform.find_library()
  local backend = Backend.create({ library_path = library_path, load_library = Native.load, notify = vim.notify })
  local listener = Listener.create({ backend = backend, keys = KeySounds.create() })
  local augroup = vim.api.nvim_create_augroup("KeyboardSound", { clear = true })
  active_instance = {
    backend = backend,
    listener = listener,
    augroup = augroup,
    is_enabled = options.is_enabled,
    volume = options.volume,
  }
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = augroup,
    callback = KeyboardSound.stop,
  })
  local commands = {
    KeyboardSoundEnable = KeyboardSound.enable,
    KeyboardSoundDisable = KeyboardSound.disable,
    KeyboardSoundToggle = KeyboardSound.toggle,
  }
  for name, callback in pairs(commands) do
    vim.api.nvim_create_user_command(name, callback, { force = true })
  end
  vim.api.nvim_create_user_command("KeyboardSoundVolume", function(command)
    KeyboardSound.set_volume(tonumber(command.args))
  end, { nargs = 1, force = true })
  configure_backend({ instance = active_instance, should_retry = false })
end

return KeyboardSound
