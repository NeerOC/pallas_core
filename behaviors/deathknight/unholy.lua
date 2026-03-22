-- ═══════════════════════════════════════════════════════════════════
-- Unholy Death Knight behavior (MoP 5.5.3)
--
-- Priority-based rotation with burst keybind toggle, disease
-- snapshotting awareness, and Dark Transformation management.
--
-- Single-Target Priority:
--   1. Apply/maintain diseases (Outbreak w/ procs > Plague Strike)
--   2. Dark Transformation (5 Shadow Infusion stacks)
--   3. Scourge Strike (Unholy/Death runes)
--   4. Death Coil (>40 RP or Sudden Doom proc)
--   5. [Burst] Summon Gargoyle → Unholy Frenzy → Empower Rune Weapon
--   6. Festering Strike (Blood + Frost runes, extends diseases)
--   7. Blood Tap / Plague Leech (rune regeneration)
--   8. Horn of Winter (filler)
--
-- Execute Priority (<35%):
--   Inserts Soul Reaper + Death and Decay above Scourge Strike
--
-- AoE Priority (3+ enemies):
--   1. Diseases → Pestilence (spread)
--   2. Death and Decay
--   3. Blood Boil (Blood/Death runes)
--   4. Dark Transformation
--   5. Death Coil (RP dump)
--   6. Icy Touch (convert Frost → Death runes)
--   7. Scourge Strike (Unholy runes, low priority in AoE)
--
-- Burst CDs (Gargoyle / Unholy Frenzy / ERW):
--   Gated by a configurable toggle key. Won't fire on dying targets.
--   Visual HUD shows burst state: READY / ON / OFF / BURSTING.
-- ═══════════════════════════════════════════════════════════════════

-- ── Menu helper ──────────────────────────────────────────────────

local function S(uid)
  return PallasSettings[uid] ~= false
end

-- ── ImGuiKey name table (1.89+ named-key enum) ─────────────────

local KEY_NAMES = {
  [512] = "Tab",
  [513] = "Left", [514] = "Right", [515] = "Up", [516] = "Down",
  [517] = "PgUp", [518] = "PgDn", [519] = "Home", [520] = "End",
  [521] = "Ins", [522] = "Del", [523] = "Backspace", [524] = "Space",
  [525] = "Enter", [526] = "Escape",
  [527] = "LCtrl", [528] = "LShift", [529] = "LAlt", [530] = "LSuper",
  [531] = "RCtrl", [532] = "RShift", [533] = "RAlt", [534] = "RSuper",
  [535] = "Menu",
  [584] = "'", [585] = ",", [586] = "-", [587] = ".", [588] = "/",
  [589] = ";", [590] = "=", [591] = "[", [592] = "\\", [593] = "]",
  [594] = "`",
  [595] = "CapsLock", [596] = "ScrollLock", [597] = "NumLock",
  [598] = "PrtSc", [599] = "Pause",
  [610] = "KP.", [611] = "KP/", [612] = "KP*",
  [613] = "KP-", [614] = "KP+", [615] = "KPEnter", [616] = "KP=",
}
for i = 0, 9  do KEY_NAMES[536 + i] = tostring(i)       end
for i = 0, 25 do KEY_NAMES[546 + i] = string.char(65+i) end
for i = 1, 12 do KEY_NAMES[571 + i] = "F" .. i          end
for i = 0, 9  do KEY_NAMES[600 + i] = "KP" .. i         end

local SCAN_MIN, SCAN_MAX = 512, 616

local recording_burst_key = false
local burst_key_code      = nil  -- loaded from PallasSettings on first draw

-- ImGui window flags: NoTitleBar(1) + AutoResize(64) + NoFocusOnAppear(4096) + NoBringToFront(8192)
local WF_HUD    = 1 + 64 + 4096 + 8192
local COND_FIRST = 4  -- ImGuiCond_FirstUseEver

-- ── Menu options ────────────────────────────────────────────────

