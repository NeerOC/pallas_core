-- ═══════════════════════════════════════════════════════════════════
-- Blood Death Knight behavior (MoP 5.5.3)
--
-- Works at any level: falls through unknown spells to baseline
-- abilities (Icy Touch, Plague Strike, Blood Strike, Death Coil).
--
-- Endgame Single-Target Priority:
--   1. Blood Presence (maintain)
--   2. Horn of Winter (maintain buff)
--   3. Diseases (Outbreak → Icy Touch + Plague Strike fallback)
--   4. Dancing Rune Weapon on CD
--   5. Bone Shield (maintain)
--   6. Crimson Scourge proc → Blood Boil / Death and Decay
--   7. Death Strike (primary heal/shield)
--   8. Soul Reaper (<35%) / Heart Strike / Blood Strike (Blood rune)
--   9. Death and Decay on CD
--  10. Rune Strike / Death Coil (Runic Power dump)
--  11. Empower Rune Weapon (rune starved)
--  12. Horn of Winter / Icy Touch (filler)
--
-- AoE (3+ enemies):
--   Death and Decay > diseases > Pestilence (spread) >
--   Blood Boil (replaces Heart/Blood Strike) > Death Strike >
--   Rune Strike / Death Coil > Horn of Winter
--
-- Defensives: Vampiric Blood, Icebound Fortitude, Anti-Magic Shell,
--   Rune Tap, Death Pact
-- ═══════════════════════════════════════════════════════════════════

-- ── Menu options ────────────────────────────────────────────────

local options = {
  Name = "Death Knight (Blood)",
  Widgets = {
    { type = "text",     text = "=== Cooldowns ===" },
    { type = "checkbox", uid = "BloodUseDRW",
      text = "Use Dancing Rune Weapon",  default = true },
    { type = "checkbox", uid = "BloodUseERW",
      text = "Use Empower Rune Weapon (no runes)", default = true },

    { type = "text",     text = "=== Defensives ===" },
    { type = "checkbox", uid = "BloodUseVampiricBlood",
      text = "Use Vampiric Blood",       default = true },
    { type = "slider",   uid = "BloodVBThreshold",
      text = "Vampiric Blood HP %",      default = 50, min = 20, max = 80 },
    { type = "checkbox", uid = "BloodUseIBF",
      text = "Use Icebound Fortitude",   default = true },
    { type = "slider",   uid = "BloodIBFThreshold",
      text = "IBF HP %",                 default = 35, min = 15, max = 60 },
    { type = "checkbox", uid = "BloodUseAMS",
      text = "Use Anti-Magic Shell",     default = false },
    { type = "checkbox", uid = "BloodUseRuneTap",
      text = "Use Rune Tap",             default = true },
    { type = "slider",   uid = "BloodRuneTapThreshold",
      text = "Rune Tap HP %",            default = 60, min = 20, max = 80 },
    { type = "checkbox", uid = "BloodUseDeathPact",
      text = "Use Death Pact (sacrifice ghoul)", default = false },
    { type = "slider",   uid = "BloodDeathPactThreshold",
      text = "Death Pact HP %",          default = 25, min = 10, max = 50 },

    { type = "text",     text = "=== Interrupts ===" },
    { type = "checkbox", uid = "BloodUseInterrupt",
      text = "Use Mind Freeze",             default = true },
    { type = "combobox", uid = "BloodInterruptMode",
      text = "Interrupt mode",              default = 0,
      options = { "Any interruptible", "Whitelist only" } },

    { type = "text",     text = "=== Utility ===" },
    { type = "checkbox", uid = "BloodMaintainHoW",
      text = "Maintain Horn of Winter",  default = true },
    { type = "checkbox", uid = "BloodMaintainPresence",
      text = "Auto Blood Presence",      default = true },

    { type = "text",     text = "=== AoE ===" },
    { type = "checkbox", uid = "BloodAoeEnabled",
      text = "Use AoE rotation (3+ enemies)", default = true },
    { type = "slider",   uid = "BloodAoeThreshold",
      text = "AoE enemy count",          default = 3, min = 2, max = 8 },

    { type = "text",     text = "=== Runic Power ===" },
    { type = "slider",   uid = "BloodRSThreshold",
      text = "Rune Strike above RP",     default = 80, min = 30, max = 110 },
  },
}

