local KeySounds = {}
local escaped_special_byte = "\128\254X"
local raw_special_byte = "\128"

function KeySounds.create()
  local sounds = {}
  for sound, characters in pairs({
    [0] = "ago2@",
    [1] = "befhp3679#^&(",
    [2] = "ciq4$",
    [4] = "lsw0)",
    [5] = "mx1!",
    [6] = "j8*",
    [7] = "n",
  }) do
    for character in characters:gmatch(".") do
      sounds[character] = sound
    end
  end

  local special_keys = {
    ["<BS>"] = 0,
    ["<C-H>"] = 0,
    ["<C-W>"] = 0,
    ["<Tab>"] = 1,
    ["<CR>"] = 5,
    ["<NL>"] = 5,
  }
  for notation, sound in pairs(special_keys) do
    sounds[vim.api.nvim_replace_termcodes(notation, true, false, true)] = sound
  end
  return setmetatable({ sounds = sounds }, { __index = KeySounds })
end

function KeySounds:select(key)
  if self.sounds[key] ~= nil then
    return self.sounds[key]
  end
  local character = key:gsub(escaped_special_byte, raw_special_byte)
  if vim.fn.strchars(character) == 1 and character:byte() >= 32 and character:byte() ~= 127 then
    return self.sounds[character:lower()] or 3
  end
  return nil
end

return KeySounds