local options = {
  Name = "Death Knight (Unholy)",
  Widgets = {
    { type = "text",     text = "=== Burst ===" },
    { type = "checkbox", uid = "UnholyShowBurst",
      text = "Show burst HUD (set keybind via HUD)", default = true },
    { type = "slider",   uid = "UnholyBurstMinHP",
      text = "Don't burst below enemy HP %", default = 15, min = 5, max = 50 },
    { type = "checkbox", uid = "UnholySyncBurst",
      text = "Sync Gargoyle + Unholy Frenzy", default = true },

    { type = "text",     text = "=== Rotation Spells ===" },
    { type = "checkbox", uid = "UnholyUseOutbreak",
      text = "Outbreak",                   default = true },
    { type = "checkbox", uid = "UnholyUsePlagueStrike",
      text = "Plague Strike",              default = true },
    { type = "checkbox", uid = "UnholyUseScourgeStrike",
      text = "Scourge Strike",             default = true },
    { type = "checkbox", uid = "UnholyUseDeathCoil",
      text = "Death Coil",                 default = true },
    { type = "slider",   uid = "UnholyDCThreshold",
      text = "Death Coil above RP",        default = 40, min = 30, max = 90 },
    { type = "checkbox", uid = "UnholyUseFesteringStrike",
      text = "Festering Strike",           default = true },
    { type = "checkbox", uid = "UnholyUseSoulReaper",
      text = "Soul Reaper",                default = true },
    { type = "slider",   uid = "UnholySoulReaperThreshold",
      text = "Soul Reaper HP %",           default = 35, min = 10, max = 50 },
    { type = "checkbox", uid = "UnholyUseDarkTransformation",
      text = "Dark Transformation",        default = true },
    { type = "checkbox", uid = "UnholyUseDnD",
      text = "Death and Decay",            default = true },
    { type = "checkbox", uid = "UnholyUseBloodBoil",
      text = "Blood Boil (AoE)",           default = true },
    { type = "checkbox", uid = "UnholyUsePestilence",
      text = "Pestilence (AoE spread)",    default = true },
    { type = "checkbox", uid = "UnholyUseIcyTouch",
      text = "Icy Touch (AoE rune convert)", default = true },
    { type = "checkbox", uid = "UnholyUseBloodTap",
      text = "Blood Tap",                  default = true },
    { type = "checkbox", uid = "UnholyUsePlagueLeech",
      text = "Plague Leech",               default = true },
    { type = "checkbox", uid = "UnholyUseHoWFiller",
      text = "Horn of Winter (filler)",    default = true },

    { type = "text",     text = "=== Cooldowns ===" },
    { type = "checkbox", uid = "UnholyUseGargoyle",
      text = "Summon Gargoyle",            default = true },
    { type = "checkbox", uid = "UnholyUseUnholyFrenzy",
      text = "Unholy Frenzy",              default = true },
    { type = "slider",   uid = "UnholyUFMinHP",
      text = "Unholy Frenzy min HP %",     default = 30, min = 10, max = 80 },
    { type = "checkbox", uid = "UnholyUseERW",
      text = "Empower Rune Weapon",        default = true },
    { type = "checkbox", uid = "UnholyUseRaiseDead",
      text = "Raise Dead (maintain ghoul)", default = true },

    { type = "text",     text = "=== Defensives ===" },
    { type = "checkbox", uid = "UnholyUseIBF",
      text = "Icebound Fortitude",         default = true },
    { type = "slider",   uid = "UnholyIBFThreshold",
      text = "IBF HP %",                   default = 35, min = 15, max = 60 },
    { type = "checkbox", uid = "UnholyUseAMS",
      text = "Anti-Magic Shell",           default = false },
    { type = "checkbox", uid = "UnholyUseDeathPact",
      text = "Death Pact (sacrifice ghoul)", default = false },
    { type = "slider",   uid = "UnholyDeathPactThreshold",
      text = "Death Pact HP %",            default = 25, min = 10, max = 50 },

    { type = "text",     text = "=== Interrupts ===" },
    { type = "checkbox", uid = "UnholyUseInterrupt",
      text = "Mind Freeze",                default = true },
    { type = "combobox", uid = "UnholyInterruptMode",
      text = "Interrupt mode",             default = 0,
      options = { "Any interruptible", "Whitelist only" } },

    { type = "text",     text = "=== Utility ===" },
    { type = "checkbox", uid = "UnholyMaintainPresence",
      text = "Auto Unholy Presence",       default = true },
    { type = "checkbox", uid = "UnholyMaintainHoW",
      text = "Maintain Horn of Winter",    default = true },

    { type = "text",     text = "=== AoE ===" },
    { type = "checkbox", uid = "UnholyAoeEnabled",
      text = "Use AoE rotation",           default = true },
    { type = "slider",   uid = "UnholyAoeThreshold",
      text = "AoE enemy count",            default = 3, min = 2, max = 8 },

    { type = "text",     text = "=== Advanced ===" },
    { type = "slider",   uid = "UnholyDiseaseRefreshSec",
      text = "Disease refresh timer (sec)", default = 4, min = 2, max = 10 },
    { type = "checkbox", uid = "UnholySnapshotAwareness",
      text = "Prioritize Outbreak with procs (Unholy Strength)",
      default = true },
    { type = "slider",   uid = "UnholyBloodTapOvercap",
      text = "Blood Tap at N+ charges",    default = 10, min = 5, max = 12 },
  },
}

