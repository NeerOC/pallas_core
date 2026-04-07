-- ImGui menu system (mirrors Pallas common/menu.lua).
--
-- Builds a single "Pallas" window with:
--   * Status bar (class/spec, last cast, target)
--   * Tabbed interface: Settings, Interrupts, Spec, per-behavior tabs
--
-- Widget descriptor format (same as Pallas):
--   { type = "checkbox", uid = "UID", text = "Label", default = true }
--   { type = "slider",   uid = "UID", text = "Label", default = 50, min = 0, max = 100 }
--   { type = "combobox", uid = "UID", text = "Label", default = 0, options = {"A","B"} }
--   { type = "text",     text = "Some header text" }

local ImGuiKeys = Pallas.include("data/imgui_keys.lua")
if not ImGuiKeys then
  print("[Pallas] Failed to load ImGui keys data, using fallback")
  ImGuiKeys = {
    get_key_name = function(key) return "Unknown (" .. tostring(key) .. ")" end,
    COMMON_KEYS = {580} -- F9 as fallback
  }
end

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

  if w.type == "header" then
    imgui.spacing()
    imgui.text_colored(0.4, 0.8, 1.0, 1.0, w.text or "")
    imgui.separator()
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
    local is_float = w.step or (lo % 1 ~= 0) or (hi % 1 ~= 0) or ((w.default or 0) % 1 ~= 0)
    local changed, val
    if is_float then
      changed, val = imgui.slider_float(label, cur, lo, hi, w.format or "%.1f")
    else
      changed, val = imgui.slider_int(label, cur, lo, hi)
    end
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

-- ── Tab content helpers ─────────────────────────────────────────────

