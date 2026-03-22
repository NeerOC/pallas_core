-- ═══════════════════════════════════════════════════════════════════
-- Blood Death Knight behavior (MoP 5.5.3)
--
-- Priority-based rotation following the MoP Blood DK guide.
-- Includes opener sequences, advanced Crimson Scourge handling,
-- Vengeance-aware cooldown usage, and QoL toggles.
--
-- Single-Target Priority:
--   1. Death Strike (survivability + prevent rune capping)
--   2. Maintain Frost Fever & Blood Plague via Outbreak
--   3. Rune Strike if about to overcap on Runic Power
--   4. Soul Reaper (<35%) / Heart Strike (Blood rune spender)
--   5. Crimson Scourge proc → DnD (diseases >15s) or Blood Boil (<15s)
--   6. Rune Strike (normal RP dump)
--   7. Horn of Winter (filler)
--
-- AoE Priority (3+ enemies):
--   1. Death and Decay
--   2. Maintain diseases via Outbreak
--   3. Spread diseases (Blood Boil w/ Roiling Blood / Pestilence)
--   4. Blood Boil (Crimson Scourge proc)
--   5. Blood Boil (Blood/Death rune spender)
--   6. Death Strike (survivability)
--   7. Rune Strike (RP dump)
--   8. Horn of Winter (filler)
--
-- Opener Modes:
--   General:        DRW immediately → diseases → normal priority
--   AoE:            DnD → DRW → diseases → AoE priority
--   Damage Focused: DS → HS → DRW (delayed ~3 GCDs for Vengeance)
--
-- Defensives: Vampiric Blood, Icebound Fortitude, Anti-Magic Shell,
--   Rune Tap, Death Pact
-- ═══════════════════════════════════════════════════════════════════

-- ── Menu options ────────────────────────────────────────────────

local function S(uid)
  return PallasSettings[uid] ~= false
end