-- ── Constants ──────────────────────────────────────────────────

local AOE_RANGE      = 10
local INTERRUPT_WHITELIST = {}

-- ── Self-buff / no-target cast helper ────────────────────────────
-- Uses game.cast_spell (no explicit target) for spells that are self-cast
-- or don't accept a friendly target parameter. Mirrors CastEx logic.

local RESULT_SUCCESS    = 0
local RESULT_THROTTLED  = 9
local RESULT_NOT_READY  = 10
local RESULT_ON_CD      = 11
local RESULT_QUEUED     = 12

local function CastNoTarget(spell)
  if not spell.IsKnown or spell.Id == 0 then return false end
  if Pallas._tick_throttled then return false end
  local now = os.clock()
  if now < (spell._fail_until or 0) or now < (spell._cast_until or 0) then
    return false
  end
  local uok, usable = pcall(game.is_usable_spell, spell.Id)
  if uok and not usable then return false end
  local cok, cd = pcall(game.spell_cooldown, spell.Id)
  if cok and cd and cd.on_cooldown then return false end

  local ok, c, desc = pcall(game.cast_spell, spell.Id)
  local code = ok and c or -1
  if code == RESULT_SUCCESS or code == RESULT_QUEUED then
    Pallas._last_cast      = spell.Name
    Pallas._last_cast_time = now
    Pallas._last_cast_tgt  = "self"
    Pallas._last_cast_code = code
    Pallas._last_cast_desc = ok and (desc or "") or ""
    spell._cast_until = now + 0.2
    return true
  elseif code == RESULT_THROTTLED or code == RESULT_NOT_READY or code == RESULT_ON_CD then
    Pallas._tick_throttled = true
  elseif code >= 0 then
    spell._fail_until      = now + 1.0
    Pallas._last_fail      = spell.Name
    Pallas._last_fail_time = now
    Pallas._last_fail_code = code
    Pallas._last_fail_desc = ok and (desc or "") or ""
  end
  return false
end

-- ── Burst state ────────────────────────────────────────────────

local burst_enabled = false

-- Pet detection uses the global Pet module (common/pet.lua).

-- ── Targeting ──────────────────────────────────────────────────

local MELEE_BASE = 5.0
local bbox_cache = {}

local function GetBboxRadius(obj_ptr)
  local cached = bbox_cache[obj_ptr]
  if cached then return cached end
  local ok, bb = pcall(game.entity_bounds, obj_ptr)
  local r = (ok and bb) and (bb.width * 0.5) or 0
  bbox_cache[obj_ptr] = r
  return r
end

