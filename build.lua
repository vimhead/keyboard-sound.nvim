local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
for _, name in ipairs({ "platform", "release", "installer", "install" }) do
  package.preload["keyboard-sound." .. name] = assert(loadfile(root .. "/lua/keyboard-sound/" .. name .. ".lua"))
end
require("keyboard-sound.install").install()