local options = {
  Name = "Death Knight (Blood)",
  Widgets = {
    { type = "text",     text = "=== Opener ===" },
    { type = "combobox", uid = "BloodOpenerMode",
      text = "Opener mode",                default = 1,
      options = { "Disabled", "General", "AoE", "Damage Focused" } },
    { type = "slider",   uid = "BloodOpenerDuration",
      text = "Opener phase (sec)",         default = 15, min = 5, max = 30 },

    { type = "text",     text = "=== Rotation Spells ===" },
    { type = "checkbox", uid = "BloodUseOutbreak",
      text = "Outbreak",                   default = true },
    { type = "checkbox", uid = "BloodUseIcyTouch",
      text = "Icy Touch",                 default = true },
    { type = "checkbox", uid = "BloodUsePlagueStrike",
      text = "Plague Strike",              default = true },
    { type = "checkbox", uid = "BloodUseDeathStrike",
      text = "Death Strike",               default = true },
    { type = "checkbox", uid = "BloodUseDeathSiphon",
      text = "Death Siphon (high Vengeance trade)", default = false },
    { type = "checkbox", uid = "BloodUseSoulReaper",
      text = "Soul Reaper",                default = true },
    { type = "slider",   uid = "BloodSoulReaperThreshold",
      text = "Soul Reaper HP %",           default = 35, min = 10, max = 50 },
    { type = "checkbox", uid = "BloodUseHeartStrike",
      text = "Heart Strike",               default = true },
    { type = "checkbox", uid = "BloodUseBloodStrike",
      text = "Blood Strike (low level)",   default = true },
    { type = "checkbox", uid = "BloodUseBoneShield",
      text = "Bone Shield",                default = true },
    { type = "checkbox", uid = "BloodUseDnD",
      text = "Death and Decay",            default = true },
    { type = "checkbox", uid = "BloodUseBloodBoil",
      text = "Blood Boil",                 default = true },
    { type = "checkbox", uid = "BloodUsePestilence",
      text = "Pestilence (AoE spread)",    default = true },
    { type = "checkbox", uid = "BloodUseRuneStrike",
      text = "Rune Strike",                default = true },
    { type = "checkbox", uid = "BloodUseDeathCoil",
      text = "Death Coil",                 default = true },
    { type = "checkbox", uid = "BloodPreferDeathCoil",
      text = "Prefer Death Coil over Rune Strike (high Vengeance)",
      default = false },
    { type = "checkbox", uid = "BloodUseHoWFiller",
      text = "Horn of Winter (filler)",    default = true },

    { type = "text",     text = "=== Cooldowns ===" },
    { type = "checkbox", uid = "BloodUseDRW",
      text = "Dancing Rune Weapon",        default = true },
    { type = "checkbox", uid = "BloodDRWHoldForVengeance",
      text = "Hold DRW for Vengeance",     default = false },
    { type = "checkbox", uid = "BloodUseRaiseDead",
      text = "Raise Dead (DPS cooldown)",  default = true },
    { type = "checkbox", uid = "BloodUseERW",
      text = "Empower Rune Weapon",        default = true },
    { type = "checkbox", uid = "BloodERWSyncDRW",
      text = "Sync ERW with DRW window",   default = false },

    { type = "text",     text = "=== Defensives ===" },
    { type = "checkbox", uid = "BloodUseVampiricBlood",
      text = "Vampiric Blood",             default = true },
    { type = "slider",   uid = "BloodVBThreshold",
      text = "Vampiric Blood HP %",        default = 50, min = 20, max = 80 },
    { type = "checkbox", uid = "BloodUseIBF",
      text = "Icebound Fortitude",         default = true },
    { type = "slider",   uid = "BloodIBFThreshold",
      text = "IBF HP %",                   default = 35, min = 15, max = 60 },
    { type = "checkbox", uid = "BloodUseAMS",
      text = "Anti-Magic Shell",           default = false },
    { type = "checkbox", uid = "BloodUseRuneTap",
      text = "Rune Tap",                   default = true },
    { type = "slider",   uid = "BloodRuneTapThreshold",
      text = "Rune Tap HP %",              default = 60, min = 20, max = 80 },
    { type = "checkbox", uid = "BloodUseDeathPact",
      text = "Death Pact (sacrifice ghoul)", default = false },
    { type = "slider",   uid = "BloodDeathPactThreshold",
      text = "Death Pact HP %",            default = 25, min = 10, max = 50 },

    { type = "text",     text = "=== Interrupts ===" },
    { type = "checkbox", uid = "BloodUseInterrupt",
      text = "Mind Freeze",                default = true },
    { type = "combobox", uid = "BloodInterruptMode",
      text = "Interrupt mode",             default = 0,
      options = { "Any interruptible", "Whitelist only" } },

    { type = "text",     text = "=== Utility ===" },
    { type = "checkbox", uid = "BloodMaintainHoW",
      text = "Maintain Horn of Winter",    default = true },
    { type = "checkbox", uid = "BloodMaintainPresence",
      text = "Auto Blood Presence",        default = true },
    { type = "checkbox", uid = "BloodMaintainBoneShieldOOC",
      text = "Bone Shield out of combat",  default = true },

    { type = "text",     text = "=== AoE ===" },
    { type = "checkbox", uid = "BloodAoeEnabled",
      text = "Use AoE rotation",           default = true },
    { type = "slider",   uid = "BloodAoeThreshold",
      text = "AoE enemy count",            default = 3, min = 2, max = 8 },

    { type = "text",     text = "=== Runic Power ===" },
    { type = "slider",   uid = "BloodRPOvercapThreshold",
      text = "RP overcap prevention at",   default = 90, min = 60, max = 120 },
    { type = "slider",   uid = "BloodRSThreshold",
      text = "RP normal dump above",       default = 60, min = 30, max = 110 },

    { type = "text",     text = "=== Advanced ===" },
    { type = "slider",   uid = "BloodDiseaseRefreshSec",
      text = "Disease refresh timer (sec)", default = 4, min = 2, max = 10 },
    { type = "slider",   uid = "BloodCSDiseaseSec",
      text = "Crimson Scourge DnD vs BB cutoff (sec)", default = 15, min = 5, max = 25 },
  },
}

