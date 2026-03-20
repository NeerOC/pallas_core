-- ImGui menu system (mirrors Pallas common/menu.lua).
--
-- Builds a single "Pallas" window with:
--   • Global combat/spell options
--   • Per-behavior option submenus added via Menu:AddOptionMenu(options)
--
-- Widget descriptor format (same as Pallas):
--   { type = "checkbox", uid = "UID", text = "Label", default = true }
--   { type = "slider",   uid = "UID", text = "Label", default = 50, min = 0, max = 100 }
--   { type = "combobox", uid = "UID", text = "Label", default = 0, options = {"A","B"} }
--   { type = "text",     text = "Some header text" }

Menu = Menu or {}
Menu.OptionMenus = {}
Menu.Open = true

function Menu:Initialize()
  self.OptionMenus = {}
  self.Open = true
  print("[Pallas] Menu initialized")
end

function Menu:AddOptionMenu(options)
  if not options or not options.Name then
    print("[Pallas] Menu:AddOptionMenu — missing Name field")
    return
  end
  if not options.Widgets then
    print("[Pallas] Menu:AddOptionMenu — missing Widgets field")
    return
  end
  self.OptionMenus[#self.OptionMenus + 1] = options
end

-- ── Drawing ─────────────────────────────────────────────────────────

local function draw_widget(w)
  if not w.type then return end

  local safe_uid = w.uid and w.uid:gsub("%s+", "") or nil
  local label = w.text or ""
  if safe_uid then
    label = string.format("%s##%s", w.text, safe_uid)
  end

  if w.type == "text" then
    imgui.text(w.text or "")
    return
  end

  if not safe_uid then return end

  -- Ensure default is stored in PallasSettings
  if PallasSettings[safe_uid] == nil and w.default ~= nil then
    PallasSettings[safe_uid] = w.default
  end

  if w.type == "checkbox" then
    local changed, val = imgui.checkbox(label, PallasSettings[safe_uid] or false)
    if changed then PallasSettings[safe_uid] = val end

  elseif w.type == "slider" then
    local lo  = w.min or 0
    local hi  = w.max or 100
    local cur = PallasSettings[safe_uid] or w.default or lo
    local changed, val = imgui.slider_int(label, cur, lo, hi)
    if changed then PallasSettings[safe_uid] = val end

  elseif w.type == "combobox" then
    if not w.options or type(w.options) ~= "table" then return end
    local cur_idx  = PallasSettings[safe_uid] or 0
    local preview  = w.options[cur_idx + 1] or "(none)"
    if imgui.begin_combo(label, preview) then
      for i, opt in ipairs(w.options) do
        local sel = (i - 1 == cur_idx)
        if imgui.selectable(opt .. "##" .. safe_uid .. i, sel) then
          PallasSettings[safe_uid] = i - 1
        end
      end
      imgui.end_combo()
    end
  end
end

function Menu:Draw()
  if not self.Open then return end

  imgui.set_next_window_size(320, 400, 4)
  local visible, open = imgui.begin_window("Pallas", 0)
  if not visible then
    imgui.end_window()
    return
  end
  if not open then self.Open = false end

  -- Status bar
  if Me then
    local class_name = Me.ClassName or Me._class_name or "Unknown"
    local spec_name  = Me.SpecName
    if not spec_name or spec_name == "" then
      spec_name = PallasSettings.PallasSpecName or "?"
    end
    imgui.text_colored(0.4, 0.8, 1.0, 1.0,
      string.format("%s — %s", class_name, spec_name))
    if Me.SpecId > 0 then
      imgui.same_line(0, 8)
      imgui.text_colored(0.5, 0.5, 0.5, 1.0,
        string.format("(spec %d)", Me.SpecId))
    end
  else
    imgui.text_colored(0.6, 0.6, 0.6, 1.0, "Not logged in")
  end

  imgui.separator()

  -- ── Live status (last cast, target) ──────────────────────────────
  local now = os.clock()
  local last = Pallas._last_cast
  if last and last ~= "" then
    local age = now - (Pallas._last_cast_time or 0)
    if age < 5 then
      local tgt_name = Pallas._last_cast_tgt or ""
      imgui.text_colored(0.3, 1.0, 0.4, 1.0,
        string.format("Cast: %s -> %s", last, tgt_name))
    end
  end

  local fail = Pallas._last_fail
  if fail and fail ~= "" then
    local age = now - (Pallas._last_fail_time or 0)
    if age < 3 then
      imgui.text_colored(1.0, 0.3, 0.3, 1.0,
        string.format("FAIL: %s (backed off 1s)", fail))
    end
  end

  if Combat and Combat.BestTarget then
    local bt = Combat.BestTarget
    imgui.text(string.format("Target: %s (%.0f%%)", bt.Name, bt.HealthPct))
    imgui.same_line(0, 8)
    imgui.text_colored(0.5, 0.5, 0.5, 1.0,
      string.format("[%d enemies]", Combat.Enemies or 0))
  end

  imgui.separator()

  -- ── Global options ──────────────────────────────────────────────
  if imgui.collapsing_header("Combat") then
    if PallasSettings.PallasAutoTarget == nil then PallasSettings.PallasAutoTarget = false end
    local ch1, v1 = imgui.checkbox("Auto-target##pallas", PallasSettings.PallasAutoTarget)
    if ch1 then PallasSettings.PallasAutoTarget = v1 end

    if PallasSettings.PallasAttackOOC == nil then PallasSettings.PallasAttackOOC = false end
    local ch2, v2 = imgui.checkbox("Attack out of combat##pallas", PallasSettings.PallasAttackOOC)
    if ch2 then PallasSettings.PallasAttackOOC = v2 end

    if PallasSettings.PallasAttackTarget == nil then PallasSettings.PallasAttackTarget = true end
    local ch5, v5 = imgui.checkbox("Always attack current target##pallas", PallasSettings.PallasAttackTarget)
    if ch5 then PallasSettings.PallasAttackTarget = v5 end
  end

  if imgui.collapsing_header("General") then
    if PallasSettings.PallasEnabled == nil then PallasSettings.PallasEnabled = true end
    local ch3, v3 = imgui.checkbox("Enabled##pallas_en", PallasSettings.PallasEnabled)
    if ch3 then PallasSettings.PallasEnabled = v3 end

    if PallasSettings.PallasESP == nil then PallasSettings.PallasESP = true end
    local ch4, v4 = imgui.checkbox("Target ESP overlay##pallas_esp", PallasSettings.PallasESP)
    if ch4 then PallasSettings.PallasESP = v4 end
  end

  if imgui.collapsing_header("Interrupts") then
    -- Interrupt mode combobox
    if PallasSettings.PallasInterruptMode == nil then PallasSettings.PallasInterruptMode = 0 end
    local mode_options = { "All", "Whitelist", "None" }
    local cur_mode = PallasSettings.PallasInterruptMode or 0
    local preview = mode_options[cur_mode + 1] or "All"
    if imgui.begin_combo("Interrupt Mode##pallas_interrupt_mode", preview) then
      for i, opt in ipairs(mode_options) do
        local sel = (i - 1 == cur_mode)
        if imgui.selectable(opt .. "##interrupt_mode" .. i, sel) then
          PallasSettings.PallasInterruptMode = i - 1
        end
      end
      imgui.end_combo()
    end

    -- Advanced timing options
    if PallasSettings.PallasInterruptTiming == nil then PallasSettings.PallasInterruptTiming = false end
    local timing_changed, timing_val = imgui.checkbox("Enable Advanced Timing##pallas_timing", PallasSettings.PallasInterruptTiming)
    if timing_changed then PallasSettings.PallasInterruptTiming = timing_val end

    if PallasSettings.PallasInterruptTiming then
      if PallasSettings.PallasInterruptPercentage == nil then PallasSettings.PallasInterruptPercentage = 80 end
      local pct_changed, pct_val = imgui.slider_int("Interrupt at %##pallas_interrupt_pct", PallasSettings.PallasInterruptPercentage, 10, 95)
      if pct_changed then PallasSettings.PallasInterruptPercentage = pct_val end
      imgui.text("Interrupts casts when ≤" .. (PallasSettings.PallasInterruptPercentage or 80) .. "% complete")
      imgui.text("Channels interrupted after random delay (700ms ± 400ms)")
    end
  end

  -- ── Spec selector (manual override) ────────────────────────────
  if Me and Me._spec_options then
    if imgui.collapsing_header("Specialization") then
      if Me.SpecName and Me.SpecName ~= "" then
        imgui.text_colored(0.3, 1.0, 0.4, 1.0,
          "Detected: " .. Me.SpecName)
        imgui.text_colored(0.5, 0.5, 0.5, 1.0,
          "Override below if the game detects incorrectly:")
      end
      local cur = PallasSettings.PallasSpecIdx or 0
      local preview = Me._spec_options[cur + 1] or "(auto)"
      if imgui.begin_combo("Spec##pallas_spec", preview) then
        for i, name in ipairs(Me._spec_options) do
          if imgui.selectable(name .. "##spec" .. i, (i - 1) == cur) then
            PallasSettings.PallasSpecIdx = i - 1
            PallasSettings.PallasSpecName = name
          end
        end
        imgui.end_combo()
      end
    end
  end

  -- ── Per-behavior option menus ───────────────────────────────────
  for _, opts in ipairs(self.OptionMenus) do
    if imgui.collapsing_header(opts.Name) then
      for _, w in ipairs(opts.Widgets) do
        draw_widget(w)
      end
    end
  end

  imgui.end_window()
end

return Menu
