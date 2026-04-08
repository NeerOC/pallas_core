-- ═══════════════════════════════════════════════════════════════════
-- Blood Death Knight behavior (MoP 5.5.3)
--
-- Priority-based rotation following the MoP Blood DK guide.
-- Includes opener sequences, advanced Crimson Scourge handling,
-- Vengeance-aware cooldown usage, and QoL toggles.
--
-- Single-Target Priority (guide-accurate split DS):
--   1. Death Strike if runes are about to cap (DS + HS both usable)
--   2. Maintain Frost Fever & Blood Plague via Outbreak
--   3. Rune Strike if about to overcap on Runic Power
--   4. Death Strike for healing (below HP threshold)
--   5. Rune Strike (normal RP dump)
--   6. Crimson Scourge proc → DnD (diseases >15s) or Blood Boil (<15s)
--   7. Soul Reaper (<35%) / Heart Strike (HP >= 70% gate)
--   8. Death Strike (fallback — never sit on runes)
--   9. Heart Strike / Blood Strike (low-HP fallback — Blood runes don't
--      feed DS so sitting on them wastes damage and threat)
--  10. Rune Strike / Death Coil (low-RP fallback at 30+)
--  11. Horn of Winter (filler)
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
      text = "Pestilence (disease spread)", default = true },
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
    { type = "checkbox", uid = "BloodSmartAMS",
      text = "Smart AMS (react to incoming magic casts)",
      default = true },
    { type = "slider",   uid = "BloodAMSReactTime",
      text = "AMS react time (sec remaining)", default = 1.5, min = 0.1, max = 3.0, step = 0.1 },
    { type = "checkbox", uid = "BloodUseRuneTap",
      text = "Rune Tap",                   default = true },
    { type = "slider",   uid = "BloodRuneTapThreshold",
      text = "Rune Tap HP %",              default = 60, min = 20, max = 80 },
    { type = "checkbox", uid = "BloodRuneTapVBSync",
      text = "Rune Tap only during Vampiric Blood (+15% healing)",
      default = false },
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

    { type = "text",     text = "=== Threat Management ===" },
    { type = "checkbox", uid = "BloodThreatTarget",
      text = "Prioritize loose mobs (threat-aware targeting)", default = true },
    { type = "checkbox", uid = "BloodUseTaunt",
      text = "Dark Command (taunt loose mobs)", default = true },
    { type = "checkbox", uid = "BloodUseDeathGrip",
      text = "Death Grip (ranged taunt)",  default = true },

    { type = "text",     text = "=== Utility ===" },
    { type = "checkbox", uid = "BloodMaintainHoW",
      text = "Maintain Horn of Winter",    default = true },
    { type = "checkbox", uid = "BloodMaintainPresence",
      text = "Auto Blood Presence",        default = true },
    { type = "checkbox", uid = "BloodMaintainBoneShieldOOC",
      text = "Bone Shield out of combat",  default = true },
    { type = "checkbox", uid = "BloodAutoFace",
      text = "Auto face target for casts", default = false },

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
    { type = "checkbox", uid = "BloodSmartRP",
      text = "HP-aware RP (skip dump when DS available & low HP)",
      default = true },
    { type = "slider",   uid = "BloodRSConserveHP",
      text = "Conserve RP below HP %",     default = 60, min = 20, max = 95 },

    { type = "text",     text = "=== Advanced ===" },
    { type = "slider",   uid = "BloodDSHealHP",
      text = "Death Strike heal priority below HP %", default = 95, min = 50, max = 100 },
    { type = "slider",   uid = "BloodHSMinHP",
      text = "Heart Strike min HP % (preserve runes for DS)", default = 70, min = 30, max = 100 },
    { type = "slider",   uid = "BloodDiseaseRefreshSec",
      text = "Disease refresh timer (sec)", default = 4, min = 2, max = 10 },
    { type = "slider",   uid = "BloodCSDiseaseSec",
      text = "Crimson Scourge DnD vs BB cutoff (sec)", default = 15, min = 5, max = 25 },
    { type = "checkbox", uid = "BloodCinderglacierAware",
      text = "Cinderglacier awareness (DC>RS when proc active, snapshot diseases)",
      default = false },
  },
}

