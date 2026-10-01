local Backend = {}
Backend.__index = Backend

function Backend.create(options)
  return setmetatable({
    executable = options.executable,
    notify = options.notify,
    job = nil,
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
    self.notify("keyboard-sound.nvim: " .. message, vim.log.levels.WARN)
  end)
end

function Backend:send(message)
  if not self.job then
    return
  end
  local is_sent = pcall(vim.fn.chansend, self.job, vim.json.encode(message) .. "\n")
  if not is_sent then
    self:report_failure("Audio worker disconnected. Use :KeyboardSoundEnable to retry.")
    self:stop()
  end
end

function Backend:start()
  if self.job or self.is_failed then
    return
  end
  if vim.fn.executable(self.executable) ~= 1 then
    self:report_failure("Build the audio worker with cargo build --release --locked --manifest-path worker/Cargo.toml.")
    return
  end
  local job
  job = vim.fn.jobstart({ self.executable }, {
    on_stderr = function(_, lines)
      for _, line in ipairs(lines) do
        if line ~= "" and self.job == job then
          self:report_failure(line)
        end
      end
    end,
    on_exit = function(_, exit_code)
      if self.job == job then
        self.job = nil
        self:report_failure("Audio worker exited (" .. exit_code .. "). Use :KeyboardSoundEnable to retry.")
      end
    end,
  })
  if job <= 0 then
    self:report_failure("Could not start the audio worker.")
    return
  end
  self.job = job
end

function Backend:configure(options)
  self.is_enabled = options.is_enabled
  self.volume = options.volume
  if options.should_retry then
    self.is_failed = false
  end
  if not self.is_enabled or self.volume == 0 then
    self:stop()
    return
  end
  self:start()
  self:send({ type = "configure", is_enabled = self.is_enabled, volume = self.volume })
end

function Backend:play(request)
  if self.is_enabled and self.volume > 0 and not self.is_failed then
    self:send({ type = "click", sound = request.sound, queued_at_millis = request.queued_at_millis })
  end
end

function Backend:stop()
  local job = self.job
  self.job = nil
  if job then
    pcall(vim.fn.chanclose, job, "stdin")
    pcall(vim.fn.jobstop, job)
  end
end

return Backend
