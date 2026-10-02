vim.opt.runtimepath:prepend(vim.fn.getcwd())
local Installer = require("keyboard-sound.installer")
local Platform = require("keyboard-sound.platform")
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")

local function read_bytes(path)
  local file = assert(io.open(path, "rb"))
  local bytes = file:read("*a")
  file:close()
  return bytes
end

local function write_bytes(request)
  local file = assert(io.open(request.path, "wb"))
  file:write(request.bytes)
  file:close()
end

local function run_tests()
  for _, options in ipairs({
    { os = "OSX", arch = "x64" },
    { os = "OSX", arch = "arm64" },
    { os = "Linux", arch = "x64" },
    { os = "Linux", arch = "arm64" },
    { os = "Windows", arch = "x64" },
  }) do
    local platform = Platform.detect(options)
    assert(platform.asset:find(platform.target, 1, true))
    assert(platform.library_file:sub(-#platform.extension) == platform.extension)
  end
  assert(not pcall(Platform.detect, { os = "Windows", arch = "arm64" }))
  assert(not pcall(Platform.detect, { os = "Linux", arch = "x86" }))

  local asset = "keyboard-sound-test.so"
  local payload = "binary\0payload\255"
  local checksum = string.rep("a", 64)
  local download_count = 0
  local should_corrupt = false
  local destination = root .. "/" .. asset
  local installer = Installer.create({
    release_url = "https://example.invalid/v0.2.0",
    asset = asset,
    destination = destination,
    download = function(request)
      download_count = download_count + 1
      if request.url:sub(-11) == "/SHA256SUMS" then
        write_bytes({ path = request.destination, bytes = checksum .. "  " .. asset .. "\n" })
      else
        write_bytes({ path = request.destination, bytes = should_corrupt and "corrupt" or payload })
      end
    end,
    hash_file = function(path)
      return read_bytes(path) == payload and checksum or string.rep("f", 64)
    end,
  })
  assert(installer:install() == destination)
  assert(read_bytes(destination) == payload and download_count == 2)
  installer:install()
  assert(download_count == 2, "valid cache downloaded again")
  assert(not pcall(function()
    installer:read_expected_hash({ checksum .. "  " .. asset, checksum .. "  " .. asset })
  end))
  assert(not pcall(function()
    installer:read_expected_hash({ "bad  " .. asset })
  end))
  assert(not pcall(function()
    installer:read_expected_hash({ checksum .. "  other.so" })
  end))
  write_bytes({ path = destination, bytes = "tampered cache" })
  should_corrupt = true
  assert(not pcall(function()
    installer:install()
  end))
  assert(read_bytes(destination) == "tampered cache", "unverified download replaced existing file")
  assert(#vim.fn.glob(root .. "/.install-*", false, true) == 0, "staging files leaked")
  should_corrupt = false
  installer:install()
  assert(read_bytes(destination) == payload)
  print("All keyboard-sound.nvim installer tests passed.")
end

local is_successful, error_message = xpcall(run_tests, debug.traceback)
vim.fn.delete(root, "rf")
if not is_successful then
  io.stderr:write(error_message .. "\n")
  vim.cmd("cquit 1")
end
vim.cmd("qa!")