-- ── Constants ──────────────────────────────────────────────────

local AOE_RANGE = 10
local INTERRUPT_WHITELIST = {}
local SCHOOL_PHYSICAL = 1

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
    Pallas._tick_throttled = true
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

local MELEE_LEEWAY = 4.0 / 3.0
local MELEE_MIN    = 5.0

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
    if not eu.in_combat then
      if not (Pallas.IsWhitelisted and Pallas.IsWhitelisted(eu.name or e.name)) then
        goto skip
      end
    end

    local a_ok, attackable = pcall(game.unit_is_attackable, e.obj_ptr)
    if a_ok and not attackable then goto skip end

    local u = Unit:New(e)
    if u:IsImmune() then goto skip end

    if e.position then
      local dx = mx - e.position.x
      local dy = my - e.position.y
      local dz = mz - e.position.z
      local dist_sq = dx * dx + dy * dy + dz * dz
      if dist_sq <= 1600 then
        if TTD then TTD.Update(u) end
        results[#results + 1] = {
          unit = u,
          dist_sq = dist_sq,
        }
      end
    end
    ::skip::
  end

  if TTD then TTD.Cleanup() end
  table.sort(results, function(a, b) return a.dist_sq < b.dist_sq end)
  return results
end

-- Check if we do NOT have the highest threat on a mob (i.e. it's "loose").
-- Uses game.unit_threat (threat table lookup) instead of game.unit_target
-- because unit_target changes temporarily during random-target casts.
-- raw_pct == 100 means we are the top threat holder; < 100 means someone
-- else has more threat and the mob is genuinely loose.
-- Caches results per-tick via the entry table to avoid repeated game calls.
local function IsLooseMob(entry)
  if entry._loose ~= nil then return entry._loose end
  local u = entry.unit
  local ok, is_tanking, status, scaled_pct, raw_pct = pcall(game.unit_threat, u.obj_ptr)
  if not ok or is_tanking == nil then
    -- Not on the mob's threat table at all — definitely loose
    entry._loose = true
    return true
  end
  -- raw_pct < 100 means someone else has more threat than us
  entry._loose = (raw_pct or 0) < 100
  return entry._loose
end

local function GetTargetInRange(enemies, range_yd)
  local range_sq = range_yd * range_yd
  local tgt_guid = Me.Target and not Me.Target.IsDead and Me.Target.Guid or nil
  local threat_aware = S("BloodThreatTarget")

  local best_loose = nil
  local best_any   = nil

  for _, entry in ipairs(enemies) do
    if entry.dist_sq > range_sq then break end

    -- Current target is always an acceptable pick
    if tgt_guid and entry.unit.Guid == tgt_guid then
      if not threat_aware then return entry.unit end
      -- Even with threat-aware on, if our current target is loose prefer it
      if IsLooseMob(entry) then return entry.unit end
      best_any = best_any or entry.unit
    else
      if threat_aware and not best_loose and IsLooseMob(entry) then
        best_loose = entry.unit
      end
      best_any = best_any or entry.unit
    end
  end

  return best_loose or best_any
end

local function MeleeTarget(enemies)
  local tgt_guid = Me.Target and not Me.Target.IsDead and Me.Target.Guid or nil
  local my_cr = Me.CombatReach or 0
  local threat_aware = S("BloodThreatTarget")

  local best_loose = nil
  local best_any   = nil

  for _, entry in ipairs(enemies) do
    if entry.dist_sq > 225 then break end
    local their_cr = entry.unit.CombatReach or 0
    local range = my_cr + their_cr + MELEE_LEEWAY
    if range < MELEE_MIN then range = MELEE_MIN end
    if entry.dist_sq <= range * range then
      if tgt_guid and entry.unit.Guid == tgt_guid then
        if not threat_aware then return entry.unit end
        if IsLooseMob(entry) then return entry.unit end
        best_any = best_any or entry.unit
      else
        if threat_aware and not best_loose and IsLooseMob(entry) then
          best_loose = entry.unit
        end
        best_any = best_any or entry.unit
      end
    end
  end

  return best_loose or best_any
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

local function enemies_need_spread(enemies, range_yd)
  local range_sq = (range_yd or 15) * (range_yd or 15)
  for _, entry in ipairs(enemies) do
    if entry.dist_sq > range_sq then break end
    if not has_diseases(entry.unit) then return true end
  end
  return false
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

--- Apply, refresh, and spread diseases. During DRW, always refresh via
--- Outbreak for the double disease application snapshot.
local function ApplyDiseases(enemies)
  local melee = MeleeTarget(enemies)
  local ranged = RangedTarget(enemies)
  local target = melee or ranged
  if not target then return false end

  local refresh_sec = PallasSettings.BloodDiseaseRefreshSec or 4
  local in_drw = Me:HasAura("Dancing Rune Weapon")

  local ff_aura = target:GetAura("Frost Fever")
  local bp_aura = target:GetAura("Blood Plague")
  local has_ff  = ff_aura ~= nil
  local has_bp  = bp_aura ~= nil
  local ff_low  = not has_ff or (ff_aura.remaining or 0) < refresh_sec
  local bp_low  = not has_bp or (bp_aura.remaining or 0) < refresh_sec

  -- Cinderglacier snapshot: when the enchant proc is active, reapply
  -- diseases via Outbreak for a stronger damage snapshot (shadow bonus).
  local cg_snapshot = PallasSettings.BloodCinderglacierAware
      and Me:HasAura("Cinderglacier")
  if cg_snapshot and S("BloodUseOutbreak") and Spell.Outbreak:IsReady() and ranged then
    if Spell.Outbreak:CastEx(ranged) then return true end
  end

  local needs_refresh = ff_low or bp_low or in_drw

  if needs_refresh then
    -- Outbreak applies both diseases at once (preferred, especially during DRW)
    if S("BloodUseOutbreak") and ranged then
      if Spell.Outbreak:CastEx(ranged) then return true end
    end

    -- Blood Boil refreshes existing diseases via Roiling Blood — more
    -- rune-efficient than IT+PS when diseases are present but expiring.
    -- Only use when both diseases are already on the target (refresh, not apply).
    if has_ff and has_bp and S("BloodUseBloodBoil") and melee then
      if Spell.BloodBoil:CastEx(melee) then return true end
    end

    -- Icy Touch: apply/refresh Frost Fever
    if ff_low and S("BloodUseIcyTouch") and ranged then
      if Spell.IcyTouch:CastEx(ranged) then return true end
    end

    -- Plague Strike: apply/refresh Blood Plague
    if bp_low and S("BloodUsePlagueStrike") and melee then
      if Spell.PlagueStrike:CastEx(melee) then return true end
    end
  end

  -- Spread: Pestilence when our target has diseases but nearby enemies don't
  if S("BloodUsePestilence") and melee and has_ff and has_bp then
    if enemies_need_spread(enemies, 15) then
      if Spell.Pestilence:CastEx(melee) then return true end
    end
  end

  return false
end

-- ── Runic Power Spending ────────────────────────────────────────

--- Spend RP with configurable priority (Rune Strike vs Death Coil).
--- HP-aware: at low HP, conserve RP when Death Strike is available
--- so we can use runes on healing instead of wasting GCDs on damage.
local function SpendRP(enemies, threshold)
  if Me.Power < threshold then return false end

  -- HP-aware gating: skip RP dump when we should be Death Striking
  if S("BloodSmartRP") then
    local hp = Me.HealthPct
    local ds_usable = Spell.DeathStrike:IsUsable()
    local conserve_hp = PallasSettings.BloodRSConserveHP or 60
    if hp < conserve_hp and ds_usable then return false end
  end

  -- DRW RP saving: when DRW is about to come off CD (< 5s), hold RP >=60
  -- so we can Rune Strike spam during the DRW window for double damage.
  if S("BloodUseDRW") and not Me:HasAura("Dancing Rune Weapon") then
    local drw_cd = Spell.DancingRuneWeapon:GetCooldown()
    if drw_cd then
      local should_save = false
      if not drw_cd.on_cooldown then
        should_save = true
      elseif drw_cd.remaining and drw_cd.remaining < 5 then
        should_save = true
      end
      if should_save and Me.Power < 60 then return false end
    end
  end

  local melee = MeleeTarget(enemies)
  local ranged = RangedTarget(enemies)

  -- Cinderglacier awareness: when the enchant proc is active, Death Coil
  -- consumes a charge for bonus shadow damage — prioritize DC over RS.
  local cg_active = PallasSettings.BloodCinderglacierAware
      and Me:HasAura("Cinderglacier")
  local prefer_dc = PallasSettings.BloodPreferDeathCoil or cg_active

  if prefer_dc then
    if S("BloodUseDeathCoil") and ranged and Spell.DeathCoil:CastEx(ranged) then return true end
    if S("BloodUseRuneStrike") and melee and Spell.RuneStrike:CastEx(melee) then return true end
  else
    if S("BloodUseRuneStrike") and melee and Spell.RuneStrike:CastEx(melee) then return true end
    if S("BloodUseDeathCoil") and ranged and Spell.DeathCoil:CastEx(ranged) then return true end
  end

  return false
end

-- ── Defensives ─────────────────────────────────────────────────

--- Detect if any enemy is casting a non-physical spell at us that is
--- close to finishing.  Uses live casting info for target/focus, and
--- OM snapshot + game_time() for other mobs.
local function ShouldUseSmartAMS(enemies)
  if not Spell.AntimagicShell.IsKnown then return false end
  if not Spell.AntimagicShell:IsReady() then return false end
  if Me:HasAura("Anti-Magic Shell") then return false end

  local react = PallasSettings.BloodAMSReactTime or 1.5
  local my_guid = Me.Guid
  local my_lo, my_hi = Me.guid_lo, Me.guid_hi
  local now_gt = nil

  for _, entry in ipairs(enemies) do
    local u = entry.unit
    if not u.IsCasting and not u.IsChanneling then goto next_ams end

    local spell_id = 0
    if u.IsCasting then
      spell_id = u.CastingSpellId or 0
    elseif u.IsChanneling then
      spell_id = u.ChannelingSpellId or 0
    end
    if spell_id == 0 then goto next_ams end

    -- Is this mob targeting us?  Prefer CLEU cast-target when available,
    -- otherwise read the mob's current target descriptor directly.
    local targeting_us = false
    if u.CastTargetLo ~= 0 or u.CastTargetHi ~= 0 then
      targeting_us = (u.CastTargetLo == my_lo and u.CastTargetHi == my_hi)
    else
      local tok, tgt = pcall(game.unit_target, u.obj_ptr)
      if tok and tgt and tgt.guid == my_guid then
        targeting_us = true
      end
    end
    if not targeting_us then goto next_ams end

    -- Skip purely physical spells (AMS only absorbs magic).
    -- Treat unknown (0) as non-physical to be safe — most mob casts are magic.
    local sok, school = pcall(game.get_spell_school, spell_id)
    if sok and school == SCHOOL_PHYSICAL then goto next_ams end

    -- Compute remaining cast time
    local remaining = 999

    -- Live data available for our current target
    if Me.Target and not Me.Target.IsDead and Me.Target.Guid == u.Guid then
      local ok, cast = pcall(game.unit_casting_info, "target")
      if ok and cast then
        remaining = cast.remaining or 999
      else
        local ok2, chan = pcall(game.unit_channel_info, "target")
        if ok2 and chan then remaining = chan.remaining or 999 end
      end
    end

    -- Fallback: OM snapshot timing (CastEnd is already in seconds)
    if remaining == 999 then
      local cast_end = u.IsCasting and u.CastEnd or u.ChannelEnd
      if cast_end and cast_end > 0 then
        if not now_gt then
          local ok, t = pcall(game.game_time)
          now_gt = ok and t or 0
        end
        if now_gt > 0 then
          remaining = cast_end - now_gt
          if remaining < 0 then remaining = 0 end
        end
      end
    end

    if remaining <= react then
      return true
    end

    ::next_ams::
  end
  return false
end

local function UseDefensives(enemies)
  local hp = Me.HealthPct

  if PallasSettings.BloodUseVampiricBlood and hp < (PallasSettings.BloodVBThreshold or 50) then
    if CastNoTarget(Spell.VampiricBlood) then return true end
  end

  -- Rune Tap: maximized when VB is active (+15% healing received).
  -- If VB synergy is enabled, only use during VB; otherwise use at threshold.
  if PallasSettings.BloodUseRuneTap and hp < (PallasSettings.BloodRuneTapThreshold or 60) then
    if not PallasSettings.BloodRuneTapVBSync or Me:HasAura("Vampiric Blood") then
      if CastNoTarget(Spell.RuneTap) then return true end
    end
  end

  if PallasSettings.BloodUseIBF and hp < (PallasSettings.BloodIBFThreshold or 35) then
    if CastNoTarget(Spell.IceboundFortitude) then return true end
  end

  -- Smart AMS: react to incoming non-physical casts targeting us
  if S("BloodSmartAMS") and enemies and ShouldUseSmartAMS(enemies) then
    if CastNoTarget(Spell.AntimagicShell) then return true end
  end

  -- Fallback: always-on AMS (original behavior, only when smart AMS is off)
  if PallasSettings.BloodUseAMS and not S("BloodSmartAMS") then
    if CastNoTarget(Spell.AntimagicShell) then return true end
  end

  -- Death Pact: sacrifice ghoul for emergency heal.
  -- Two-step: summon ghoul first if none exists, then sacrifice next tick.
  if PallasSettings.BloodUseDeathPact and hp < (PallasSettings.BloodDeathPactThreshold or 25) then
    if not Pet.HasPet() then
      if CastNoTarget(Spell.RaiseDead) then return true end
    else
      if CastNoTarget(Spell.DeathPact) then return true end
    end
  end

  return false
end

-- ── Threat Management ────────────────────────────────────────────

--- Taunt or grip any mob that is NOT targeting us.
--- Uses IsLooseMob (game.unit_target) which is cheaper than walking
--- the full threat list and catches all loose mobs regardless of
--- who is top threat.
local function TryTauntLoose(enemies)
  local use_taunt = S("BloodUseTaunt")
  local use_grip  = S("BloodUseDeathGrip")
  if not use_taunt and not use_grip then return false end

  local my_cr = Me.CombatReach or 0

  for _, entry in ipairs(enemies) do
    if not IsLooseMob(entry) then goto next_taunt end

    local u = entry.unit

    -- Dark Command (30yd taunt — preferred)
    if use_taunt and Spell.DarkCommand and Spell.DarkCommand.IsKnown then
      if Spell.DarkCommand:CastEx(u) then return true end
    end

    -- Death Grip (30yd — use on out-of-melee mobs, or if taunt is on CD)
    if use_grip and Spell.DeathGrip and Spell.DeathGrip.IsKnown then
      local their_cr = u.CombatReach or 0
      local melee_range = my_cr + their_cr + MELEE_LEEWAY
      if melee_range < MELEE_MIN then melee_range = MELEE_MIN end
      if entry.dist_sq > melee_range * melee_range then
        if Spell.DeathGrip:CastEx(u) then return true end
      end
    end

    ::next_taunt::
  end
  return false
end

-- ── Snap Threat (damage abilities on loose mobs) ────────────────
-- When taunt/grip are both on CD but there are loose mobs in melee,
-- actively target them with threat-generating damage abilities.
-- Blood Boil is the best snap-threat tool (instant AoE, no target needed).
-- After that, direct abilities at the loose mob.
local function TrySnapThreat(enemies)
  if not S("BloodThreatTarget") then return false end

  -- Check if any loose mob exists in melee range
  local my_cr = Me.CombatReach or 0
  local loose_melee = nil
  local loose_any   = nil
  for _, entry in ipairs(enemies) do
    if entry.dist_sq > 225 then break end
    if IsLooseMob(entry) then
      local their_cr = entry.unit.CombatReach or 0
      local range = my_cr + their_cr + MELEE_LEEWAY
      if range < MELEE_MIN then range = MELEE_MIN end
      if entry.dist_sq <= range * range then
        loose_melee = loose_melee or entry.unit
      end
      loose_any = loose_any or entry.unit
    end
  end
  if not loose_melee and not loose_any then return false end

  -- Blood Boil: instant AoE threat on everything around us (no target needed)
  if loose_melee and S("BloodUseBloodBoil") then
    if Spell.BloodBoil:CastEx(loose_melee) then return true end
  end

  -- Death Strike the loose mob for massive single-target threat
  if loose_melee and S("BloodUseDeathStrike") then
    if Spell.DeathStrike:CastEx(loose_melee) then return true end
  end

  -- Heart Strike the loose mob (cleaves nearby, good snap threat)
  if loose_melee and S("BloodUseHeartStrike") then
    if Spell.HeartStrike:CastEx(loose_melee) then return true end
  end

  -- Icy Touch at range if we can't melee it yet
  if loose_any and not loose_melee then
    if Spell.IcyTouch:CastEx(loose_any) then return true end
  end

  return false
end

-- ── Smart Soul Reaper (haste proc on dying mobs) ────────────────
-- Soul Reaper haste buff (114868): 50% haste for 5s when a SR-debuffed
-- target dies.  Scan all nearby enemies and cast SR on anything that
-- will die within ~5 seconds, unless we already have the buff active.
local SOUL_REAPER_HASTE = 114868

local function TrySmartSoulReaper(enemies)
  if not S("BloodUseSoulReaper") then return false end
  if not Spell.SoulReaper or not Spell.SoulReaper.IsKnown then return false end
  if not Spell.SoulReaper:IsReady() then return false end
  if not TTD then return false end

  local sr_aura = Me:GetAura(SOUL_REAPER_HASTE)
  if sr_aura and sr_aura.remaining and sr_aura.remaining > 1 then return false end

  local my_cr = Me.CombatReach or 0
  for _, entry in ipairs(enemies) do
    if entry.dist_sq > 225 then break end
    local u = entry.unit
    local their_cr = u.CombatReach or 0
    local range = my_cr + their_cr + MELEE_LEEWAY
    if range < MELEE_MIN then range = MELEE_MIN end
    if entry.dist_sq <= range * range then
      local ttd = TTD.Get(u)
      if ttd <= 5 and ttd > 0.5 then
        if Spell.SoulReaper:CastEx(u) then return true end
      end
    end
  end
  return false
end

-- ── Auto Facing ──────────────────────────────────────────────────

local pending_face_restore = nil
local face_restore_at = 0

local pending_face_restore = nil
local face_restore_at = 0

--- If auto-face is enabled and we aren't facing our primary target,
--- snap toward them and schedule a facing restore after the cast window.
--- Called once at the start of each combat tick so all subsequent casts
--- in the priority list can pass their facing checks.
local function AutoFaceTarget(enemies)
  if not PallasSettings.BloodAutoFace then return end
  if not Me or not Me.obj_ptr then return end

  local target = MeleeTarget(enemies) or RangedTarget(enemies)
  if not target or not target.obj_ptr then return end

  local fok, facing = pcall(game.is_facing, Me.obj_ptr, target.obj_ptr)
  if fok and facing then return end

  local tp = target.Position
  local mp = Me.Position
  if not tp or not mp then return end

  local cur_ok, cur_facing = pcall(game.entity_facing, Me.obj_ptr)
  if not cur_ok then return end

  local desired = game.angle_to(mp.x, mp.y, tp.x, tp.y)
  game.set_facing(desired, cur_facing)
  pending_face_restore = cur_facing
  face_restore_at = os.clock() + 0.4
end

local function UpdateFaceRestore()
  if pending_face_restore and os.clock() >= face_restore_at then
    local cur_ok, cur = pcall(game.entity_facing, Me.obj_ptr)
    if cur_ok then
      game.set_facing(pending_face_restore, cur)
    end
    pending_face_restore = nil
  end
end

-- ── Opener & Cooldown State ─────────────────────────────────────

local combat_enter_time = 0
local opener_done = false

--- Manage offensive cooldowns: DRW, Raise Dead, ERW.
--- Opener mode affects DRW timing during the first few seconds of combat.
local function UseCooldowns(enemies, combat_elapsed)
  -- Target TTD check: don't waste DRW on a target about to die
  local primary = MeleeTarget(enemies) or RangedTarget(enemies)
  local target_ttd = (TTD and primary) and TTD.Get(primary) or 999

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

    -- Don't waste DRW on a target dying in < 10s
    if target_ttd < 10 then should_drw = false end

    if should_drw and CastNoTarget(Spell.DancingRuneWeapon) then return true end
  end

  -- Raise Dead (DPS cooldown, also provides Death Pact option)
  if S("BloodUseRaiseDead") and not Pet.HasPetOfFamily(Pet.FAMILY_GHOUL) then
    if CastNoTarget(Spell.RaiseDead) then return true end
  end

  -- Empower Rune Weapon: sync with DRW window or use as emergency rune refresh.
  -- 5-min CD — require ALL 6 runes on CD AND low RP.  Never waste on dying target.
  if S("BloodUseERW") and target_ttd > 15 then
    if PallasSettings.BloodERWSyncDRW then
      if Me:HasAura("Dancing Rune Weapon") then
        if CastNoTarget(Spell.EmpowerRuneWeapon) then return true end
      end
    else
      local rs = Rune and Rune.GetState() or nil
      local fully_depleted = false
      if rs then
        fully_depleted = Rune.IsFullyDepleted(rs)
      else
        fully_depleted = not Spell.DeathStrike:IsUsable()
            and not Spell.HeartStrike:IsUsable()
            and not Spell.BloodBoil:IsUsable()
      end
      if fully_depleted and Me.Power < 40 then
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
  local hp = Me.HealthPct
  local hs_min_hp = PallasSettings.BloodHSMinHP or 70

  local rs = Rune and Rune.GetState() or nil

  -- 1. Death Strike — prevent rune capping.  If both DS and HS runes are
  --    sitting ready we're about to waste regeneration. Prefer direct rune
  --    checks over IsUsable() which can't distinguish "no runes" from
  --    "on GCD".
  if S("BloodUseDeathStrike") and melee then
    local capping = rs and Rune.IsRuneCapping(rs, "blood")
      or (Spell.DeathStrike:IsUsable() and Spell.HeartStrike.IsKnown and Spell.HeartStrike:IsUsable())

    if capping then
      if S("BloodUseDeathSiphon") and Spell.DeathSiphon and Spell.DeathSiphon.IsKnown then
        if Me:HasAura("Vengeance") then
          if Spell.DeathSiphon:CastEx(melee) then return true end
        end
      end
      if Spell.DeathStrike:CastEx(melee) then return true end
    end
  end

  -- 2. Maintain Frost Fever & Blood Plague (Outbreak > IT + PS fallback)
  if ApplyDiseases(enemies) then return true end

  -- 3. Rune Strike — prevent RP overcap (high threshold)
  local overcap = PallasSettings.BloodRPOvercapThreshold or 90
  if SpendRP(enemies, overcap) then return true end

  -- 4. Death Strike — use when we've taken damage and need healing.
  --    At high HP, skip to let Blood runes go to Heart Strike for damage.
  if S("BloodUseDeathStrike") and melee and hp < (PallasSettings.BloodDSHealHP or 95) then
    if S("BloodUseDeathSiphon") and Spell.DeathSiphon and Spell.DeathSiphon.IsKnown then
      if Me:HasAura("Vengeance") then
        if Spell.DeathSiphon:CastEx(melee) then return true end
      end
    end
    if Spell.DeathStrike:CastEx(melee) then return true end
  end

  -- 5. Rune Strike — normal RP dump
  local dump = PallasSettings.BloodRSThreshold or 60
  if SpendRP(enemies, dump) then return true end

  -- 6. Crimson Scourge proc: free DnD or Blood Boil — use before spending
  --    Blood runes on Heart Strike.  DnD preferred when diseases are healthy;
  --    Blood Boil when diseases need refresh (Roiling Blood re-applies them).
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

  -- 7. Soul Reaper / Heart Strike / Blood Strike (Blood rune spenders)
  --    Heart Strike preferred at higher HP so Blood runes feed damage
  --    rather than sit idle.
  if melee then
    if S("BloodUseSoulReaper") and melee.HealthPct > 0 then
      local sr_thresh = PallasSettings.BloodSoulReaperThreshold or 35
      if melee.HealthPct < sr_thresh then
        if Spell.SoulReaper:CastEx(melee) then return true end
      elseif melee.HealthPct < sr_thresh + 5 then
        if Spell.SoulReaper:CastEx(melee) then return true end
      end
    end

    if hp >= hs_min_hp then
      if S("BloodUseHeartStrike") and Spell.HeartStrike:CastEx(melee) then return true end
      if S("BloodUseBloodStrike") and Spell.BloodStrike:CastEx(melee) then return true end
    end
  end

  -- 8. Death Strike — fallback even at high HP to avoid sitting on runes forever
  if S("BloodUseDeathStrike") and melee then
    if Spell.DeathStrike:CastEx(melee) then return true end
  end

  -- 9. Blood rune fallback — at low HP, if DS can't fire (Frost/Unholy runes
  --    on CD), use Heart Strike / Blood Strike anyway.  Blood runes don't feed
  --    DS (it uses Frost+Unholy), so sitting on them wastes damage and threat.
  if melee and hp < hs_min_hp then
    if S("BloodUseHeartStrike") and Spell.HeartStrike:CastEx(melee) then return true end
    if S("BloodUseBloodStrike") and Spell.BloodStrike:CastEx(melee) then return true end
  end

  -- 10. Rune Strike — dump any remaining RP we couldn't spend earlier
  if melee and Me.Power >= 30 then
    if S("BloodUseRuneStrike") and Spell.RuneStrike:CastEx(melee) then return true end
    if S("BloodUseDeathCoil") and Spell.DeathCoil:CastEx(melee) then return true end
  end

  -- 11. Horn of Winter — filler (generates Runic Power)
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

  -- 2. Maintain diseases + spread via Pestilence
  if ApplyDiseases(enemies) then return true end

  -- 3. Blood Boil on Crimson Scourge proc (free, no rune cost)
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
  if Me.IsMounted then return end
  if Me:IsIncapacitated() then return end

  -- Restore facing from a previous auto-face cast
  UpdateFaceRestore()

  -- Out of combat maintenance
  if not Me.InCombat then
    if was_in_combat then
      was_in_combat = false
      opener_done = false
      combat_enter_time = 0
      if TTD then TTD.Reset() end
    end

    -- Bone Shield out of combat (30s+ before pull per guide).
    -- Refresh when missing OR at low stacks (<=2) to avoid entering a pull weak.
    if PallasSettings.BloodMaintainBoneShieldOOC and S("BloodUseBoneShield") then
      local bs = Me:GetAura("Bone Shield")
      local needs_refresh = not bs or (bs.stacks and bs.stacks <= 2)
      if needs_refresh then
        if not Me.IsCasting and not Me.IsChanneling then
          if Me.Target and not Me.Target.IsDead then
            CastNoTarget(Spell.BoneShield)
          end
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

  local enemies = GetCombatEnemies()

  -- Defensives (highest combat priority, needs enemies for smart AMS)
  if UseDefensives(enemies) then return end

  if #enemies == 0 then return end

  -- Auto face nearest target so subsequent casts pass facing checks
  AutoFaceTarget(enemies)

  -- Interrupts
  if TryInterrupt(enemies) then return end

  -- Threat management: taunt/grip loose mobs before they kill DPS
  if TryTauntLoose(enemies) then return end

  -- Snap threat: when taunt/grip are on CD, use damage abilities on loose mobs
  if TrySnapThreat(enemies) then return end

  -- Smart Soul Reaper: cast on any dying mob for the 50% haste buff
  if TrySmartSoulReaper(enemies) then return end

  -- Bone Shield maintenance — refresh when missing or at low stacks (<=2)
  -- to maintain the damage reduction buffer proactively
  if S("BloodUseBoneShield") then
    local bs = Me:GetAura("Bone Shield")
    if not bs or (bs.stacks and bs.stacks <= 2) then
      if CastNoTarget(Spell.BoneShield) then return end
    end
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
