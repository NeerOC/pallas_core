-- ═══════════════════════════════════════════════════════════════════
-- Pallas Core — general-purpose PvE behavior framework for jmrMoP
--
-- Modelled after TeamWector/Pallas.  Lives as a CommunityScripts
-- plugin so it reloads cleanly with the END key alongside any
-- behavior files that extend it.
-- ═══════════════════════════════════════════════════════════════════

local Plugin = {}
Plugin.name        = "Pallas Core"
Plugin.description = "Pallas-style behavior framework (combat, heal, tank)"
Plugin.author      = "community"

local settings_mod = require("settings")

-- ── Globals set up by the core ──────────────────────────────────
-- These are intentionally global so behavior files can reference
-- them without require() (mirrors Pallas's global convention).
--   Me, Spell, Combat, Heal, Tank, Behavior, BehaviorType,
--   Menu, PallasSettings, Unit, Targeting, GroupRole, UnitReaction

Pallas = Pallas or {}
Pallas._entity_cache = {}
Pallas._last_cast      = ""
Pallas._last_cast_time = 0
Pallas._last_cast_tgt  = ""
Pallas._last_cast_code = 0
Pallas._last_cast_desc = ""
Pallas._last_fail      = ""
Pallas._last_fail_time = 0
Pallas._last_fail_code = 0
Pallas._last_fail_desc = ""
Pallas._tick_throttled = false

-- ── Module loader ───────────────────────────────────────────────

local BASE_DIR = (game.SCRIPTS_DIR or ".") .. "\\CommunityScripts\\pallas_core"

local function include(rel_path)
  local full = BASE_DIR .. "\\" .. rel_path:gsub("/", "\\")
  local chunk, err = loadfile(full)
  if not chunk then
    console.warn("[Pallas] load failed: " .. rel_path .. " — " .. tostring(err))
    return nil
  end
  local ok, result = pcall(chunk)
  if not ok then
    console.error("[Pallas] error in " .. rel_path .. " — " .. tostring(result))
    return nil
  end
  return result
end

-- Expose the loader globally so system/behavior.lua can load behavior files.
Pallas.include = include

-- ── Behavior variants (multiple implementations per spec) ───────
-- Files: behaviors/<class>/<spec>.lua (default) and
--        behaviors/<class>/<spec>_<suffix>.lua (e.g. arms_jane.lua).
-- Discovery uses Windows "dir /b" via io.popen; falls back to probing the
-- canonical file if listing is unavailable.

Pallas._behavior_variant_cache_key = nil
Pallas._behavior_variants = nil

local function list_behavior_variants_impl(class_key, spec_slug)
  local results = {}
  local seen = {}
  local function add_stem(stem)
    if seen[stem] then return end
    seen[stem] = true
    results[#results + 1] = stem
  end

  local function consider_filename(name)
    if not name or name == "" then return end
    name = name:match("^%s*(.-)%s*$") or name
    if not name:lower():match("%.lua$") then return end
    local stem = name:sub(1, -5)
    if stem == "_template" or stem:sub(1, 1) == "_" then return end
    if stem == spec_slug then
      add_stem(stem)
      return
    end
    local prefix = spec_slug .. "_"
    if stem:sub(1, #prefix) == prefix then
      add_stem(stem)
    end
  end

  local abs_dir = (BASE_DIR .. "\\behaviors\\" .. class_key):gsub("/", "\\")
  local wild = abs_dir .. "\\" .. spec_slug .. "*.lua"
  local p = io.popen('cmd /c dir /b "' .. wild .. '" 2>nul', "r")
  if p then
    for line in p:lines() do
      consider_filename(line)
    end
    p:close()
  end

  if #results == 0 then
    local f = io.open(abs_dir .. "\\" .. spec_slug .. ".lua", "r")
    if f then
      f:close()
      add_stem(spec_slug)
    end
  end

  table.sort(results, function(a, b)
    if a == spec_slug and b ~= spec_slug then return true end
    if b == spec_slug and a ~= spec_slug then return false end
    return a < b
  end)

  local out = {}
  for _, stem in ipairs(results) do
    local label
    if stem == spec_slug then
      label = "Default"
    else
      label = stem:sub(#spec_slug + 2) or stem
    end
    out[#out + 1] = { stem = stem, label = label }
  end
  return out
end

function Pallas.list_behavior_variants(class_key, spec_slug)
  if not class_key or class_key == "" or not spec_slug or spec_slug == "" then
    return {}
  end
  return list_behavior_variants_impl(class_key, spec_slug)
end

function Pallas.invalidate_behavior_variant_cache()
  Pallas._behavior_variant_cache_key = nil
end

function Pallas.refresh_behavior_variant_cache()
  if not Me or not Me._class_key or Me._class_key == "" then
    Pallas._behavior_variants = {}
    Pallas._behavior_variant_cache_key = nil
    return
  end
  local spec_name = Me.SpecName
  if not spec_name or spec_name == "" then
    spec_name = PallasSettings.PallasSpecName or ""
  end
  local slug = spec_name:gsub("%s+", ""):lower()
  if slug == "" then
    Pallas._behavior_variants = {}
    Pallas._behavior_variant_cache_key = nil
    return
  end
  local key = Me._class_key .. "/" .. slug
  if key == Pallas._behavior_variant_cache_key and Pallas._behavior_variants then
    return
  end
  Pallas._behavior_variant_cache_key = key
  Pallas._behavior_variants = list_behavior_variants_impl(Me._class_key, slug)
end

function Pallas.get_chosen_behavior_stem()
  Pallas.refresh_behavior_variant_cache()
  local variants = Pallas._behavior_variants
  if not variants or #variants == 0 then
    return nil
  end
  local key = Pallas._behavior_variant_cache_key
  if not key then
    return variants[1].stem
  end
  if type(PallasSettings.PallasBehaviorBySpec) ~= "table" then
    PallasSettings.PallasBehaviorBySpec = {}
  end
  local saved = PallasSettings.PallasBehaviorBySpec[key]
  if saved then
    for i = 1, #variants do
      if variants[i].stem == saved then
        return saved
      end
    end
  end
  return variants[1].stem
end

-- ── Settings persistence ────────────────────────────────────────

PallasSettings = PallasSettings or {}

local SETTINGS_KEY = "CommunityScripts\\pallas_core"

local CORE_DEFAULTS = {
  PallasEnabled      = true,
  PallasAutoTarget   = false,
  PallasAttackOOC    = false,
  PallasAttackTarget = true,
  PallasESP          = true,
  PallasSpecIdx      = 0,
  PallasSpecName     = "",
  PallasInterruptMode = 2, -- 0=All (filtered by interrupts.lua), 1=Whitelist (same as All), 2=None
  PallasInterruptTiming = false, -- Enable advanced timing logic
  PallasInterruptPercentage = 80, -- Interrupt when cast is <= 80% complete
  PallasDispelMode   = 2, -- 0=All, 1=Whitelist (data/dispels.lua), 2=None
  PallasPaused       = false, -- Behavior pause state
  PallasPauseKey     = 580, -- ImGuiKey_F9 default
  PallasSpellDebug   = false, -- Show spell debug window
  PallasForceTarget  = false, -- Skip range/facing/LOS on current target
  PallasAlwaysAttackList = "", -- Comma-separated partial names (case-insensitive)
}

local function load_settings()
  -- Load ALL saved keys (passing nil defaults preserves everything),
  -- then fill in missing core keys with defaults.
  local saved = settings_mod.load(SETTINGS_KEY) or {}
  for k, v in pairs(CORE_DEFAULTS) do
    if saved[k] == nil then saved[k] = v end
  end
  if type(saved.PallasBehaviorBySpec) ~= "table" then
    saved.PallasBehaviorBySpec = {}
  end
  PallasSettings = saved
end

local function save_settings()
  settings_mod.save(SETTINGS_KEY, PallasSettings)
end

local save_cooldown = 0

-- ── Load all modules (order matters) ────────────────────────────

local function load_modules()
  include("common/group.lua")
  include("common/targeting.lua")

  local UnitMod = include("common/unit.lua")
  if UnitMod then
    Unit = UnitMod
  end

  local PlayerMod = include("common/player.lua")
  if PlayerMod then
    Player = PlayerMod
  end

  include("common/spell.lua")
  include("common/item.lua")

  local PetMod = include("common/pet.lua")
  if PetMod then
    Pet = PetMod
  end

  local RuneMod = include("common/rune.lua")
  if RuneMod then
    Rune = RuneMod
  end

  local TTDMod = include("common/ttd.lua")
  if TTDMod then
    TTD = TTDMod
  end

  include("common/menu.lua")

  local ClassData = include("data/classes.lua")
  Pallas._class_data = ClassData

  include("system/behavior.lua")
  include("system/combat.lua")
  include("system/heal.lua")
  include("system/tank.lua")
end

-- ── ActivePlayer refresh ────────────────────────────────────────

local function refresh_me()
  local ok, player = pcall(game.local_player)
  if not ok or not player then
    Me = nil
    return
  end

  Me = Player:New(player)
  if not Me then return end

  -- Attach class metadata
  local cd = Pallas._class_data
  if cd then
    local key = cd.class_key(Me.ClassId)
    Me._class_key     = key
    Me._class_name    = cd.CLASS_MAP[Me.ClassId] or "Unknown"
    Me.ClassName      = Me._class_name
    Me._spec_options  = key and cd.SPEC_MAP[key] or {}
  end

  -- Auto-detect spec from the OM snapshot (active player only).
  -- If the game provides a spec_name, use it directly; otherwise fall
  -- back to the manual dropdown selection stored in PallasSettings.
  if Me.SpecName ~= "" then
    PallasSettings.PallasSpecName = Me.SpecName
    -- Sync the index for the dropdown display
    if Me._spec_options then
      for i, name in ipairs(Me._spec_options) do
        if name == Me.SpecName then
          PallasSettings.PallasSpecIdx = i - 1
          break
        end
      end
    end
  end

  -- Attach current target as a property (mirrors Pallas Me.Target)
  Me.Target = Me:GetTarget()
end

-- ── Entity cache (one OM read per tick) ─────────────────────────

local function refresh_entities()
  local ok, list = pcall(game.objects)
  Pallas._entity_cache = (ok and list) or {}
end

-- ── Always-Attack Whitelist ──────────────────────────────────────
-- Parsed cache: list of lowercased partial-name strings.
local _whitelist_cache = {}
local _whitelist_source = ""

local function refresh_whitelist()
  local raw = PallasSettings.PallasAlwaysAttackList or ""
  if raw == _whitelist_source then return end
  _whitelist_source = raw
  _whitelist_cache = {}
  for token in raw:gmatch("[^,]+") do
    local trimmed = token:match("^%s*(.-)%s*$"):lower()
    if trimmed ~= "" then
      _whitelist_cache[#_whitelist_cache + 1] = trimmed
    end
  end
end

function Pallas.IsWhitelisted(name)
  if not name or name == "" then return false end
  refresh_whitelist()
  if #_whitelist_cache == 0 then return false end
  local lower = name:lower()
  for i = 1, #_whitelist_cache do
    if lower:find(_whitelist_cache[i], 1, true) then return true end
  end
  return false
end

-- ── Initialize ──────────────────────────────────────────────────

local initialized = false

local function initialize()
  if initialized then return end

  load_settings()
  load_modules()

  if not Unit then
    console.error("[Pallas] Unit module failed to load — aborting")
    return
  end

  -- Refresh player and entities for the first time
  refresh_entities()
  refresh_me()

  if Me then
    Menu:Initialize()
    Spell:UpdateCache()
    Behavior:Initialize()
  end

  initialized = true
  print("[Pallas] Core initialized")
end

-- ── ImGui key constants ───────────────────────────────────────────
local ImGuiKey_Insert = 521

-- ── Plugin lifecycle ────────────────────────────────────────────

function Plugin.onEnable()
  initialized = false
  initialize()
  console.log("[Pallas] Enabled")
end

function Plugin.onDisable()
  save_settings()
  Me = nil
  initialized = false
  console.log("[Pallas] Disabled")
end

local TICK_RATE = 0.05   -- 50ms → 20 ticks/sec (plenty for a 1.5s GCD)
local last_tick = 0

function Plugin.onTick()
  if not initialized then
    initialize()
    if not initialized then return end
  end

  -- Check for Insert key press to toggle Pallas window
  if imgui.is_key_pressed(ImGuiKey_Insert) then
    if Menu then
      Menu.Open = not Menu.Open
    end
  end

  -- Check for pause key press to toggle behavior pulses
  if imgui.is_key_pressed(PallasSettings.PallasPauseKey or 580) then
    PallasSettings.PallasPaused = not PallasSettings.PallasPaused
    if PallasSettings.PallasPaused then
      print("[Pallas] Behaviors paused")
    else
      print("[Pallas] Behaviors resumed")
    end
  end

  if not PallasSettings.PallasEnabled then return end

  -- Rate-limit the entire tick body.  At 300fps only ~20 of those frames
  -- actually do work; the rest are no-ops (single clock() + compare).
  local now = os.clock()
  if now - last_tick < TICK_RATE then return end
  last_tick = now

  Pallas._tick_throttled = false
  Pallas._spell_debug_tick = (Pallas._spell_debug_tick or 0) + 1
  Pallas._last_tick = now

  -- Refresh world state (OM read + player + target) - always update even when paused
  refresh_entities()
  refresh_me()
  if not Me then return end

  -- Re-initialize behavior if spec or chosen behavior variant changed
  local live_spec = Me.SpecName
  if not live_spec or live_spec == "" then
    live_spec = PallasSettings.PallasSpecName or ""
  end
  local chosen_stem = ""
  if Pallas.get_chosen_behavior_stem then
    chosen_stem = Pallas.get_chosen_behavior_stem() or ""
  end
  local loaded_stem = Behavior.LoadedStem or ""
  local live_class = Me._class_key or ""
  if live_spec ~= "" and (
      live_spec ~= Behavior.LoadedSpec
      or chosen_stem ~= loaded_stem
      or live_class ~= (Behavior.LoadedClass or "")
    ) then
    Menu:Initialize()
    Behavior:Initialize()
  end

  -- If spell cache is empty, rebuild (e.g. after zoning)
  if Spell.CacheCount == 0 then
    Spell:UpdateCache()
  end

  -- Only run targeting and behaviors if not paused
  if not PallasSettings.PallasPaused then
    -- Run the targeting pipelines
    Combat:Update()
    Heal:Update()
    Tank:Update()

    -- Dispatch all behavior functions
    Behavior:Update()
  end

  -- Periodic settings save (every ~5 seconds)
  if now - save_cooldown > 5 then
    save_settings()
    save_cooldown = now
  end
end

-- ── ESP overlay ─────────────────────────────────────────────────

local COL_TARGET  = imgui.color_u32(1.0, 1.0, 0.0, 1.0)   -- yellow
local COL_ENEMY   = imgui.color_u32(1.0, 0.2, 0.2, 1.0)   -- red
local COL_GREY    = imgui.color_u32(0.7, 0.7, 0.7, 0.9)   -- grey
local COL_WHITE   = imgui.color_u32(1.0, 1.0, 1.0, 1.0)   -- white

local function draw_esp()
  -- Draw "Behavior Disabled" text at character position when paused (even if ESP is disabled)
  if PallasSettings.PallasPaused then
    if Me and Me.Position then
      local sx, sy = game.world_to_screen(Me.Position.x, Me.Position.y, Me.Position.z + 2.0)
      if sx then
        imgui.draw_text(sx - 80, sy - 10, COL_WHITE, "Behavior Disabled")
      end
    end
    return -- Don't draw other ESP elements when paused
  end

  if not PallasSettings.PallasESP then return end
  if not Me or not Me.Position then return end

  -- Draw best target with circle + label
  local bt = Combat and Combat.BestTarget or nil
  if bt and bt.Position then
    local sx, sy = game.world_to_screen(bt.Position.x, bt.Position.y, bt.Position.z + 1.5)
    if sx then
      local dist = Me:GetDistance(bt)
      local los_ok, los = pcall(game.is_visible, Me.obj_ptr, bt.obj_ptr, 0x03)
      local los_str = (los_ok and los) and "LOS" or "NO LOS"

      imgui.draw_circle(sx, sy, 12, COL_TARGET, 0, 2)
      imgui.draw_text(sx - 60, sy - 28, COL_TARGET,
        string.format("[T] %s (%.0f%%) %.1fyd %s",
          bt.Name, bt.HealthPct, dist, los_str))

      -- Show GUID for debugging
      imgui.draw_text(sx - 60, sy - 14, COL_GREY,
        string.format("guid: %d / %d", bt.guid_lo or 0, bt.guid_hi or 0))
    end

    -- Also draw a foot marker
    local fx, fy = game.world_to_screen(bt.Position.x, bt.Position.y, bt.Position.z)
    if fx then
      imgui.draw_circle(fx, fy, 6, COL_TARGET, 0, 1)
    end
  end

  -- Draw all other combat targets
  local targets = Combat and Combat.Targets or {}
  for _, u in ipairs(targets) do
    if u.Position and (not bt or u.Guid ~= bt.Guid) then
      local sx, sy = game.world_to_screen(u.Position.x, u.Position.y, u.Position.z + 1.0)
      if sx then
        local dist = Me:GetDistance(u)
        imgui.draw_text(sx - 30, sy - 14, COL_ENEMY,
          string.format("%s (%.0f%%) %.0fyd", u.Name, u.HealthPct, dist))
      end
    end
  end

end

function Plugin.onDraw()
  if not initialized then return end
  if not Me then return end
  Menu:Draw()
  draw_esp()
  if Spell and Spell.DrawDebugWindow then
    pcall(Spell.DrawDebugWindow, Spell)
  end
  if Pallas._behavior_draw then
    pcall(Pallas._behavior_draw)
  end
end

return Plugin