-- ── Constants ──────────────────────────────────────────────────

local AOE_RANGE = 10
-- Spell IDs to interrupt in "Whitelist only" mode.
-- Empty = interrupt everything interruptible.  Add IDs to restrict, e.g.:
--   local INTERRUPT_WHITELIST = { 12345, 67890 }
local INTERRUPT_WHITELIST = {}

-- ── Tank Targeting (priority-based, no player target required) ─

--- Collect all valid in-combat enemies from the entity cache.
--- Returns a list of Unit wrappers sorted by distance (nearest first).
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

    if e.position then
      local dx = mx - e.position.x
      local dy = my - e.position.y
      local dz = mz - e.position.z
      local dist_sq = dx * dx + dy * dy + dz * dz
      if dist_sq <= 1600 then -- 40yd max
        local u = Unit:New(e)
        if Me:CanAttack(u) then
          results[#results + 1] = { unit = u, dist_sq = dist_sq }
        end
      end
    end
    ::skip::
  end

  table.sort(results, function(a, b) return a.dist_sq < b.dist_sq end)
  return results
end

--- Get the best target within a given yard range.
--- Prefers the player's current target if valid and in range, otherwise nearest.
local function GetTargetInRange(enemies, range_yd)
  local range_sq = range_yd * range_yd
  local tgt_guid = Me.Target and not Me.Target.IsDead and Me.Target.Guid or nil

  local best = nil
  for _, entry in ipairs(enemies) do
    if entry.dist_sq > range_sq then break end -- sorted by distance
    if tgt_guid and entry.unit.Guid == tgt_guid then return entry.unit end
    if not best then best = entry.unit end
  end
  return best
end

--- Shorthand accessors for common range tiers.
local function MeleeTarget(enemies)  return GetTargetInRange(enemies, 6)   end
local function AoeTarget(enemies)    return GetTargetInRange(enemies, 10)  end
local function RangedTarget(enemies) return GetTargetInRange(enemies, 30)  end
local function AnyTarget(enemies)    return GetTargetInRange(enemies, 40)  end

--- Count enemies within a given range of the player.
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

local mf_range_sq = nil -- cached Mind Freeze range², resolved once

--- Scan enemies for interruptible casts.  Uses cached spell range and
--- pre-computed distances — no game function calls in the hot loop except
--- one unit_casting_info for the current target.
local function TryInterrupt(enemies)
  if not PallasSettings.BloodUseInterrupt then return false end
  if not Spell.MindFreeze.IsKnown then return false end
  if not Spell.MindFreeze:IsReady() then return false end

  -- Resolve Mind Freeze range once via spell data
  if not mf_range_sq then
    local ok, info = pcall(game.get_spell_info, Spell.MindFreeze.Id)
    if ok and info then
      local r = (info.max_range or 0)
      if r < 1 then r = 5 end -- melee fallback
      mf_range_sq = r * r
    else
      mf_range_sq = 25 -- 5yd fallback
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

-- ── Helpers ────────────────────────────────────────────────────

local function has_diseases(target)
  return target:HasAura("Frost Fever") and target:HasAura("Blood Plague")
end

local function diseases_expiring(target)
  local ff = target:GetAura("Frost Fever")
  local bp = target:GetAura("Blood Plague")
  if not ff or not bp then return true end
  local ff_rem = ff.remaining or 0
  local bp_rem = bp.remaining or 0
  return ff_rem < 4 or bp_rem < 4
end

--- Apply diseases: Outbreak if known, otherwise Icy Touch + Plague Strike.
--- Picks the right target per ability range.
local function ApplyDiseases(enemies)
  local melee = MeleeTarget(enemies)
  local ranged = RangedTarget(enemies)
  local target = melee or ranged
  if not target then return false end
  if has_diseases(target) then return false end

  -- Outbreak (instant, 30yd, applies both)
  if ranged and not has_diseases(ranged) then
    if Spell.Outbreak:CastEx(ranged) then return true end
  end

  -- Icy Touch (30yd — Frost Fever)
  if ranged and not ranged:HasAura("Frost Fever") then
    if Spell.IcyTouch:CastEx(ranged) then return true end
  end

  -- Plague Strike (melee — Blood Plague)
  if melee and not melee:HasAura("Blood Plague") then
    if Spell.PlagueStrike:CastEx(melee) then return true end
  end

  return false
end

--- Spend Runic Power: Rune Strike (melee) if known, else Death Coil (ranged).
local function SpendRP(enemies)
  local threshold = PallasSettings.BloodRSThreshold or 80
  if Me.Power < threshold then return false end

  local melee = MeleeTarget(enemies)
  if melee and Spell.RuneStrike:CastEx(melee) then return true end
  local ranged = RangedTarget(enemies)
  if ranged and Spell.DeathCoil:CastEx(ranged) then return true end
  return false
end

-- ── Defensives ─────────────────────────────────────────────────

local function UseDefensives()
  local hp = Me.HealthPct

  if PallasSettings.BloodUseVampiricBlood and hp < (PallasSettings.BloodVBThreshold or 50) then
    if Spell.VampiricBlood:CastEx(Me) then return true end
  end

  if PallasSettings.BloodUseRuneTap and hp < (PallasSettings.BloodRuneTapThreshold or 60) then
    if Spell.RuneTap:CastEx(Me) then return true end
  end

  if PallasSettings.BloodUseIBF and hp < (PallasSettings.BloodIBFThreshold or 35) then
    if Spell.IceboundFortitude:CastEx(Me) then return true end
  end

  if PallasSettings.BloodUseAMS then
    if Spell.AntiMagicShell:CastEx(Me) then return true end
  end

  if PallasSettings.BloodUseDeathPact and hp < (PallasSettings.BloodDeathPactThreshold or 25) then
    if Spell.DeathPact:CastEx(Me) then return true end
  end

  return false
end

-- ── Single-Target Priority ────────────────────────────────────

local function SingleTarget(enemies)
  local melee  = MeleeTarget(enemies)
  local ranged = RangedTarget(enemies)

  -- 1. Diseases (range-aware: Outbreak/Icy Touch at 30yd, Plague Strike melee)
  if ApplyDiseases(enemies) then return true end

  -- 2. Dancing Rune Weapon on CD (self-cast)
  if PallasSettings.BloodUseDRW then
    if Spell.DancingRuneWeapon:CastEx(Me) then return true end
  end

  -- 3. Bone Shield (self-cast)
  if not Me:HasAura("Bone Shield") then
    if Spell.BoneShield:CastEx(Me) then return true end
  end

  -- 4. Crimson Scourge proc (Blood Boil 10yd / DnD at target)
  if Me:HasAura("Crimson Scourge") then
    local aoe_tgt = AoeTarget(enemies)
    if aoe_tgt and diseases_expiring(aoe_tgt) then
      if Spell.BloodBoil:CastEx(aoe_tgt) then return true end
    elseif melee then
      if Spell.DeathAndDecay:CastAtPos(melee) then return true end
    end
  end

  -- 5. Death Strike (melee — primary heal + Blood Shield)
  if melee and Spell.DeathStrike:CastEx(melee) then return true end

  -- 6. Soul Reaper (<35%), Heart Strike, Blood Strike (all melee)
  if melee then
    if melee.HealthPct and melee.HealthPct > 0 and melee.HealthPct < 35 then
      if Spell.SoulReaper:CastEx(melee) then return true end
    end
    if Spell.HeartStrike:CastEx(melee) then return true end
    if Spell.BloodStrike:CastEx(melee) then return true end
  end

  -- 7. Death and Decay (at nearest enemy)
  if melee and Spell.DeathAndDecay:CastAtPos(melee) then return true end

  -- 8. Blood Boil to refresh expiring diseases (10yd)
  local aoe_tgt = AoeTarget(enemies)
  if aoe_tgt and diseases_expiring(aoe_tgt) then
    if Spell.BloodBoil:CastEx(aoe_tgt) then return true end
  end

  -- 9. Runic Power dump (Rune Strike melee / Death Coil 30yd)
  if SpendRP(enemies) then return true end

  -- 10. Empower Rune Weapon (self-cast, rune + RP starved)
  if PallasSettings.BloodUseERW and Me.Power < 40 then
    if Spell.EmpowerRuneWeapon:CastEx(Me) then return true end
  end

  -- 11. Horn of Winter (self-cast filler)
  if Spell.HornOfWinter:CastEx(Me) then return true end

  -- 12. Ranged fillers on any valid target
  if ranged and Spell.IcyTouch:CastEx(ranged) then return true end
  if melee and Spell.PlagueStrike:CastEx(melee) then return true end

  return false
end

-- ── AoE Priority ──────────────────────────────────────────────

local function AoERotation(enemies)
  local melee   = MeleeTarget(enemies)
  local aoe_tgt = AoeTarget(enemies)
  local ranged  = RangedTarget(enemies)

  -- 1. Death and Decay (at melee clump)
  if melee and Spell.DeathAndDecay:CastAtPos(melee) then return true end

  -- 2. Diseases (range-aware)
  if ApplyDiseases(enemies) then return true end

  -- 3. Pestilence to spread diseases (melee)
  if melee and has_diseases(melee) then
    if Spell.Pestilence:CastEx(melee) then return true end
  end

  -- 4. Bone Shield (self-cast)
  if not Me:HasAura("Bone Shield") then
    if Spell.BoneShield:CastEx(Me) then return true end
  end

  -- 5. Crimson Scourge proc (Blood Boil 10yd)
  if Me:HasAura("Crimson Scourge") and aoe_tgt then
    if Spell.BloodBoil:CastEx(aoe_tgt) then return true end
  end

  -- 6. Blood Boil (10yd — replaces Heart/Blood Strike in AoE)
  if aoe_tgt and Spell.BloodBoil:CastEx(aoe_tgt) then return true end

  -- 7. Death Strike (melee — self-sustain)
  if melee and Spell.DeathStrike:CastEx(melee) then return true end

  -- 8. Blood Strike (melee fallback when Blood Boil not known)
  if melee and Spell.BloodStrike:CastEx(melee) then return true end

  -- 9. RP dump (melee Rune Strike / ranged Death Coil)
  if SpendRP(enemies) then return true end

  -- 10. Empower Rune Weapon (self-cast)
  if PallasSettings.BloodUseERW and Me.Power < 40 then
    if Spell.EmpowerRuneWeapon:CastEx(Me) then return true end
  end

  -- 11. Fillers
  if Spell.HornOfWinter:CastEx(Me) then return true end
  if ranged and Spell.IcyTouch:CastEx(ranged) then return true end
  if melee and Spell.PlagueStrike:CastEx(melee) then return true end

  return false
end

-- ── Main Combat Function ──────────────────────────────────────

local function BloodDKCombat()
  if not Me.InCombat then return end

  -- Self-buffs — no target needed but only in combat
  if PallasSettings.BloodMaintainPresence then
    if not Me:HasAura("Blood Presence") then
      if Spell.BloodPresence:CastEx(Me) then return end
    end
  end

  if PallasSettings.BloodMaintainHoW then
    if not Me:HasAura("Horn of Winter") then
      if Spell.HornOfWinter:CastEx(Me) then return end
    end
  end

  -- Defensives
  if UseDefensives() then return end

  -- Tank targeting: build sorted enemy list (nearest first)
  local enemies = GetCombatEnemies()
  if #enemies == 0 then return end

  -- Interrupts (highest priority after defensives)
  if TryInterrupt(enemies) then return end

  -- Determine AoE based on enemies within Blood Boil range (10yd)
  local use_aoe = false
  if PallasSettings.BloodAoeEnabled then
    local nearby = EnemiesInRange(enemies, AOE_RANGE)
    use_aoe = nearby >= (PallasSettings.BloodAoeThreshold or 3)
  end

  if use_aoe then
    AoERotation(enemies)
  else
    SingleTarget(enemies)
  end
end

-- ── Export ───────────────────────────────────────────────────

local behaviors = {
  [BehaviorType.Combat] = BloodDKCombat,
}

return { Options = options, Behaviors = behaviors }