local function GetCombatEnemies()
  local entities = Pallas._entity_cache or {}
  if not Me or not Me.Position then return {} end
  local mx, my, mz = Me.Position.x, Me.Position.y, Me.Position.z

  local results = {}
  for _, e in ipairs(entities) do
    local cls = e.class
    if cls ~= "Unit" and cls ~= "Player" then goto skip end
    local eu = e.unit
    if not eu then goto skip end
    if eu.is_dead then goto skip end
    if eu.health and eu.health <= 0 then goto skip end
    if not eu.in_combat then goto skip end

    -- Filter out friendly units (pets, guardians, allies)
    local a_ok, attackable = pcall(game.unit_is_attackable, e.obj_ptr)
    if a_ok and not attackable then goto skip end

    if e.position then
      local dx = mx - e.position.x
      local dy = my - e.position.y
      local dz = mz - e.position.z
      local dist_sq = dx * dx + dy * dy + dz * dz
      if dist_sq <= 1600 then
        local u = Unit:New(e)
        results[#results + 1] = {
          unit = u,
          dist_sq = dist_sq,
          radius = GetBboxRadius(e.obj_ptr),
        }
      end
    end
    ::skip::
  end
  table.sort(results, function(a, b) return a.dist_sq < b.dist_sq end)
  return results
end

local function GetTargetInRange(enemies, range_yd)
  local range_sq = range_yd * range_yd
  local tgt_guid = Me.Target and not Me.Target.IsDead and Me.Target.Guid or nil
  local best = nil
  for _, entry in ipairs(enemies) do
    if entry.dist_sq > range_sq then break end
    if tgt_guid and entry.unit.Guid == tgt_guid then return entry.unit end
    if not best then best = entry.unit end
  end
  return best
end

local function MeleeTarget(enemies)
  local tgt_guid = Me.Target and not Me.Target.IsDead and Me.Target.Guid or nil
  local best = nil
  for _, entry in ipairs(enemies) do
    if entry.dist_sq > 225 then break end
    local range = MELEE_BASE + entry.radius
    if entry.dist_sq <= range * range then
      if tgt_guid and entry.unit.Guid == tgt_guid then return entry.unit end
      if not best then best = entry.unit end
    end
  end
  return best
end

local function AoeTarget(enemies)    return GetTargetInRange(enemies, 10) end
local function RangedTarget(enemies) return GetTargetInRange(enemies, 30) end

local function EnemiesInRange(enemies, range_yd)
  local range_sq = range_yd * range_yd
  local count = 0
  for _, entry in ipairs(enemies) do
    if entry.dist_sq > range_sq then break end
    count = count + 1
  end
  return count
end

-- ── Interrupt ─────────────────────────────────────────────────

local mf_range_sq = nil

local function TryInterrupt(enemies)
  if not PallasSettings.UnholyUseInterrupt then return false end
  if not Spell.MindFreeze.IsKnown then return false end
  if not Spell.MindFreeze:IsReady() then return false end

  if not mf_range_sq then
    local ok, info = pcall(game.get_spell_info, Spell.MindFreeze.Id)
    if ok and info then
      local r = (info.max_range or 0)
      if r < 1 then r = 5 end
      mf_range_sq = r * r
    else
      mf_range_sq = 25
    end
  end

  local wl_mode = (PallasSettings.UnholyInterruptMode or 0) == 1
  local tgt_guid = Me.Target and not Me.Target.IsDead and Me.Target.Guid or nil

  for _, entry in ipairs(enemies) do
    if entry.dist_sq > mf_range_sq then goto next_enemy end
    local u = entry.unit
    local is_target = tgt_guid and u.Guid == tgt_guid

    local casting, spell_id, confirmed_immune = false, 0, false
    if is_target then
      local ok, cast = pcall(game.unit_casting_info, "target")
      if ok and cast then
        casting, spell_id = true, cast.spell_id or 0
        if cast.not_interruptible then confirmed_immune = true end
      else
        local ok2, chan = pcall(game.unit_channel_info, "target")
        if ok2 and chan then
          casting, spell_id = true, chan.spell_id or 0
          if chan.not_interruptible then confirmed_immune = true end
        end
      end
    else
      if u.IsCasting then
        casting, spell_id = true, u.CastingSpellId or 0
      elseif u.IsChanneling then
        casting, spell_id = true, u.ChannelingSpellId or 0
      end
    end

    if not casting or confirmed_immune then goto next_enemy end
    if wl_mode and #INTERRUPT_WHITELIST > 0 and spell_id > 0 then
      local found = false
      for _, wid in ipairs(INTERRUPT_WHITELIST) do
        if wid == spell_id then found = true; break end
      end
      if not found then goto next_enemy end
    end
    if Spell.MindFreeze:CastEx(u) then return true end
    ::next_enemy::
  end
  return false