-- ── Constants ──────────────────────────────────────────────────

local AOE_RANGE = 10
local INTERRUPT_WHITELIST = {}

-- ── Self-buff cast helper ────────────────────────────────────────
-- Some self-buff spells (DRW, Bone Shield, ERW, etc.) fail when cast via
-- cast_spell_at_unit because the game rejects a friendly target for them.
-- This helper uses game.cast_spell (no target) and mirrors CastEx logic.

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

-- ── Tank Targeting (priority-based, no player target required) ─

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

local function AoeTarget(enemies)    return GetTargetInRange(enemies, 10)  end
local function RangedTarget(enemies) return GetTargetInRange(enemies, 30)  end
local function AnyTarget(enemies)    return GetTargetInRange(enemies, 40)  end

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
  if not PallasSettings.BloodUseInterrupt then return false end
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

  local wl_mode = (PallasSettings.BloodInterruptMode or 0) == 1
  local tgt_guid = Me.Target and not Me.Target.IsDead and Me.Target.Guid or nil

  for _, entry in ipairs(enemies) do
    if entry.dist_sq > mf_range_sq then goto next_enemy end
    local u = entry.unit
    local is_target = tgt_guid and u.Guid == tgt_guid

    local casting = false
    local spell_id = 0
    local confirmed_immune = false

    if is_target then
      local ok, cast = pcall(game.unit_casting_info, "target")
      if ok and cast then
        casting = true
        spell_id = cast.spell_id or 0
        if cast.not_interruptible then confirmed_immune = true end
      else
        local ok2, chan = pcall(game.unit_channel_info, "target")
        if ok2 and chan then
          casting = true
          spell_id = chan.spell_id or 0
          if chan.not_interruptible then confirmed_immune = true end
        end
      end
    else
      if u.IsCasting then
        casting = true
        spell_id = u.CastingSpellId or 0
      elseif u.IsChanneling then
        casting = true
        spell_id = u.ChannelingSpellId or 0
      end
    end

    if not casting then goto next_enemy end
    if confirmed_immune then goto next_enemy end

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

-- ── Disease Helpers ──────────────────────────────────────────────

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

local function min_disease_remaining(target)
  local ff = target:GetAura("Frost Fever")
  local bp = target:GetAura("Blood Plague")
  local ff_rem = ff and ff.remaining or 0
  local bp_rem = bp and bp.remaining or 0
  if ff_rem <= 0 and bp_rem <= 0 then return 0 end
  if ff_rem <= 0 then return bp_rem end
  if bp_rem <= 0 then return ff_rem end
  return math.min(ff_rem, bp_rem)
end

--- Apply or refresh diseases. During DRW, always refresh via Outbreak
--- for the double disease application snapshot.
local function ApplyDiseases(enemies)
  local melee = MeleeTarget(enemies)
  local ranged = RangedTarget(enemies)
  local target = melee or ranged
  if not target then return false end

  local refresh_sec = PallasSettings.BloodDiseaseRefreshSec or 4
  local in_drw = Me:HasAura("Dancing Rune Weapon")

  -- During DRW, always try to refresh diseases with Outbreak for double snapshot
  local needs_refresh = not has_diseases(target)
      or diseases_expiring(target, refresh_sec)
      or in_drw

  if not needs_refresh then return false end

  if S("BloodUseOutbreak") and ranged then
    if not has_diseases(ranged) or diseases_expiring(ranged, refresh_sec) or in_drw then
      if Spell.Outbreak:CastEx(ranged) then return true end
    end
  end

  if S("BloodUseIcyTouch") and ranged and not ranged:HasAura("Frost Fever") then
    if Spell.IcyTouch:CastEx(ranged) then return true end
  end

  if S("BloodUsePlagueStrike") and melee and not melee:HasAura("Blood Plague") then
    if Spell.PlagueStrike:CastEx(melee) then return true end
  end

  return false
