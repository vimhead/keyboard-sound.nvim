local Installer = {}
Installer.__index = Installer

function Installer.create(options)
  return setmetatable({
    release_url = options.release_url,
    asset = options.asset,
    destination = options.destination,
    download = options.download,
    hash_file = options.hash_file,
  }, Installer)
end

function Installer:read_expected_hash(lines)
  local expected = nil
  for _, line in ipairs(lines) do
    local checksum, filename = line:match("^([a-fA-F0-9]+)%s+%*?(.+)$")
    if filename == self.asset then
      assert(#checksum == 64 and not expected, "Invalid or duplicate release checksum")
      expected = checksum:lower()
    end
  end
  assert(expected, "Release checksum does not contain " .. self.asset)
  return expected
end

function Installer:is_cached()
  if vim.fn.filereadable(self.destination) ~= 1 or vim.fn.filereadable(self.destination .. ".sha256") ~= 1 then
    return false
  end
  local expected = vim.fn.readfile(self.destination .. ".sha256")[1]
  return expected ~= nil and #expected == 64 and self.hash_file(self.destination) == expected
end

function Installer:install()
  if self:is_cached() then
    return self.destination
  end
  local directory = vim.fn.fnamemodify(self.destination, ":h")
  vim.fn.mkdir(directory, "p")
  local staging = assert(vim.uv.fs_mkdtemp(directory .. "/.install-XXXXXX"))
  local is_successful, result = xpcall(function()
    local checksums = staging .. "/SHA256SUMS"
    self.download({ url = self.release_url .. "/SHA256SUMS", destination = checksums })
    local expected = self:read_expected_hash(vim.fn.readfile(checksums))
    local library = staging .. "/" .. self.asset
    self.download({ url = self.release_url .. "/" .. self.asset, destination = library })
    assert(self.hash_file(library) == expected, "Audio library SHA-256 mismatch; nothing installed")
    assert(vim.fn.writefile({ expected }, staging .. "/checksum") == 0)
    assert(vim.uv.fs_rename(library, self.destination))
    assert(vim.uv.fs_rename(staging .. "/checksum", self.destination .. ".sha256"))
    return self.destination
  end, debug.traceback)
  vim.fn.delete(staging, "rf")
  assert(is_successful, result)
  return result
end

return Installer