end

-- ── Disease helpers ──────────────────────────────────────────────

local function has_diseases(target)
  return target:HasAura("Frost Fever") and target:HasAura("Blood Plague")
end

local function diseases_expiring(target, threshold)
  threshold = threshold or 4
  local ff = target:GetAura("Frost Fever")
  local bp = target:GetAura("Blood Plague")
  if not ff or not bp then return true end
  return (ff.remaining or 0) < threshold or (bp.remaining or 0) < threshold
end

--- Apply or refresh diseases.
--- Snapshot-aware: prioritizes Outbreak when Unholy Strength (Fallen Crusader)
--- is active for a stronger disease snapshot.
local function ApplyDiseases(enemies)
  local melee = MeleeTarget(enemies)
  local ranged = RangedTarget(enemies)
  local target = melee or ranged
  if not target then return false end

  local refresh_sec = PallasSettings.UnholyDiseaseRefreshSec or 4
  local needs_refresh = not has_diseases(target) or diseases_expiring(target, refresh_sec)

  -- Snapshot awareness: if we have Unholy Strength proc and Outbreak is ready,
  -- reapply diseases even if they're not expiring (better snapshot)
  local has_proc = PallasSettings.UnholySnapshotAwareness
      and Me:HasAura("Unholy Strength")
  if has_proc and S("UnholyUseOutbreak") and Spell.Outbreak:IsReady() then
    if ranged then
      if Spell.Outbreak:CastEx(ranged) then return true end
    end
  end

  if not needs_refresh then return false end

  if S("UnholyUseOutbreak") and ranged then
    if Spell.Outbreak:CastEx(ranged) then return true end
  end

  if S("UnholyUsePlagueStrike") and melee and not melee:HasAura("Blood Plague") then
    if Spell.PlagueStrike:CastEx(melee) then return true end
  end

  return false
end

-- ── Rune regeneration helpers ────────────────────────────────────

--- Blood Tap: consume Blood Charge stacks to generate Death Runes.
--- Use at high stacks to prevent overcapping, or when rune-starved.
local function HandleBloodTap()
  if not S("UnholyUseBloodTap") then return false end
  if not Spell.BloodTap.IsKnown then return false end

  local charges = Me:GetAura("Blood Charge")
  local stacks = charges and charges.stacks or 0
  local overcap_at = PallasSettings.UnholyBloodTapOvercap or 10

  if stacks >= overcap_at then
    if CastNoTarget(Spell.BloodTap) then return true end
  elseif stacks >= 5 then
    if not Spell.ScourgeStrike:IsUsable() and not Spell.FesteringStrike:IsUsable() then
      if CastNoTarget(Spell.BloodTap) then return true end
    end
  end
  return false
end

--- Plague Leech: consume diseases for 2 Death Runes.
--- Only use when diseases are expiring AND we can reapply immediately.
local function HandlePlagueLeech(target)
  if not S("UnholyUsePlagueLeech") then return false end
  if not Spell.PlagueLeech.IsKnown then return false end
  if not target then return false end
  if not has_diseases(target) then return false end
  if not diseases_expiring(target, 3) then return false end

  local can_reapply = Spell.Outbreak:IsReady()
      or (Spell.PlagueStrike.IsKnown and Spell.PlagueStrike:IsUsable())
  if can_reapply then
    if Spell.PlagueLeech:CastEx(target) then return true end
  end
  return false
end

-- ── Defensives ─────────────────────────────────────────────────

local function UseDefensives()
  local hp = Me.HealthPct

  if PallasSettings.UnholyUseIBF and hp < (PallasSettings.UnholyIBFThreshold or 35) then
    if CastNoTarget(Spell.IceboundFortitude) then return true end
  end

  if PallasSettings.UnholyUseAMS then
    if CastNoTarget(Spell.AntiMagicShell) then return true end
  end

  if PallasSettings.UnholyUseDeathPact and hp < (PallasSettings.UnholyDeathPactThreshold or 25) then
    if CastNoTarget(Spell.DeathPact) then return true end
  end

  return false
end

