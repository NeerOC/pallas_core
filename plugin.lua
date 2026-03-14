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
}

local function load_settings()
  -- Load ALL saved keys (passing nil defaults preserves everything),
  -- then fill in missing core keys with defaults.
  local saved = settings_mod.load(SETTINGS_KEY) or {}
  for k, v in pairs(CORE_DEFAULTS) do
    if saved[k] == nil then saved[k] = v end
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

  if not PallasSettings.PallasEnabled then return end

  -- Rate-limit the entire tick body.  At 300fps only ~20 of those frames
  -- actually do work; the rest are no-ops (single clock() + compare).
  local now = os.clock()
  if now - last_tick < TICK_RATE then return end
  last_tick = now

  Pallas._tick_throttled = false

  -- Refresh world state (OM read + player + target)
  refresh_entities()
  refresh_me()
  if not Me then return end

  -- Re-initialize behavior if spec changed (detected or manual override)
  local live_spec = Me.SpecName
  if not live_spec or live_spec == "" then
    live_spec = PallasSettings.PallasSpecName or ""
  end
  if live_spec ~= "" and live_spec ~= Behavior.LoadedSpec then
    Menu:Initialize()
    Behavior:Initialize()
  end

  -- If spell cache is empty, rebuild (e.g. after zoning)
  if Spell.CacheCount == 0 then
    Spell:UpdateCache()
  end

  -- Run the targeting pipelines
  Combat:Update()
  Heal:Update()
  Tank:Update()

  -- Dispatch all behavior functions
  Behavior:Update()

  -- Periodic settings save (every ~5 seconds)
  if now - save_cooldown > 5 then
    save_settings()
    save_cooldown = now
  end
end

-- ── ESP overlay ─────────────────────────────────────────────────

local COL_TARGET  = imgui.color_u32(1.0, 1.0, 0.0, 1.0)   -- yellow
local COL_ENEMY   = imgui.color_u32(1.0, 0.2, 0.2, 1.0)   -- red
local COL_GREEN   = imgui.color_u32(0.3, 1.0, 0.3, 1.0)   -- green
local COL_GREY    = imgui.color_u32(0.7, 0.7, 0.7, 0.9)   -- grey

local function draw_esp()
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

  -- ── HUD: cast diagnostics (top-left area) ──────────────────────
  local hud_x, hud_y = 20, 60

  -- Last successful cast
  local last = Pallas._last_cast
  if last and last ~= "" then
    local age = os.clock() - (Pallas._last_cast_time or 0)
    if age < 3 then
      imgui.draw_text(hud_x, hud_y, COL_GREEN,
        string.format("OK: %s -> %s [code=%d %s]",
          last, Pallas._last_cast_tgt or "",
          Pallas._last_cast_code or 0,
          Pallas._last_cast_desc or ""))
      hud_y = hud_y + 16
    end
  end

  -- Last failed cast (with result code + description)
  local fail = Pallas._last_fail
  if fail and fail ~= "" then
    local age = os.clock() - (Pallas._last_fail_time or 0)
    if age < 5 then
      imgui.draw_text(hud_x, hud_y, COL_ENEMY,
        string.format("FAIL: %s [code=%d %s]",
          fail,
          Pallas._last_fail_code or -1,
          Pallas._last_fail_desc or ""))
      hud_y = hud_y + 16
    end
  end

  -- Target info summary
  if bt then
    local dist = Me:GetDistance(bt)
    imgui.draw_text(hud_x, hud_y, COL_GREY,
      string.format("Best: %s | dist=%.1f | hp=%.0f%% | combat=%s",
        bt.Name, dist, bt.HealthPct,
        bt.InCombat and "yes" or "no"))
    hud_y = hud_y + 16

    imgui.draw_text(hud_x, hud_y, COL_GREY,
      string.format("Enemies: %d | Casting: %s",
        Combat.Enemies or 0,
        Me.IsCasting and "yes" or "no"))
  end
end

function Plugin.onDraw()
  if not initialized then return end
  if not Me then return end
  Menu:Draw()
  draw_esp()
end

return Plugin