end

-- ── Runic Power Spending ────────────────────────────────────────

--- Spend RP with configurable priority (Rune Strike vs Death Coil).
--- Death Coil trades efficiency (40 RP vs 30 RP) for better AP scaling
--- at high Vengeance, and works at range.
local function SpendRP(enemies, threshold)
  if Me.Power < threshold then return false end
  local melee = MeleeTarget(enemies)
  local ranged = RangedTarget(enemies)

  if PallasSettings.BloodPreferDeathCoil then
    if S("BloodUseDeathCoil") and ranged and Spell.DeathCoil:CastEx(ranged) then return true end
    if S("BloodUseRuneStrike") and melee and Spell.RuneStrike:CastEx(melee) then return true end
  else
    if S("BloodUseRuneStrike") and melee and Spell.RuneStrike:CastEx(melee) then return true end
    if S("BloodUseDeathCoil") and ranged and Spell.DeathCoil:CastEx(ranged) then return true end
  end

  return false
end

-- ── Defensives ─────────────────────────────────────────────────

local function UseDefensives()
  local hp = Me.HealthPct

  if PallasSettings.BloodUseVampiricBlood and hp < (PallasSettings.BloodVBThreshold or 50) then
    if CastNoTarget(Spell.VampiricBlood) then return true end
  end

  if PallasSettings.BloodUseRuneTap and hp < (PallasSettings.BloodRuneTapThreshold or 60) then
    if CastNoTarget(Spell.RuneTap) then return true end
  end

  if PallasSettings.BloodUseIBF and hp < (PallasSettings.BloodIBFThreshold or 35) then
    if CastNoTarget(Spell.IceboundFortitude) then return true end
  end

  if PallasSettings.BloodUseAMS then
    if CastNoTarget(Spell.AntiMagicShell) then return true end
  end

  if PallasSettings.BloodUseDeathPact and hp < (PallasSettings.BloodDeathPactThreshold or 25) then
    if CastNoTarget(Spell.DeathPact) then return true end
  end

  return false
end

-- ── Opener & Cooldown State ─────────────────────────────────────

local combat_enter_time = 0
local opener_done = false

--- Manage offensive cooldowns: DRW, Raise Dead, ERW.
--- Opener mode affects DRW timing during the first few seconds of combat.
local function UseCooldowns(enemies, combat_elapsed)
  -- Dancing Rune Weapon
  if S("BloodUseDRW") then
    local should_drw = true
    local opener_mode = PallasSettings.BloodOpenerMode or 0

    -- Damage Focused opener: delay DRW for ~3 GCDs to build Vengeance first
    if not opener_done and opener_mode == 3 then
      should_drw = combat_elapsed >= 4.5
    end

    -- Outside opener: optionally hold DRW until we have Vengeance
    if opener_done and PallasSettings.BloodDRWHoldForVengeance then
      if not Me:HasAura("Vengeance") then should_drw = false end
    end

    if should_drw and CastNoTarget(Spell.DancingRuneWeapon) then return true end
  end

  -- Raise Dead (DPS cooldown, also provides Death Pact option)
  if S("BloodUseRaiseDead") and not Pet.HasPetOfFamily(Pet.FAMILY_GHOUL) then
    if CastNoTarget(Spell.RaiseDead) then return true end
  end

  -- Empower Rune Weapon: sync with DRW window or use as emergency rune refresh
  if S("BloodUseERW") then
    if PallasSettings.BloodERWSyncDRW then
      if Me:HasAura("Dancing Rune Weapon") then
        if CastNoTarget(Spell.EmpowerRuneWeapon) then return true end
      end
    else
      if not Spell.DeathStrike:IsUsable() and not Spell.HeartStrike:IsUsable() then
        if CastNoTarget(Spell.EmpowerRuneWeapon) then return true end
      end
    end
  end

  return false
end

-- ── Single-Target Priority ────────────────────────────────────

