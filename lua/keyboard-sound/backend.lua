local Backend = {}
Backend.__index = Backend

local errors = {
  [1] = "Could not start the audio thread.",
  [2] = "Audio output unavailable. Check your audio device.",
  [3] = "Audio device disconnected.",
  [4] = "Audio library failed.",
  [5] = "Invalid audio request.",
  [6] = "Audio library is not started.",
}

function Backend.create(options)
  return setmetatable({
    library_path = options.library_path,
    load_library = options.load_library,
    notify = options.notify,
    library = nil,
    timer = nil,
    is_running = false,
    is_failed = false,
    is_enabled = false,
    volume = 0,
  }, Backend)
end

function Backend:report_failure(message)
  if self.is_failed then
    return
  end
  self.is_failed = true
  vim.schedule(function()
    self.notify("keyboard-sound.nvim: " .. message .. " Use :KeyboardSoundEnable to retry.", vim.log.levels.WARN)
  end)
end

function Backend:check_result(result)
  local code = tonumber(result)
  if code ~= 0 then
    self:report_failure(errors[code] or ("Unknown audio error: " .. tostring(code)))
    return false
  end
  return true
end

function Backend:start()
  if self.is_running or self.is_failed then
    return
  end
  local is_loaded, library = pcall(self.load_library, self.library_path)
  if not is_loaded then
    self:report_failure(tostring(library))
    return
  end
  self.library = library
  if not self:check_result(library.keyboard_sound_start()) then
    return
  end
  self.is_running = true
  self.timer = assert(vim.uv.new_timer())
  self.timer:start(
    100,
    100,
    vim.schedule_wrap(function()
      if self.is_running and not self.is_failed then
        self:check_result(self.library.keyboard_sound_poll_error())
      end
    end)
  )
end

function Backend:configure(options)
  self.is_enabled = options.is_enabled
  self.volume = options.volume
  if options.should_retry and self.is_failed then
    self:stop()
    self.is_failed = false
  end
  if not self.is_enabled or self.volume == 0 then
    self:stop()
    return
  end
  self:start()
  if self.is_running and not self.is_failed then
    self:check_result(self.library.keyboard_sound_configure(self.volume))
  end
end

function Backend:play(request)
  if self.is_running and self.is_enabled and self.volume > 0 and not self.is_failed then
    self:check_result(self.library.keyboard_sound_play(request.sound, request.queued_at_millis))
  end
end

function Backend:stop()
  self.is_running = false
  if self.timer then
    self.timer:stop()
    self.timer:close()
    self.timer = nil
  end
  if self.library then
    self.library.keyboard_sound_shutdown()
    self.library = nil
  end
end

return Backend
