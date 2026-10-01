local plugin_root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(plugin_root)

local KeySounds = require("keyboard-sound.keys")
local Listener = require("keyboard-sound.listener")
local KeyboardSound = require("keyboard-sound")
local sounds = KeySounds.create()
local termcodes = function(keys)
  return vim.api.nvim_replace_termcodes(keys, true, false, true)
end
local played = {}
local backend = {
  play = function(_, request)
    table.insert(played, request.sound)
  end,
}
local listener = Listener.create({ backend = backend, keys = sounds })

local function assert_equal(actual, expected, label)
  assert(
    vim.deep_equal(actual, expected),
    label .. ": expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual)
  )
end

local function type_keys(keys)
  vim.api.nvim_feedkeys(termcodes(keys), "xt", false)
  vim.wait(30, function()
    return false
  end)
end

local function run_case(keys, expected, label)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  played = {}
  type_keys(keys)
  assert_equal(played, expected, label)
end

local function run_tests()
  for notation, sound in pairs({
    a = 0,
    G = 0,
    o = 0,
    ["2"] = 0,
    ["@"] = 0,
    b = 1,
    E = 1,
    f = 1,
    h = 1,
    p = 1,
    ["3"] = 1,
    ["6"] = 1,
    ["7"] = 1,
    ["9"] = 1,
    ["#"] = 1,
    ["^"] = 1,
    ["&"] = 1,
    ["("] = 1,
    c = 2,
    I = 2,
    q = 2,
    ["4"] = 2,
    ["$"] = 2,
    l = 4,
    S = 4,
    w = 4,
    ["0"] = 4,
    [")"] = 4,
    m = 5,
    X = 5,
    ["1"] = 5,
    ["!"] = 5,
    j = 6,
    ["8"] = 6,
    ["*"] = 6,
    n = 7,
    N = 7,
    [" "] = 3,
    z = 3,
    t = 3,
    ["-"] = 3,
    ["é"] = 3,
    ["😀"] = 3,
    ["<BS>"] = 0,
    ["<C-H>"] = 0,
    ["<C-W>"] = 0,
    ["<Tab>"] = 1,
    ["<CR>"] = 5,
  }) do
    assert_equal(sounds:select(termcodes(notation)), sound, "key " .. notation)
  end
  for _, notation in ipairs({ "<Esc>", "<Left>", "<Right>", "<C-R>", "<C-U>", "<F2>", "<M-x>" }) do
    assert_equal(sounds:select(termcodes(notation)), nil, "silent key " .. notation)
  end
  assert_equal(sounds:select("ab"), nil, "multiple typed keys")
  listener:start()
  run_case("iab<BS><Tab><CR>jn<Space><Esc>", { 0, 1, 0, 1, 5, 6, 7, 3 }, "insert edits")
  run_case("i<BS><C-W><Esc>", {}, "no-op deletion")
  run_case("iword<C-W><Esc>", { 4, 0, 3, 3, 0 }, "delete word")
  run_case("iab<Left><Right><Esc>hlddu", { 0, 1 }, "navigation and normal commands")
  run_case(":let g:keyboard_sound_test = 1<CR>", {}, "command line")
  run_case("Rabc<Esc>", {}, "replace mode")
  run_case("iab<Esc>a<BS><C-H><Esc>", { 0, 1, 0, 0 }, "both backspace encodings")
  run_case("iAé😀<Esc>", { 0, 3, 3 }, "uppercase and UTF-8 typing")
  vim.fn.setreg("a", "register contents")
  run_case("i<C-R>a<Esc>", {}, "register paste is silent")
  run_case("i<C-R><C-R>a<Esc>", {}, "literal register paste is silent")
  run_case("i<C-R><C-O>a<Esc>", {}, "unindented register paste is silent")
  vim.keymap.set("i", "a", "<Esc>dd")
  run_case("ia", {}, "mapped normal command is silent")
  vim.keymap.del("i", "a")
  vim.keymap.set("i", "(", "()<Left>")
  run_case("i(<Esc>", { 1 }, "mapped autopair emits one click")
  vim.keymap.del("i", "(")
  vim.keymap.set("i", "<Tab>", "<Right>")
  run_case("ia<Tab><Esc>", { 0 }, "mapped navigation is silent")
  vim.keymap.del("i", "<Tab>")
  run_case("iabc<Esc>.", { 0, 1, 2 }, "dot repeat is silent")
  vim.fn.setreg("q", "iabc" .. termcodes("<Esc>"))
  run_case("@q", {}, "macro playback is silent")
  played = {}
  vim.api.nvim_paste("pasted\ntext", false, -1)
  vim.wait(30, function()
    return false
  end)
  assert_equal(played, {}, "API paste is silent")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "changed by API" })
  vim.wait(30, function()
    return false
  end)
  assert_equal(played, {}, "programmatic changes are silent")
  vim.bo.buftype = "nofile"
  run_case("iabc<Esc>", {}, "special buffers are silent")
  vim.bo.buftype = ""
  listener:stop()
  run_case("iabc<Esc>", {}, "listener stop")
  listener:start()
  run_case("iabc<Esc>", { 0, 1, 2 }, "listener restart")

  local notifications = {}
  local original_notify = vim.notify
  rawset(vim, "notify", function(message)
    table.insert(notifications, message)
  end)
  KeyboardSound.setup({ is_enabled = false, volume = 37, worker_path = "/missing/keyboard-sound-worker" })
  assert_equal(KeyboardSound.get_status().is_running, false, "muted setup does not spawn")
  KeyboardSound.set_volume(0)
  assert_equal(KeyboardSound.get_status().volume, 37, "mute remembers volume")
  KeyboardSound.enable()
  vim.wait(30, function()
    return false
  end)
  assert_equal(#notifications, 1, "missing executable warned once")
  KeyboardSound.disable()
  assert_equal(KeyboardSound.get_status().is_enabled, false, "disabled status")
  KeyboardSound.set_volume(25)
  vim.wait(30, function()
    return false
  end)
  assert_equal(KeyboardSound.get_status().volume, 25, "positive volume updates level")
  assert_equal(KeyboardSound.get_status().is_enabled, true, "positive volume enables")
  local previous_status = KeyboardSound.get_status()
  for _, volume in ipairs({ -1, 101, 0.5, "50" }) do
    assert_equal(pcall(KeyboardSound.set_volume, volume), false, "invalid volume")
    assert_equal(KeyboardSound.get_status(), previous_status, "invalid volume leaves state")
  end
  KeyboardSound.setup({ is_enabled = false, volume = 0, worker_path = "/missing/keyboard-sound-worker" })
  KeyboardSound.enable()
  assert_equal(KeyboardSound.get_status().volume, 50, "enable restores zero level")
  KeyboardSound.stop()
  KeyboardSound.stop()
  rawset(vim, "notify", original_notify)
  listener:stop()
  print("All keyboard-sound.nvim Lua tests passed.")
end

local is_successful, error_message = xpcall(run_tests, debug.traceback)
if not is_successful then
  io.stderr:write(error_message .. "\n")
  vim.cmd("cquit 1")
end
vim.cmd("qa!")