local function SingleTarget(enemies)
  local melee  = MeleeTarget(enemies)
  local ranged = RangedTarget(enemies)

  -- 1. Death Strike — top priority rune spender.
  --    Death Siphon trade: costs 1 Death Rune vs DS's 2 runes.
  --    At high Vengeance, 2x Death Siphon outdamages 1x Death Strike.
  --    Manual toggle since we can't read Attack Power breakpoints.
  if S("BloodUseDeathStrike") and melee then
    if S("BloodUseDeathSiphon") and Spell.DeathSiphon and Spell.DeathSiphon.IsKnown then
      if Me:HasAura("Vengeance") then
        if Spell.DeathSiphon:CastEx(melee) then return true end
      end
    end
    if Spell.DeathStrike:CastEx(melee) then return true end
  end

  -- 2. Maintain Frost Fever & Blood Plague (Outbreak > IT + PS fallback)
  if ApplyDiseases(enemies) then return true end

  -- 3. Rune Strike — prevent RP overcap (high threshold)
  local overcap = PallasSettings.BloodRPOvercapThreshold or 90
  if SpendRP(enemies, overcap) then return true end

  -- 4. Soul Reaper / Heart Strike / Blood Strike (Blood rune spenders)
  if melee then
    local sr_thresh = PallasSettings.BloodSoulReaperThreshold or 35
    if S("BloodUseSoulReaper") and melee.HealthPct > 0 and melee.HealthPct < sr_thresh then
      if Spell.SoulReaper:CastEx(melee) then return true end
    end
    if S("BloodUseHeartStrike") and Spell.HeartStrike:CastEx(melee) then return true end
    if S("BloodUseBloodStrike") and Spell.BloodStrike:CastEx(melee) then return true end
  end

  -- 5. Crimson Scourge proc: DnD if diseases are healthy, Blood Boil if expiring.
  --    DnD deals more damage; BB refreshes/spreads diseases via Roiling Blood.
  if Me:HasAura("Crimson Scourge") then
    local cs_target = melee or AoeTarget(enemies)
    if cs_target then
      local cs_cutoff = PallasSettings.BloodCSDiseaseSec or 15
      if min_disease_remaining(cs_target) > cs_cutoff then
        if S("BloodUseDnD") and Spell.DeathAndDecay:CastAtPos(cs_target) then return true end
        if S("BloodUseBloodBoil") and Spell.BloodBoil:CastEx(cs_target) then return true end
      else
        if S("BloodUseBloodBoil") and Spell.BloodBoil:CastEx(cs_target) then return true end
        if S("BloodUseDnD") and Spell.DeathAndDecay:CastAtPos(cs_target) then return true end
      end
    end
  end

  -- 6. Rune Strike — normal RP dump (lower threshold)
  local dump = PallasSettings.BloodRSThreshold or 60
  if SpendRP(enemies, dump) then return true end

  -- 7. Horn of Winter — filler (generates Runic Power)
  if S("BloodUseHoWFiller") and CastNoTarget(Spell.HornOfWinter) then return true end

  return false
end

-- ── AoE Priority ──────────────────────────────────────────────