--- Real cooldown remaining (ignores GCD — duration < 2s is just GCD).
local function cd_remaining(spell)
  if not spell.IsKnown then return -1 end
  local cd = spell:GetCooldown()
  if cd and cd.on_cooldown and (cd.duration or 0) > 2 then
    return math.ceil(cd.remaining or 0)
  end
  return 0
end

--- True if a spell's own cooldown (not GCD) is ready.
local function is_off_cooldown(spell)
  return cd_remaining(spell) == 0
end

-- ── Burst CD management ─────────────────────────────────────────

--- Use burst CDs: Gargoyle → Unholy Frenzy → ERW.
--- Placed between Death Coil and Festering Strike in the ST priority so
--- the sequence naturally becomes: DT → SS → DC → Gargoyle → UF → ERW → FS.
local function UseBurstCDs(enemies, target)
  if not burst_enabled then return false end
  if not target then return false end
  local min_hp = PallasSettings.UnholyBurstMinHP or 15
  if target.HealthPct > 0 and target.HealthPct < min_hp then return false end

  -- Summon Gargoyle (attacks current target for 30s, scales dynamically)
  if S("UnholyUseGargoyle") then
    if PallasSettings.UnholySyncBurst then
      if is_off_cooldown(Spell.UnholyFrenzy) then
        if Spell.SummonGargoyle:CastEx(target) then return true end
      end
    else
      if Spell.SummonGargoyle:CastEx(target) then return true end
    end
  end

  -- Unholy Frenzy (20% haste for 30s, costs health)
  if S("UnholyUseUnholyFrenzy") then
    local uf_min_hp = PallasSettings.UnholyUFMinHP or 30
    if Me.HealthPct >= uf_min_hp then
      if CastNoTarget(Spell.UnholyFrenzy) then return true end
    end
  end

  -- ERW: refill runes during burst window (only when UF is active)
  if S("UnholyUseERW") and Me:HasAura("Unholy Frenzy") then
    if CastNoTarget(Spell.EmpowerRuneWeapon) then return true end
  end

  return false
end

-- ── Burst HUD (ImGui window, drawn every frame) ─────────────────

local function draw_burst_hud()
  if not Me then return end

  -- Lazy-init key code from saved setting
  if burst_key_code == nil then
    burst_key_code = PallasSettings.UnholyBurstKeyCode or 576
  end

  -- Keybind toggle runs every frame regardless of HUD visibility
  if not recording_burst_key and burst_key_code then
    if imgui.is_key_pressed(burst_key_code) then
      burst_enabled = not burst_enabled
    end
  end

  if not PallasSettings.UnholyShowBurst then return end

  imgui.set_next_window_pos(450, 10, COND_FIRST)
  imgui.set_next_window_bg_alpha(0.8)
  local visible = imgui.begin_window("##UnholyBurst", WF_HUD)
  if visible then
    if recording_burst_key then
      imgui.text_colored(1, 1, 0, 1, ">>> Press any key (Esc to cancel) <<<")
      for k = SCAN_MIN, SCAN_MAX do
        if imgui.is_key_pressed(k) then
          if k == 526 then
            recording_burst_key = false
          else
            burst_key_code = k
            PallasSettings.UnholyBurstKeyCode = k
            recording_burst_key = false
          end
          break
        end
      end
    else
      local key_name = KEY_NAMES[burst_key_code]
                       or ("Key" .. tostring(burst_key_code))

      local garg_rem = cd_remaining(Spell.SummonGargoyle)
      local uf_rem   = cd_remaining(Spell.UnholyFrenzy)
      local erw_rem  = cd_remaining(Spell.EmpowerRuneWeapon)

      local cd_line = string.format("Garg: %ds | UF: %ds | ERW: %ds",
          garg_rem >= 0 and garg_rem or 0,
          uf_rem   >= 0 and uf_rem   or 0,
          erw_rem  >= 0 and erw_rem  or 0)

      if not burst_enabled then
        imgui.text_colored(0.6, 0.6, 0.6, 1, "BURST: OFF")
        imgui.text_colored(0.5, 0.5, 0.5, 1, cd_line)
      elseif Me:HasAura("Unholy Frenzy") then
        imgui.text_colored(1, 0.2, 0.2, 1, "BURSTING!")
        imgui.text_colored(1, 0.6, 0.6, 1, cd_line)
      elseif garg_rem == 0 and uf_rem == 0 then
        imgui.text_colored(0.2, 1, 0.2, 1, "BURST: READY")
      else
        imgui.text_colored(1, 0.8, 0, 1, "BURST: ON")
        imgui.text_colored(1, 0.8, 0, 1, cd_line)
      end

      if burst_enabled then
        if imgui.button("Disable Burst", 110, 0) then
          burst_enabled = false
        end
      else
        if imgui.button("Enable Burst", 110, 0) then
          burst_enabled = true
        end
      end

      imgui.same_line()

      if imgui.button("[" .. key_name .. "] Set Key", 100, 0) then
        recording_burst_key = true
      end
    end
  end
  imgui.end_window()