local function draw_tab_settings()
  imgui.text_colored(0.4, 0.8, 1.0, 1.0, "Core")
  imgui.separator()

  if PallasSettings.PallasEnabled == nil then PallasSettings.PallasEnabled = true end
  local ch3, v3 = imgui.checkbox("Enabled##pallas_en", PallasSettings.PallasEnabled)
  if ch3 then PallasSettings.PallasEnabled = v3 end

  if PallasSettings.PallasESP == nil then PallasSettings.PallasESP = true end
  local ch4, v4 = imgui.checkbox("Target ESP overlay##pallas_esp", PallasSettings.PallasESP)
  if ch4 then PallasSettings.PallasESP = v4 end

  if PallasSettings.PallasSpellDebug == nil then PallasSettings.PallasSpellDebug = false end
  local chsd, vsd = imgui.checkbox("Spell Debug Window##pallas_spelldebug", PallasSettings.PallasSpellDebug)
  if chsd then PallasSettings.PallasSpellDebug = vsd end

  imgui.spacing()
  imgui.text_colored(0.4, 0.8, 1.0, 1.0, "Combat")
  imgui.separator()

  if PallasSettings.PallasAutoTarget == nil then PallasSettings.PallasAutoTarget = false end
  local ch1, v1 = imgui.checkbox("Auto-target##pallas", PallasSettings.PallasAutoTarget)
  if ch1 then PallasSettings.PallasAutoTarget = v1 end

  if PallasSettings.PallasAttackOOC == nil then PallasSettings.PallasAttackOOC = false end
  local ch2, v2 = imgui.checkbox("Attack out of combat##pallas", PallasSettings.PallasAttackOOC)
  if ch2 then PallasSettings.PallasAttackOOC = v2 end

  if PallasSettings.PallasAttackTarget == nil then PallasSettings.PallasAttackTarget = true end
  local ch5, v5 = imgui.checkbox("Always attack current target##pallas", PallasSettings.PallasAttackTarget)
  if ch5 then PallasSettings.PallasAttackTarget = v5 end

  if PallasSettings.PallasForceTarget == nil then PallasSettings.PallasForceTarget = false end
  local ch6, v6 = imgui.checkbox("Force target (skip range/facing/LOS)##pallas", PallasSettings.PallasForceTarget)
  if ch6 then PallasSettings.PallasForceTarget = v6 end

  imgui.spacing()
  imgui.text_colored(0.4, 0.8, 1.0, 1.0, "Always Attack (name whitelist)")
  imgui.separator()
  imgui.text_colored(0.5, 0.5, 0.5, 1.0, "Attack these even if not in combat with us")

  if not Menu._wl_input then Menu._wl_input = "" end
  local wl_ch, wl_v = imgui.input_text("##wl_add", Menu._wl_input, 64)
  Menu._wl_input = wl_v or Menu._wl_input
  imgui.same_line(0, 4)
  local wl_enter = wl_ch and imgui.is_key_pressed(525)  -- Enter key
  if (imgui.button("Add##wl_add_btn") or wl_enter) and Menu._wl_input ~= "" then
    local cur = PallasSettings.PallasAlwaysAttackList or ""
    local entry = Menu._wl_input:match("^%s*(.-)%s*$")
    if entry ~= "" then
      if cur == "" then
        PallasSettings.PallasAlwaysAttackList = entry
      else
        PallasSettings.PallasAlwaysAttackList = cur .. "," .. entry
      end
      Menu._wl_input = ""
    end
  end

  local wl_raw = PallasSettings.PallasAlwaysAttackList or ""
  if wl_raw ~= "" then
    local entries = {}
    for token in wl_raw:gmatch("[^,]+") do
      local t = token:match("^%s*(.-)%s*$")
      if t ~= "" then entries[#entries + 1] = t end
    end
    for idx, name in ipairs(entries) do
      imgui.text("  " .. name)
      imgui.same_line(0, 8)
      if imgui.button("X##wl_rm" .. idx) then
        table.remove(entries, idx)
        PallasSettings.PallasAlwaysAttackList = table.concat(entries, ",")
      end
    end
  else
    imgui.text_colored(0.5, 0.5, 0.5, 1.0, "  (empty)")
  end

  imgui.spacing()
  imgui.text_colored(0.4, 0.8, 1.0, 1.0, "Pause Key")
  imgui.separator()

  local current_key = PallasSettings.PallasPauseKey or 580
  local key_name = ImGuiKeys.get_key_name(current_key)
  imgui.text("Current: " .. key_name)
  imgui.same_line(0, 12)

  if imgui.button("Change##pause_key") then
    Menu.CapturingKey = true
    Menu.CaptureStartTime = os.clock()
  end

  if Menu.CapturingKey then
    imgui.text_colored(1.0, 0.8, 0.2, 1.0, "Press any key... (ESC to cancel)")

    if os.clock() - (Menu.CaptureStartTime or 0) > 5 then
      Menu.CapturingKey = false
    end

    for _, key in ipairs(ImGuiKeys.COMMON_KEYS) do
      if imgui.is_key_pressed(key) then
        if key == 526 then -- ESC
          Menu.CapturingKey = false
        else
          PallasSettings.PallasPauseKey = key
          Menu.CapturingKey = false
          print("[Pallas] Pause key set to: " .. ImGuiKeys.get_key_name(key))
        end
        break
      end
    end
  end

  -- ── Spec selector ───────────────────────────────────────────────
  if Me and Me._spec_options then
    imgui.spacing()
    imgui.text_colored(0.4, 0.8, 1.0, 1.0, "Specialization")
    imgui.separator()

    if Me.SpecName and Me.SpecName ~= "" then
      imgui.text_colored(0.3, 1.0, 0.4, 1.0, "Detected: " .. Me.SpecName)
    end
    local cur = PallasSettings.PallasSpecIdx or 0
    local preview = Me._spec_options[cur + 1] or "(auto)"
    if imgui.begin_combo("Spec##pallas_spec", preview) then
      for i, name in ipairs(Me._spec_options) do
        if imgui.selectable(name .. "##spec" .. i, (i - 1) == cur) then
          PallasSettings.PallasSpecIdx = i - 1
          PallasSettings.PallasSpecName = name
          if Pallas.invalidate_behavior_variant_cache then
            Pallas.invalidate_behavior_variant_cache()
          end
        end
      end
      imgui.end_combo()
    end

    -- Multiple behavior scripts per spec: <spec>.lua plus <spec>_<suffix>.lua
    if Pallas.refresh_behavior_variant_cache then
      Pallas.refresh_behavior_variant_cache()
    end
    local variants = Pallas._behavior_variants
    local vk = Pallas._behavior_variant_cache_key
    if variants and #variants > 1 and vk then
      imgui.spacing()
      imgui.text_colored(0.4, 0.8, 1.0, 1.0, "Behavior implementation")
      imgui.separator()
      imgui.text_colored(0.5, 0.5, 0.5, 1.0,
        "Add optional scripts alongside the default, e.g. arms_contrib.lua")
      if type(PallasSettings.PallasBehaviorBySpec) ~= "table" then
        PallasSettings.PallasBehaviorBySpec = {}
      end
      local cur_stem = (Pallas.get_chosen_behavior_stem and Pallas.get_chosen_behavior_stem()) or variants[1].stem
      local preview_label = cur_stem
      for _, v in ipairs(variants) do
        if v.stem == cur_stem then
          preview_label = (v.label == "Default") and "Default" or (v.label .. "  [" .. v.stem .. "]")
          break
        end
      end
      if imgui.begin_combo("Script##pallas_beh_impl", preview_label) then
        for _, v in ipairs(variants) do
          local row = (v.label == "Default") and "Default" or (v.label .. "  [" .. v.stem .. "]")
          if imgui.selectable(row .. "##behvar" .. v.stem, v.stem == cur_stem) then
            PallasSettings.PallasBehaviorBySpec[vk] = v.stem
          end
        end
        imgui.end_combo()
      end
    end
  end
end

local function draw_tab_interrupts()
  if PallasSettings.PallasInterruptMode == nil then PallasSettings.PallasInterruptMode = 0 end
  local mode_options = { "All", "Whitelist", "None" }
  local cur_mode = PallasSettings.PallasInterruptMode or 0
  local preview = mode_options[cur_mode + 1] or "All"
  if imgui.begin_combo("Mode##pallas_interrupt_mode", preview) then
    for i, opt in ipairs(mode_options) do
      local sel = (i - 1 == cur_mode)
      if imgui.selectable(opt .. "##interrupt_mode" .. i, sel) then
        PallasSettings.PallasInterruptMode = i - 1
      end
    end
    imgui.end_combo()
  end

  imgui.spacing()

  if PallasSettings.PallasInterruptTiming == nil then PallasSettings.PallasInterruptTiming = false end
  local timing_changed, timing_val = imgui.checkbox("Advanced Timing##pallas_timing", PallasSettings.PallasInterruptTiming)
  if timing_changed then PallasSettings.PallasInterruptTiming = timing_val end

  if PallasSettings.PallasInterruptTiming then
    if PallasSettings.PallasInterruptPercentage == nil then PallasSettings.PallasInterruptPercentage = 80 end
    local pct_changed, pct_val = imgui.slider_int("Cast %##pallas_interrupt_pct", PallasSettings.PallasInterruptPercentage, 10, 95)
    if pct_changed then PallasSettings.PallasInterruptPercentage = pct_val end
    imgui.text_colored(0.5, 0.5, 0.5, 1.0,
      "Interrupt at >=" .. (PallasSettings.PallasInterruptPercentage or 80) .. "% | Channels: immediately")
  end
end

local function draw_tab_dispels()
  if PallasSettings.PallasDispelMode == nil then PallasSettings.PallasDispelMode = 0 end
  local mode_options = { "All", "Whitelist", "None" }
  local cur_mode = PallasSettings.PallasDispelMode or 0
  local preview = mode_options[cur_mode + 1] or "All"
  if imgui.begin_combo("Mode##pallas_dispel_mode", preview) then
    for i, opt in ipairs(mode_options) do
      local sel = (i - 1 == cur_mode)
      if imgui.selectable(opt .. "##dispel_mode" .. i, sel) then
        PallasSettings.PallasDispelMode = i - 1
      end
    end
    imgui.end_combo()
  end

  imgui.spacing()

  if cur_mode == 0 then
    imgui.text_colored(0.5, 0.5, 0.5, 1.0, "Dispels all removable debuffs/buffs")
  elseif cur_mode == 1 then
    imgui.text_colored(0.5, 0.5, 0.5, 1.0, "Only dispels auras listed in data/dispels.lua")
  else
    imgui.text_colored(0.5, 0.5, 0.5, 1.0, "Dispelling disabled globally")
  end
end

function Menu:Draw()
  if not self.Open then return end

  imgui.set_next_window_size(340, 420, 4)
  local visible, open = imgui.begin_window("Pallas", 0)
  if not visible then
    imgui.end_window()
    return
  end
  if not open then self.Open = false end

  -- ── Status bar ──────────────────────────────────────────────────
  if Me then
    local class_name = Me.ClassName or Me._class_name or "Unknown"
    local spec_name  = Me.SpecName
    if not spec_name or spec_name == "" then
      spec_name = PallasSettings.PallasSpecName or "?"
    end
    imgui.text_colored(0.4, 0.8, 1.0, 1.0,
      string.format("%s - %s", class_name, spec_name))
    if Me.SpecId > 0 then
      imgui.same_line(0, 8)
      imgui.text_colored(0.5, 0.5, 0.5, 1.0,
        string.format("(spec %d)", Me.SpecId))
    end
  else
    imgui.text_colored(0.6, 0.6, 0.6, 1.0, "Not logged in")
  end

  -- Live status
  local now = os.clock()
  local last = Pallas._last_cast
  if last and last ~= "" then
    local age = now - (Pallas._last_cast_time or 0)
    if age < 5 then
      imgui.text_colored(0.3, 1.0, 0.4, 1.0,
        string.format("Cast: %s -> %s", last, Pallas._last_cast_tgt or ""))
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

  -- ── Tab bar ─────────────────────────────────────────────────────
  if imgui.begin_tab_bar("##pallas_tabs") then

    -- Settings tab
    local sv = imgui.begin_tab_item("Settings##ptab_settings")
    if sv then
      imgui.begin_child("##settings_scroll", 0, 0, false)
      draw_tab_settings()
      imgui.end_child()
      imgui.end_tab_item()
    end

    -- Interrupts tab
    local iv = imgui.begin_tab_item("Interrupts##ptab_int")
    if iv then
      imgui.begin_child("##int_scroll", 0, 0, false)
      draw_tab_interrupts()
      imgui.end_child()
      imgui.end_tab_item()
    end

    -- Dispels tab
    local dv = imgui.begin_tab_item("Dispels##ptab_disp")
    if dv then
      imgui.begin_child("##disp_scroll", 0, 0, false)
      draw_tab_dispels()
      imgui.end_child()
      imgui.end_tab_item()
    end

    -- Per-behavior tabs
    for idx, opts in ipairs(self.OptionMenus) do
      local bv = imgui.begin_tab_item(opts.Name .. "##ptab_beh" .. idx)
      if bv then
        imgui.begin_child("##beh_scroll" .. idx, 0, 0, false)
        for _, w in ipairs(opts.Widgets) do
          draw_widget(w)
        end
        imgui.end_child()
        imgui.end_tab_item()
      end
    end

    imgui.end_tab_bar()
  end

  imgui.end_window()
end

return Menu