local function AoERotation(enemies)
  local melee   = MeleeTarget(enemies)
  local aoe_tgt = AoeTarget(enemies)
  local ranged  = RangedTarget(enemies)

  -- 1. Death and Decay (highest AoE priority)
  if S("BloodUseDnD") and melee and Spell.DeathAndDecay:CastAtPos(melee) then return true end

  -- 2. Maintain diseases via Outbreak
  if ApplyDiseases(enemies) then return true end

  -- 3. Spread diseases: Pestilence (or Blood Boil with Roiling Blood)
  if S("BloodUsePestilence") and melee and has_diseases(melee) then
    if Spell.Pestilence:CastEx(melee) then return true end
  end

  -- 4. Blood Boil on Crimson Scourge proc (free, no rune cost)
  if S("BloodUseBloodBoil") and Me:HasAura("Crimson Scourge") and aoe_tgt then
    if Spell.BloodBoil:CastEx(aoe_tgt) then return true end
  end

  -- 5. Blood Boil (main AoE rune spender — replaces Heart Strike)
  if S("BloodUseBloodBoil") and aoe_tgt and Spell.BloodBoil:CastEx(aoe_tgt) then return true end

  -- 6. Death Strike (survivability, lower priority in AoE)
  if S("BloodUseDeathStrike") and melee then
    if S("BloodUseDeathSiphon") and Spell.DeathSiphon and Spell.DeathSiphon.IsKnown then
      if Me:HasAura("Vengeance") then
        if Spell.DeathSiphon:CastEx(melee) then return true end
      end
    end
    if Spell.DeathStrike:CastEx(melee) then return true end
  end

  -- 7. Blood Strike (low-level fallback)
  if S("BloodUseBloodStrike") and melee and Spell.BloodStrike:CastEx(melee) then return true end

  -- 8. RP dump: overcap prevention then normal dump
  local overcap = PallasSettings.BloodRPOvercapThreshold or 90
  if SpendRP(enemies, overcap) then return true end
  local dump = PallasSettings.BloodRSThreshold or 60
  if SpendRP(enemies, dump) then return true end

  -- 9. Horn of Winter — filler
  if S("BloodUseHoWFiller") and CastNoTarget(Spell.HornOfWinter) then return true end

  return false
end

-- ── Main Combat Function ──────────────────────────────────────

local was_in_combat = false

local function BloodDKCombat()
  -- Out of combat maintenance
  if not Me.InCombat then
    if was_in_combat then
      bbox_cache = {}
      was_in_combat = false
      opener_done = false
      combat_enter_time = 0
    end

    -- Bone Shield out of combat (30s+ before pull per guide)
    if PallasSettings.BloodMaintainBoneShieldOOC then
      if S("BloodUseBoneShield") and not Me:HasAura("Bone Shield") then
        if not Me.IsCasting and not Me.IsChanneling then
          CastNoTarget(Spell.BoneShield)
        end
      end
    end

    return
  end

  -- Track combat entry for opener phase
  if not was_in_combat then
    was_in_combat = true
    combat_enter_time = os.clock()
    opener_done = false
  end

  if Me.IsCasting or Me.IsChanneling then return end
  if Spell:IsGCDActive() then return end

  local combat_elapsed = os.clock() - combat_enter_time
  local opener_duration = PallasSettings.BloodOpenerDuration or 15
  if combat_elapsed > opener_duration then opener_done = true end

  -- Self-buffs
  if PallasSettings.BloodMaintainPresence then
    if not Me:HasAura("Blood Presence") then
      if CastNoTarget(Spell.BloodPresence) then return end
    end
  end

  if PallasSettings.BloodMaintainHoW then
    if not Me:HasAura("Horn of Winter") then
      if CastNoTarget(Spell.HornOfWinter) then return end
    end
  end

  -- Defensives (highest combat priority)
  if UseDefensives() then return end

  local enemies = GetCombatEnemies()
  if #enemies == 0 then return end

  -- Interrupts
  if TryInterrupt(enemies) then return end

  -- Bone Shield maintenance (should always be active)
  if S("BloodUseBoneShield") and not Me:HasAura("Bone Shield") then
    if CastNoTarget(Spell.BoneShield) then return end
  end

  -- Offensive cooldowns (DRW, Raise Dead, ERW)
  if UseCooldowns(enemies, combat_elapsed) then return end

  -- Determine rotation: AoE vs Single-Target
  local use_aoe = false
  if PallasSettings.BloodAoeEnabled then
    local nearby = EnemiesInRange(enemies, AOE_RANGE)
    use_aoe = nearby >= (PallasSettings.BloodAoeThreshold or 3)
  end

  -- AoE opener mode forces AoE rotation during opener phase
  local opener_mode = PallasSettings.BloodOpenerMode or 0
  if not opener_done and opener_mode == 2 then
    use_aoe = true
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
  [BehaviorType.Combat] = BloodDKCombat,
}

return { Options = options, Behaviors = behaviors }
