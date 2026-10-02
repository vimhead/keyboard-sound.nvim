local Install = {}
local Platform = require("keyboard-sound.platform")
local Installer = require("keyboard-sound.installer")
local release = require("keyboard-sound.release")

local function run_command(request)
  local result = nil
  local process = vim.system(request.argv, { cwd = request.cwd, text = true }, function(completed)
    result = completed
  end)
  if coroutine.running() then
    while result == nil do
      coroutine.yield({ msg = request.progress, level = vim.log.levels.TRACE })
    end
  else
    result = process:wait()
  end
  assert(result.code == 0, request.progress .. ": " .. (result.stderr or "Command failed"))
  return result.stdout or ""
end

local function download(request)
  assert(vim.fn.executable("curl") == 1, "Install curl to download the audio library")
  run_command({
    argv = {
      "curl",
      "--fail",
      "--location",
      "--silent",
      "--show-error",
      "--proto",
      "=https",
      "--proto-redir",
      "=https",
      "--tlsv1.2",
      "--connect-timeout",
      "20",
      "--max-time",
      "120",
      "--output",
      request.destination,
      request.url,
    },
    cwd = nil,
    progress = "Downloading " .. vim.fn.fnamemodify(request.destination, ":t"),
  })
end

local function hash_file(path)
  local argv
  local pattern = "^([a-fA-F0-9]+)"
  if vim.fn.executable("sha256sum") == 1 then
    argv = { "sha256sum", path }
  elseif vim.fn.executable("shasum") == 1 then
    argv = { "shasum", "-a", "256", path }
  elseif vim.fn.has("win32") == 1 then
    local executable = vim.fn.executable("pwsh") == 1 and "pwsh" or "powershell"
    assert(vim.fn.executable(executable) == 1, "SHA-256 verification requires PowerShell")
    argv = {
      executable,
      "-NoProfile",
      "-NonInteractive",
      "-Command",
      "(Get-FileHash -Algorithm SHA256 -LiteralPath '" .. path:gsub("'", "''") .. "').Hash",
    }
  else
    error("SHA-256 verification requires sha256sum or shasum")
  end
  local output = run_command({ argv = argv, cwd = nil, progress = "Verifying SHA-256" })
  local checksum = output:match(pattern)
  assert(checksum and #checksum == 64, "Checksum tool returned an invalid SHA-256")
  return checksum:lower()
end

function Install.install()
  local platform = Platform.current()
  local installer = Installer.create({
    release_url = "https://github.com/" .. release.repository .. "/releases/download/v" .. release.version,
    asset = platform.asset,
    destination = Platform.get_cache_path(platform),
    download = download,
    hash_file = hash_file,
  })
  return installer:install()
end

function Install.build_from_source()
  local platform = Platform.current()
  local root = Platform.get_plugin_root()
  assert(vim.fn.executable("cargo") == 1, "Source builds require Cargo and Rust 1.88+")
  run_command({
    argv = { "cargo", "build", "--release", "--locked", "--manifest-path", root .. "/native/Cargo.toml" },
    cwd = root,
    progress = "Building the audio library from source",
  })
  return root .. "/native/target/release/" .. platform.library_file
end

return Install
