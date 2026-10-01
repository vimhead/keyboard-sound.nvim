local Listener = {}
Listener.__index = Listener

function Listener.create(options)
  return setmetatable({
    backend = options.backend,
    keys = options.keys,
    namespace = vim.api.nvim_create_namespace(""),
    buffers = {},
    pending = nil,
    is_running = false,
    augroup = nil,
    is_selecting_register = false,
    feedback_revision = 0,
  }, Listener)
end

function Listener:attach(buffer)
  if self.buffers[buffer] or not vim.api.nvim_buf_is_loaded(buffer) or vim.bo[buffer].buftype ~= "" then
    return
  end
  self.buffers[buffer] = true
  local is_attached = vim.api.nvim_buf_attach(buffer, false, {
    on_bytes = function(_, changed_buffer, _, _, _, _, _, _, old_bytes, _, _, new_bytes)
      if not self.is_running then
        self.buffers[changed_buffer] = nil
        return true
      end
      local pending = self.pending
      if
        pending
        and pending.buffer == changed_buffer
        and old_bytes + new_bytes > 0
        and vim.api.nvim_get_mode().mode:sub(1, 1) == "i"
        and not vim.o.paste
        and vim.fn.reg_executing() == ""
      then
        self.pending = nil
        local seconds, microseconds = vim.uv.gettimeofday()
        local request = {
          sound = pending.sound,
          queued_at_millis = seconds * 1000 + math.floor(microseconds / 1000),
        }
        vim.schedule(function()
          if
            self.is_running
            and pending.feedback_revision == self.feedback_revision
            and vim.uv.hrtime() - pending.started_at <= 80000000
          then
            self.backend:play(request)
          end
        end)
      end
    end,
    on_detach = function(_, detached_buffer)
      self.buffers[detached_buffer] = nil
    end,
  })
  if not is_attached then
    self.buffers[buffer] = nil
  end
end

function Listener:observe(options)
  local is_insert_mode = vim.api.nvim_get_mode().mode:sub(1, 1) == "i"
  if not is_insert_mode then
    self.is_selecting_register = false
    self.pending = nil
    return
  end
  if options.key == "\18" then
    self.is_selecting_register = true
    self.pending = nil
    return
  end
  if self.is_selecting_register then
    self.is_selecting_register = options.key == "\15" or options.key == "\16"
    self.pending = nil
    return
  end
  if options.typed == "" then
    return
  end
  self.pending = nil
  if vim.o.paste or vim.fn.reg_executing() ~= "" then
    return
  end
  local sound = self.keys:select(options.typed)
  if sound == nil then
    return
  end
  local buffer = vim.api.nvim_get_current_buf()
  if vim.bo[buffer].buftype ~= "" then
    return
  end
  self:attach(buffer)
  local pending = {
    buffer = buffer,
    sound = sound,
    started_at = vim.uv.hrtime(),
    feedback_revision = self.feedback_revision,
  }
  self.pending = pending
  vim.schedule(function()
    if self.pending == pending then
      self.pending = nil
    end
  end)
end

function Listener:start()
  if self.is_running then
    return
  end
  self.is_running = true
  self.augroup = vim.api.nvim_create_augroup("KeyboardSoundInput" .. self.namespace, { clear = true })
  -- InsertCharPre prevents adjacent typed characters from being batched into one buffer update.
  vim.api.nvim_create_autocmd("InsertCharPre", {
    group = self.augroup,
    callback = function()
      if vim.v.char == "" then
        self.pending = nil
      end
    end,
  })
  vim.on_key(function(key, typed)
    self:observe({ key = key, typed = typed })
  end, self.namespace)
end

function Listener:reset_feedback()
  self.pending = nil
  self.is_selecting_register = false
  self.feedback_revision = self.feedback_revision + 1
end

function Listener:stop()
  self.is_running = false
  self:reset_feedback()
  vim.on_key(nil, self.namespace)
  if self.augroup then
    vim.api.nvim_del_augroup_by_id(self.augroup)
    self.augroup = nil
  end
end

return Listener