end

-- Register the draw hook (called every frame by plugin.lua)
Pallas._behavior_draw = draw_burst_hud

-- ── Single-Target Priority ────────────────────────────────────

local function SingleTarget(enemies)
  local melee  = MeleeTarget(enemies)
  local ranged = RangedTarget(enemies)
  local target = melee or ranged
  if not target then return false end

  local in_execute = target.HealthPct > 0
      and target.HealthPct < (PallasSettings.UnholySoulReaperThreshold or 35)

  -- 1. Apply / maintain diseases (snapshot-aware)
  if ApplyDiseases(enemies) then return true end

  -- 2. Dark Transformation (5 Shadow Infusion stacks on ghoul)
  if S("UnholyUseDarkTransformation") then
    if CastNoTarget(Spell.DarkTransformation) then return true end
  end

  -- Execute: Soul Reaper + Death and Decay (high priority in execute phase)
  if in_execute and melee then
    if S("UnholyUseSoulReaper") then
      if Spell.SoulReaper:CastEx(melee) then return true end
    end
    if S("UnholyUseDnD") then
      if Spell.DeathAndDecay:CastAtPos(melee) then return true end
    end
  end

  -- 3. Scourge Strike (primary damage, Unholy/Death runes)
  if S("UnholyUseScourgeStrike") and melee then
    if Spell.ScourgeStrike:CastEx(melee) then return true end
  end

  -- 4. Death Coil (>threshold RP or Sudden Doom proc)
  if S("UnholyUseDeathCoil") and ranged then
    local dc_thresh = PallasSettings.UnholyDCThreshold or 40
    if Me.Power >= dc_thresh or Me:HasAura("Sudden Doom") then
      if Spell.DeathCoil:CastEx(ranged) then return true end
    end
  end

  -- 5. Burst CDs (Gargoyle → UF → ERW, gated by keybind toggle)
  if UseBurstCDs(enemies, target) then return true end

  -- 6. Festering Strike (extends diseases, spends Blood + Frost runes)
  if S("UnholyUseFesteringStrike") and melee then
    if Spell.FesteringStrike:CastEx(melee) then return true end
  end

  -- 7. Blood Tap / Plague Leech (rune regeneration)
  if HandleBloodTap() then return true end
  if HandlePlagueLeech(melee or ranged) then return true end

  -- 8. Death Coil (dump remaining RP even below threshold)
  if S("UnholyUseDeathCoil") and ranged and Me.Power >= 40 then
    if Spell.DeathCoil:CastEx(ranged) then return true end
  end

  -- 9. Horn of Winter (filler, generates RP)
  if S("UnholyUseHoWFiller") and CastNoTarget(Spell.HornOfWinter) then return true end

  return false
end

-- ── AoE Priority ──────────────────────────────────────────────

