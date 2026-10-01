vim.opt.runtimepath:prepend(vim.fn.getcwd())
local KeyboardSound = require("keyboard-sound")
local log_path = vim.fn.tempname()
vim.env.KEYBOARD_SOUND_TEST_LOG = log_path
vim.env.KEYBOARD_SOUND_TEST_MODE = "record"
local notices = {}
rawset(vim, "notify", function(message)
  table.insert(notices, message)
end)

local function read_messages()
  if vim.fn.filereadable(log_path) ~= 1 then
    return {}
  end
  local messages = {}
  for _, line in ipairs(vim.fn.readfile(log_path)) do
    table.insert(messages, vim.json.decode(line))
  end
  return messages
end

local function count_clicks()
  local count = 0
  for _, message in ipairs(read_messages()) do
    if message.type == "click" then
      count = count + 1
    end
  end
  return count
end

local function wait_for_count(count)
  assert(
    vim.wait(2000, function()
      return #read_messages() >= count
    end),
    "worker did not receive messages"
  )
end

local function type_keys(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
end

local function run_tests()
  local options = { is_enabled = false, volume = 37, worker_path = vim.fn.getcwd() .. "/tests/fake-worker.py" }
  KeyboardSound.setup(options)
  assert(not KeyboardSound.get_status().is_running)
  KeyboardSound.enable()
  wait_for_count(1)
  assert(KeyboardSound.get_status().is_running)
  local configured = read_messages()[1]
  assert(configured.type == "configure" and configured.is_enabled and configured.volume == 37)
  type_keys("iajn<Esc>")
  wait_for_count(4)
  local messages = read_messages()
  for index, sound in ipairs({ 0, 6, 7 }) do
    assert(messages[index + 1].type == "click")
    assert(messages[index + 1].sound == sound)
    assert(messages[index + 1].queued_at_millis > 0)
  end
  KeyboardSound.set_volume(0)
  assert(not KeyboardSound.get_status().is_running)
  assert(KeyboardSound.get_status().volume == 37)
  type_keys("iajn<Esc>")
  vim.wait(100, function()
    return false
  end)
  assert(count_clicks() == 3)
  KeyboardSound.enable()
  wait_for_count(5)
  assert(read_messages()[5].volume == 37)
  KeyboardSound.set_volume(25)
  wait_for_count(6)
  assert(read_messages()[6].volume == 25)
  options.is_enabled = true
  options.volume = 25
  KeyboardSound.setup(options)
  wait_for_count(7)
  type_keys("ia<Esc>")
  wait_for_count(8)
  assert(count_clicks() == 4, "repeat setup duplicated clicks")
  assert(#notices == 0, "stopped worker produced spurious warning")
  KeyboardSound.stop()
  vim.wait(100, function()
    return false
  end)
  assert(#notices == 0)

  KeyboardSound.setup(options)
  wait_for_count(9)
  type_keys("ia<Esc>:KeyboardSoundDisable<CR>:KeyboardSoundEnable<CR>")
  wait_for_count(10)
  vim.wait(100, function()
    return false
  end)
  assert(count_clicks() == 4, "old click survived mute and re-enable")
  KeyboardSound.stop()

  vim.env.KEYBOARD_SOUND_TEST_MODE = "crash"
  KeyboardSound.setup(options)
  assert(vim.wait(2000, function()
    return KeyboardSound.get_status().is_failed
  end))
  assert(not KeyboardSound.get_status().is_running)
  assert(#notices == 1)
  vim.env.KEYBOARD_SOUND_TEST_MODE = "record"
  KeyboardSound.enable()
  wait_for_count(11)
  assert(not KeyboardSound.get_status().is_failed)
  KeyboardSound.stop()

  vim.env.KEYBOARD_SOUND_TEST_MODE = "error"
  KeyboardSound.setup(options)
  assert(vim.wait(2000, function()
    return KeyboardSound.get_status().is_failed
  end))
  assert(#notices == 2)
  local previous_clicks = count_clicks()
  type_keys("iajn<Esc>")
  vim.wait(100, function()
    return false
  end)
  assert(count_clicks() == previous_clicks, "failed device still received clicks")
  KeyboardSound.stop()
  vim.fn.delete(log_path)
  print("All keyboard-sound.nvim subprocess tests passed.")
end

local is_successful, error_message = xpcall(run_tests, debug.traceback)
if not is_successful then
  KeyboardSound.stop()
  vim.fn.delete(log_path)
  io.stderr:write(error_message .. "\n")
  vim.cmd("cquit 1")
end
vim.cmd("qa!")