local function AoERotation(enemies)
  local melee   = MeleeTarget(enemies)
  local aoe_tgt = AoeTarget(enemies)
  local ranged  = RangedTarget(enemies)
  local target  = melee or ranged

  -- 1. Apply diseases
  if ApplyDiseases(enemies) then return true end

  -- 2. Pestilence (spread diseases to nearby enemies)
  if S("UnholyUsePestilence") and melee and has_diseases(melee) then
    if Spell.Pestilence:CastEx(melee) then return true end
  end

  -- 3. Death and Decay
  if S("UnholyUseDnD") and melee then
    if Spell.DeathAndDecay:CastAtPos(melee) then return true end
  end

  -- 4. Blood Boil (Blood/Death rune AoE spender)
  if S("UnholyUseBloodBoil") and aoe_tgt then
    if Spell.BloodBoil:CastEx(aoe_tgt) then return true end
  end

  -- 5. Dark Transformation
  if S("UnholyUseDarkTransformation") then
    if CastNoTarget(Spell.DarkTransformation) then return true end
  end

  -- 6. Death Coil (RP dump)
  if S("UnholyUseDeathCoil") and ranged then
    local dc_thresh = PallasSettings.UnholyDCThreshold or 40
    if Me.Power >= dc_thresh or Me:HasAura("Sudden Doom") then
      if Spell.DeathCoil:CastEx(ranged) then return true end
    end
  end

  -- Burst CDs (still use during AoE if toggled on)
  if target and UseBurstCDs(enemies, target) then return true end

  -- 7. Icy Touch (convert Frost runes → Death runes via Blood of the North)
  if S("UnholyUseIcyTouch") and ranged then
    if Spell.IcyTouch:CastEx(ranged) then return true end
  end

  -- 8. Scourge Strike (low priority in AoE, only Unholy runes)
  if S("UnholyUseScourgeStrike") and melee then
    if Spell.ScourgeStrike:CastEx(melee) then return true end
  end

  -- 9. Festering Strike (spend remaining Blood+Frost runes)
  if S("UnholyUseFesteringStrike") and melee then
    if Spell.FesteringStrike:CastEx(melee) then return true end
  end

  -- Rune regeneration
  if HandleBloodTap() then return true end

  -- 10. Horn of Winter (filler)
  if S("UnholyUseHoWFiller") and CastNoTarget(Spell.HornOfWinter) then return true end

  return false
end

-- ── Main Combat Function ──────────────────────────────────────

local was_in_combat = false

local function UnholyDKCombat()
  -- ── Out of combat ──
  if not Me.InCombat then
    if was_in_combat then
      bbox_cache = {}
      was_in_combat = false
    end

    if not Me.IsCasting and not Me.IsChanneling then
      if S("UnholyUseRaiseDead") and not Pet.HasPetOfFamily(Pet.FAMILY_GHOUL) then
        CastNoTarget(Spell.RaiseDead)
      end
    end

    return
  end

  if not was_in_combat then
    was_in_combat = true
  end

  if Me.IsCasting or Me.IsChanneling then return end
  if Spell:IsGCDActive() then return end

  -- ── Self-buffs ──
  if PallasSettings.UnholyMaintainPresence and not Me:HasAura("Unholy Presence") then
    if CastNoTarget(Spell.UnholyPresence) then return end
  end

  if PallasSettings.UnholyMaintainHoW and not Me:HasAura("Horn of Winter") then
    if CastNoTarget(Spell.HornOfWinter) then return end
  end

  -- ── Maintain ghoul (resummon if dead) ──
  if S("UnholyUseRaiseDead") and not Pet.HasPetOfFamily(Pet.FAMILY_GHOUL) then
    if CastNoTarget(Spell.RaiseDead) then return end
  end

  -- ── Defensives ──
  if UseDefensives() then return end

  -- ── Enemies ──
  local enemies = GetCombatEnemies()
  if #enemies == 0 then return end

  -- ── Interrupts ──
  if TryInterrupt(enemies) then return end

  -- ── AoE vs ST ──
  local use_aoe = false
  if PallasSettings.UnholyAoeEnabled then
    local nearby = EnemiesInRange(enemies, AOE_RANGE)
    use_aoe = nearby >= (PallasSettings.UnholyAoeThreshold or 3)
  end

  if use_aoe then
    if not AoERotation(enemies) then
      SingleTarget(enemies)
    end
  else
    SingleTarget(enemies)
  end

  Pallas._tick_throttled = true
end

-- ── Export ───────────────────────────────────────────────────

local behaviors = {
  [BehaviorType.Combat] = UnholyDKCombat,
}

return { Options = options, Behaviors = behaviors }
