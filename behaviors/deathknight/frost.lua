-- ═══════════════════════════════════════════════════════════════════
-- Frost Death Knight behavior (MoP 5.5.3)
--
-- Supports both Two-Hand and Dual-Wield (Masterfrost) play styles.
-- The key difference: Killing Machine procs are consumed by Obliterate
-- (2H) or Frost Strike (DW).  Auto-detect from settings or manual
-- selection.
--
-- Two-Hand Single-Target Priority:
--   1. Maintain diseases (Outbreak > PS/IT fallback)
--   2. Soul Reaper (<35%)
--   3. Howling Blast (Rime proc)
--   4. Obliterate (Killing Machine proc)
--   5. Frost Strike (RP overcap > 76)
--   6. Obliterate (rune pair capping — 2+ of any rune type)
--   7. Blood Tap / Plague Leech (rune regen)
--   8. Frost Strike (Runic Empowerment — no Frost rune ready)
--   9. Obliterate (filler)
--  10. Frost Strike (RP ≥ 40)
--  11. Horn of Winter (filler)
--  12. Empower Rune Weapon (emergency)
--
-- Dual-Wield Single-Target Priority:
--   1. Maintain diseases
--   2. Soul Reaper (<35%)
--   3. Frost Strike (Killing Machine proc, or RP ≥ 88)
--   4. Howling Blast (Rime proc)
--   5. Frost Strike (RP overcap > 76)
--   6. Obliterate (2+ Unholy runes)
--   7. Howling Blast (2+ Frost/Death runes)
--   8. Blood Tap / Plague Leech (rune regen)
--   9. Obliterate (Unholy rune filler)
--  10. Howling Blast (filler)
--  11. Frost Strike (RP ≥ 40)
--  12. Horn of Winter (filler)
--  13. Empower Rune Weapon (emergency)
--
-- AoE Priority (both styles):
--   1. Death and Decay
--   2. Diseases + Pestilence spread
--   3. Howling Blast (Rime proc)
--   4. Howling Blast (rune spender)
--   5. Frost Strike (RP cap)
--   6. Obliterate (Unholy rune spender)
--   7. Frost Strike (RP dump)
--   8. Horn of Winter (filler)
--
-- Cooldowns: Pillar of Frost, Raise Dead, ERW
-- Defensives: Icebound Fortitude, Anti-Magic Shell, Death Pact
-- ═══════════════════════════════════════════════════════════════════

-- ── Menu helper ──────────────────────────────────────────────────

local function S(uid)
  return PallasSettings[uid] ~= false
end

-- ── Menu options ────────────────────────────────────────────────

local options = {
  Name = "Death Knight (Frost)",
  Widgets = {
    { type = "text",     text = "=== Play Style ===" },
    { type = "combobox", uid = "FrostStyle",
      text = "Frost style (KM proc target)", default = 0,
      options = { "Two-Hand (Obliterate)", "Dual-Wield (Frost Strike)" } },

    { type = "text",     text = "=== Rotation Spells ===" },
    { type = "checkbox", uid = "FrostUseOutbreak",
      text = "Outbreak",                   default = true },
    { type = "checkbox", uid = "FrostUseIcyTouch",
      text = "Icy Touch",                 default = true },
    { type = "checkbox", uid = "FrostUsePlagueStrike",
      text = "Plague Strike",              default = true },
    { type = "checkbox", uid = "FrostUseObliterate",
      text = "Obliterate",                 default = true },
    { type = "checkbox", uid = "FrostUseHowlingBlast",
      text = "Howling Blast",              default = true },
    { type = "checkbox", uid = "FrostUseFrostStrike",
      text = "Frost Strike",               default = true },
    { type = "checkbox", uid = "FrostUseSoulReaper",
      text = "Soul Reaper",                default = true },
    { type = "slider",   uid = "FrostSoulReaperThreshold",
      text = "Soul Reaper HP %",           default = 35, min = 10, max = 50 },
    { type = "checkbox", uid = "FrostUseDnD",
      text = "Death and Decay",            default = true },
    { type = "checkbox", uid = "FrostUseBloodBoil",
      text = "Blood Boil (AoE)",           default = true },
    { type = "checkbox", uid = "FrostUsePestilence",
      text = "Pestilence (disease spread)", default = true },
    { type = "checkbox", uid = "FrostUseHoWFiller",
      text = "Horn of Winter (filler)",    default = true },

    { type = "text",     text = "=== Rune Regeneration ===" },
    { type = "checkbox", uid = "FrostUseBloodTap",
      text = "Blood Tap",                  default = true },
    { type = "slider",   uid = "FrostBloodTapOvercap",
      text = "Blood Tap at N+ charges",    default = 10, min = 5, max = 12 },
    { type = "checkbox", uid = "FrostUsePlagueLeech",
      text = "Plague Leech",               default = true },

    { type = "text",     text = "=== Cooldowns ===" },
    { type = "checkbox", uid = "FrostUsePillar",
      text = "Pillar of Frost",            default = true },
    { type = "checkbox", uid = "FrostUseRaiseDead",
      text = "Raise Dead (DPS cooldown)",  default = true },
    { type = "checkbox", uid = "FrostUseERW",
      text = "Empower Rune Weapon",        default = true },

    { type = "text",     text = "=== Defensives ===" },
    { type = "checkbox", uid = "FrostUseIBF",
      text = "Icebound Fortitude",         default = true },
    { type = "slider",   uid = "FrostIBFThreshold",
      text = "IBF HP %",                   default = 35, min = 15, max = 60 },
    { type = "checkbox", uid = "FrostUseAMS",
      text = "Anti-Magic Shell",           default = false },
    { type = "checkbox", uid = "FrostSmartAMS",
      text = "Smart AMS (react to incoming magic casts)",
      default = true },
    { type = "slider",   uid = "FrostAMSReactTime",
      text = "AMS react time (sec remaining)", default = 1.5, min = 0.1, max = 3.0, step = 0.1 },
    { type = "checkbox", uid = "FrostUseDeathPact",
      text = "Death Pact (sacrifice ghoul)", default = false },
    { type = "slider",   uid = "FrostDeathPactThreshold",
      text = "Death Pact HP %",            default = 25, min = 10, max = 50 },

    { type = "text",     text = "=== Interrupts ===" },
    { type = "checkbox", uid = "FrostUseInterrupt",
      text = "Mind Freeze",                default = true },
    { type = "combobox", uid = "FrostInterruptMode",
      text = "Interrupt mode",             default = 0,
      options = { "Any interruptible", "Whitelist only" } },

    { type = "text",     text = "=== Utility ===" },
    { type = "checkbox", uid = "FrostMaintainPresence",
      text = "Auto Frost Presence",        default = true },
    { type = "checkbox", uid = "FrostMaintainHoW",
      text = "Maintain Horn of Winter",    default = true },
    { type = "checkbox", uid = "FrostAutoFace",
      text = "Auto face target for casts", default = false },

    { type = "text",     text = "=== AoE ===" },
    { type = "checkbox", uid = "FrostAoeEnabled",
      text = "Use AoE rotation",           default = true },
    { type = "slider",   uid = "FrostAoeThreshold",
      text = "AoE enemy count",            default = 3, min = 2, max = 8 },

    { type = "text",     text = "=== Runic Power ===" },
    { type = "slider",   uid = "FrostRPOvercap",
      text = "RP overcap prevention at",   default = 76, min = 60, max = 120 },
    { type = "slider",   uid = "FrostFSThreshold",
      text = "Frost Strike RP dump above", default = 40, min = 20, max = 80 },

    { type = "text",     text = "=== Advanced ===" },
    { type = "slider",   uid = "FrostDiseaseRefreshSec",
      text = "Disease refresh timer (sec)", default = 4, min = 2, max = 10 },
  },
}

-- ── Constants ──────────────────────────────────────────────────

local AOE_RANGE = 10
local INTERRUPT_WHITELIST = {}
local SCHOOL_PHYSICAL = 1

-- ── Self-buff cast helper ────────────────────────────────────────

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

-- ── Targeting ──────────────────────────────────────────────────

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
  local my_cr = Me.CombatReach or 0
  local best = nil
  for _, entry in ipairs(enemies) do
    if entry.dist_sq > 225 then break end
    local their_cr = entry.unit.CombatReach or 0
    local range = my_cr + their_cr + MELEE_LEEWAY
    if range < MELEE_MIN then range = MELEE_MIN end
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

-- ── Play style helper ──────────────────────────────────────────

local function is_dual_wield()
  return (PallasSettings.FrostStyle or 0) == 1
end

-- ── Interrupt ─────────────────────────────────────────────────

local mf_range_sq = nil

local function TryInterrupt(enemies)
  if not PallasSettings.FrostUseInterrupt then return false end
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

  local wl_mode = (PallasSettings.FrostInterruptMode or 0) == 1
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

local function ApplyDiseases(enemies)
  local melee = MeleeTarget(enemies)
  local ranged = RangedTarget(enemies)
  local target = melee or ranged
  if not target then return false end

  local refresh_sec = PallasSettings.FrostDiseaseRefreshSec or 4
  local ff_aura = target:GetAura("Frost Fever")
  local bp_aura = target:GetAura("Blood Plague")
  local has_ff  = ff_aura ~= nil
  local has_bp  = bp_aura ~= nil
  local ff_low  = not has_ff or (ff_aura.remaining or 0) < refresh_sec
  local bp_low  = not has_bp or (bp_aura.remaining or 0) < refresh_sec
  local needs_refresh = ff_low or bp_low

  if needs_refresh then
    -- Outbreak is always preferred (instant, no rune cost)
    if S("FrostUseOutbreak") and ranged then
      if Spell.Outbreak:CastEx(ranged) then return true end
    end

    -- Howling Blast applies Frost Fever (and is instant) — prefer over Icy Touch
    if ff_low and S("FrostUseHowlingBlast") and ranged then
      if Spell.HowlingBlast:CastEx(ranged) then return true end
    end

    -- Icy Touch fallback for Frost Fever
    if ff_low and S("FrostUseIcyTouch") and ranged then
      if Spell.IcyTouch:CastEx(ranged) then return true end
    end

    -- Plague Strike for Blood Plague
    if bp_low and S("FrostUsePlagueStrike") and melee then
      if Spell.PlagueStrike:CastEx(melee) then return true end
    end
  end

  -- Spread: Pestilence when our target has diseases but nearby enemies don't
  if S("FrostUsePestilence") and melee and has_ff and has_bp then
    if enemies_need_spread(enemies, 15) then
      if Spell.Pestilence:CastEx(melee) then return true end
    end
  end

  return false
end

-- ── Rune Regeneration ──────────────────────────────────────────

local function HandleBloodTap()
  if not S("FrostUseBloodTap") then return false end
  if not Spell.BloodTap.IsKnown then return false end

  local charges = Me:GetAura("Blood Charge")
  local stacks = charges and charges.stacks or 0
  local overcap_at = PallasSettings.FrostBloodTapOvercap or 10

  if stacks >= overcap_at then
    if CastNoTarget(Spell.BloodTap) then return true end
  elseif stacks >= 5 then
    local rs = Rune and Rune.GetState() or nil
    local starved = rs
        and (not Rune.CanObliterate(rs) and not Rune.CanHowlingBlast(rs))
        or (not Spell.Obliterate:IsUsable() and not Spell.HowlingBlast:IsUsable())
    if starved then
      if CastNoTarget(Spell.BloodTap) then return true end
    end
  end
  return false
end

local function HandlePlagueLeech(target)
  if not S("FrostUsePlagueLeech") then return false end
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

local function ShouldUseSmartAMS(enemies)
  if not Spell.AntimagicShell.IsKnown then return false end
  if not Spell.AntimagicShell:IsReady() then return false end
  if Me:HasAura("Anti-Magic Shell") then return false end

  local react = PallasSettings.FrostAMSReactTime or 1.5
  local my_guid = Me.Guid
  local my_lo, my_hi = Me.guid_lo, Me.guid_hi
  local now_gt = nil

  for _, entry in ipairs(enemies) do
    local u = entry.unit
    if not u.IsCasting and not u.IsChanneling then goto next_ams end

    local spell_id = u.IsCasting and u.CastingSpellId or u.ChannelingSpellId
    if not spell_id or spell_id == 0 then goto next_ams end

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

    local sok, school = pcall(game.get_spell_school, spell_id)
    if sok and school == SCHOOL_PHYSICAL then goto next_ams end

    local remaining = 999
    if Me.Target and not Me.Target.IsDead and Me.Target.Guid == u.Guid then
      local ok, cast = pcall(game.unit_casting_info, "target")
      if ok and cast then
        remaining = cast.remaining or 999
      else
        local ok2, chan = pcall(game.unit_channel_info, "target")
        if ok2 and chan then remaining = chan.remaining or 999 end
      end
    end

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

  if PallasSettings.FrostUseIBF and hp < (PallasSettings.FrostIBFThreshold or 35) then
    if CastNoTarget(Spell.IceboundFortitude) then return true end
  end

  if S("FrostSmartAMS") and enemies and ShouldUseSmartAMS(enemies) then
    if CastNoTarget(Spell.AntimagicShell) then return true end
  end

  if PallasSettings.FrostUseAMS and not S("FrostSmartAMS") then
    if CastNoTarget(Spell.AntimagicShell) then return true end
  end

  if PallasSettings.FrostUseDeathPact and hp < (PallasSettings.FrostDeathPactThreshold or 25) then
    if not Pet.HasPet() then
      if CastNoTarget(Spell.RaiseDead) then return true end
    else
      if CastNoTarget(Spell.DeathPact) then return true end
    end
  end

  return false
end

-- ── Auto Facing ──────────────────────────────────────────────────

local pending_face_restore = nil
local face_restore_at = 0

local function AutoFaceTarget(enemies)
  if not PallasSettings.FrostAutoFace then return end
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

-- ── Cooldown helpers ────────────────────────────────────────────

local function cd_remaining(spell)
  if not spell.IsKnown then return -1 end
  local cd = spell:GetCooldown()
  if cd and cd.on_cooldown and (cd.duration or 0) > 2 then
    return math.ceil(cd.remaining or 0)
  end
  return 0
end

-- ── Smart Soul Reaper (haste proc on dying mobs) ────────────────
local SOUL_REAPER_HASTE = 114868

local function TrySmartSoulReaper(enemies)
  if not S("FrostUseSoulReaper") then return false end
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

-- ── Cooldowns ────────────────────────────────────────────────────

local function UseCooldowns(enemies)
  local primary = MeleeTarget(enemies) or RangedTarget(enemies)
  local target_ttd = (TTD and primary) and TTD.Get(primary) or 999

  -- Pillar of Frost (1-min CD, 20% Strength for 20s)
  -- Use on CD but don't waste on a dying target.
  if S("FrostUsePillar") and target_ttd > 10 then
    if CastNoTarget(Spell.PillarOfFrost) then return true end
  end

  -- Raise Dead (DPS ghoul)
  if S("FrostUseRaiseDead") and not Pet.HasPetOfFamily(Pet.FAMILY_GHOUL) then
    if CastNoTarget(Spell.RaiseDead) then return true end
  end

  -- Empower Rune Weapon: only when truly rune-starved AND low RP.
  -- 5-min CD — never waste on a target dying in < 15s.
  if S("FrostUseERW") and target_ttd > 15 then
    local rs = Rune and Rune.GetState() or nil
    local fully_depleted = false
    if rs then
      fully_depleted = Rune.IsFullyDepleted(rs)
    else
      fully_depleted = not Spell.Obliterate:IsUsable()
          and not Spell.HowlingBlast:IsUsable()
    end
    if fully_depleted and Me.Power < 40 then
      if CastNoTarget(Spell.EmpowerRuneWeapon) then return true end
    end
  end

  return false
end

-- ── RP Spending ──────────────────────────────────────────────────

local function SpendFrostStrike(enemies, threshold)
  if not S("FrostUseFrostStrike") then return false end
  if Me.Power < threshold then return false end
  local melee = MeleeTarget(enemies)
  if melee and Spell.FrostStrike:CastEx(melee) then return true end
  return false
end

-- ── Two-Hand Single-Target ──────────────────────────────────────

local function SingleTarget2H(enemies)
  local melee  = MeleeTarget(enemies)
  local ranged = RangedTarget(enemies)
  local target = melee or ranged
  if not target then return false end

  local rs = Rune and Rune.GetState() or nil
  local rp_cap = PallasSettings.FrostRPOvercap or 76
  local rp_dump = PallasSettings.FrostFSThreshold or 40
  local has_km = Me:HasAura("Killing Machine")
  local has_rime = Me:HasAura("Rime") or Me:HasAura("Freezing Fog")

  -- 1. Diseases
  if ApplyDiseases(enemies) then return true end

  -- 2. Soul Reaper (execute range)
  if S("FrostUseSoulReaper") and melee and melee.HealthPct > 0 then
    local sr_thresh = PallasSettings.FrostSoulReaperThreshold or 35
    if melee.HealthPct < sr_thresh + 5 then
      if Spell.SoulReaper:CastEx(melee) then return true end
    end
  end

  -- 3. Howling Blast with Rime proc (free, instant — always use)
  if has_rime and S("FrostUseHowlingBlast") and ranged then
    if Spell.HowlingBlast:CastEx(ranged) then return true end
  end

  -- 4. Obliterate with Killing Machine (2H: KM always into Oblit)
  if has_km and S("FrostUseObliterate") and melee then
    if Spell.Obliterate:CastEx(melee) then return true end
  end

  -- 5. Frost Strike — RP overcap prevention
  if SpendFrostStrike(enemies, rp_cap) then return true end

  -- 6. Obliterate — rune pair capping (2+ of any rune type ready)
  if S("FrostUseObliterate") and melee then
    if rs and Rune.HasRunePairReady(rs) then
      if Spell.Obliterate:CastEx(melee) then return true end
    end
  end

  -- 7. Blood Tap / Plague Leech
  if HandleBloodTap() then return true end
  if HandlePlagueLeech(melee or ranged) then return true end

  -- 8. Frost Strike — Runic Empowerment: spend RP when no Frost rune
  --    to proc rune regeneration via Runic Empowerment talent.
  if rs and rs.frost_ready == 0 then
    if SpendFrostStrike(enemies, rp_dump) then return true end
  elseif not rs and not Spell.HowlingBlast:IsUsable() then
    if SpendFrostStrike(enemies, rp_dump) then return true end
  end

  -- 9. Obliterate — filler (use runes, don't sit on them)
  if S("FrostUseObliterate") and melee then
    if Spell.Obliterate:CastEx(melee) then return true end
  end

  -- 10. Frost Strike — dump remaining RP
  if SpendFrostStrike(enemies, rp_dump) then return true end

  -- 11. Horn of Winter — filler
  if S("FrostUseHoWFiller") and CastNoTarget(Spell.HornOfWinter) then return true end

  return false
end

-- ── Dual-Wield Single-Target (Masterfrost) ──────────────────────

local function SingleTargetDW(enemies)
  local melee  = MeleeTarget(enemies)
  local ranged = RangedTarget(enemies)
  local target = melee or ranged
  if not target then return false end

  local rs = Rune and Rune.GetState() or nil
  local rp_cap = PallasSettings.FrostRPOvercap or 76
  local rp_dump = PallasSettings.FrostFSThreshold or 40
  local has_km = Me:HasAura("Killing Machine")
  local has_rime = Me:HasAura("Rime") or Me:HasAura("Freezing Fog")

  -- 1. Diseases
  if ApplyDiseases(enemies) then return true end

  -- 2. Soul Reaper (execute range)
  if S("FrostUseSoulReaper") and melee and melee.HealthPct > 0 then
    local sr_thresh = PallasSettings.FrostSoulReaperThreshold or 35
    if melee.HealthPct < sr_thresh + 5 then
      if Spell.SoulReaper:CastEx(melee) then return true end
    end
  end

  -- 3. Frost Strike with Killing Machine (DW: KM into FS)
  --    Also fire FS at very high RP (>= 88) with KM for maximum damage.
  if has_km and S("FrostUseFrostStrike") and melee then
    if Spell.FrostStrike:CastEx(melee) then return true end
  end
  if Me.Power >= 88 and S("FrostUseFrostStrike") and melee then
    if Spell.FrostStrike:CastEx(melee) then return true end
  end

  -- 4. Howling Blast with Rime proc
  if has_rime and S("FrostUseHowlingBlast") and ranged then
    if Spell.HowlingBlast:CastEx(ranged) then return true end
  end

  -- 5. Frost Strike — RP overcap prevention
  if SpendFrostStrike(enemies, rp_cap) then return true end

  -- 6. Obliterate when 2+ Unholy runes ready (spend them)
  if S("FrostUseObliterate") and melee then
    local unholy_pool = rs and Rune.ReadyAs(rs, Rune.UNHOLY) or 0
    if unholy_pool >= 2 then
      if Spell.Obliterate:CastEx(melee) then return true end
    end
  end

  -- 7. Howling Blast when 2+ Frost/Death runes ready
  if S("FrostUseHowlingBlast") and ranged then
    local frost_pool = rs and Rune.ReadyAs(rs, Rune.FROST) or 0
    if frost_pool >= 2 then
      if Spell.HowlingBlast:CastEx(ranged) then return true end
    end
  end

  -- 8. Blood Tap / Plague Leech
  if HandleBloodTap() then return true end
  if HandlePlagueLeech(melee or ranged) then return true end

  -- 9. Obliterate — spend Unholy runes
  if S("FrostUseObliterate") and melee then
    local unholy_pool = rs and Rune.ReadyAs(rs, Rune.UNHOLY) or 0
    if unholy_pool >= 1 then
      if Spell.Obliterate:CastEx(melee) then return true end
    end
  end

  -- 10. Howling Blast — spend Frost/Death runes
  if S("FrostUseHowlingBlast") and ranged then
    if Spell.HowlingBlast:CastEx(ranged) then return true end
  end

  -- 11. Frost Strike (Runic Empowerment / Runic Corruption RP dump)
  --     When no Frost rune is ready, spend RP to proc RE.
  if rs and (rs.frost_ready == 0 or rs.blood_ready == 0) then
    if SpendFrostStrike(enemies, rp_dump) then return true end
  elseif not rs then
    if SpendFrostStrike(enemies, rp_dump) then return true end
  end

  -- 12. Frost Strike — dump remaining RP
  if SpendFrostStrike(enemies, rp_dump) then return true end

  -- 13. Horn of Winter — filler
  if S("FrostUseHoWFiller") and CastNoTarget(Spell.HornOfWinter) then return true end

  return false
end

-- ── Single-Target dispatch ──────────────────────────────────────

local function SingleTarget(enemies)
  if is_dual_wield() then
    return SingleTargetDW(enemies)
  else
    return SingleTarget2H(enemies)
  end
end

-- ── AoE Priority ──────────────────────────────────────────────

local function AoERotation(enemies)
  local melee   = MeleeTarget(enemies)
  local aoe_tgt = AoeTarget(enemies)
  local ranged  = RangedTarget(enemies)

  local rp_cap = PallasSettings.FrostRPOvercap or 76
  local rp_dump = PallasSettings.FrostFSThreshold or 40
  local has_rime = Me:HasAura("Rime") or Me:HasAura("Freezing Fog")

  -- 1. Death and Decay (highest AoE priority)
  if S("FrostUseDnD") and melee and Spell.DeathAndDecay:CastAtPos(melee) then return true end

  -- 2. Diseases + Pestilence spread
  if ApplyDiseases(enemies) then return true end

  -- 3. Howling Blast (Rime proc — free)
  if has_rime and S("FrostUseHowlingBlast") and ranged then
    if Spell.HowlingBlast:CastEx(ranged) then return true end
  end

  -- 4. Howling Blast (rune spender — primary AoE damage)
  if S("FrostUseHowlingBlast") and ranged then
    if Spell.HowlingBlast:CastEx(ranged) then return true end
  end

  -- 5. Frost Strike — RP cap prevention
  if SpendFrostStrike(enemies, rp_cap) then return true end

  -- 6. Obliterate (spend Unholy runes so they don't cap)
  if S("FrostUseObliterate") and melee then
    if Spell.Obliterate:CastEx(melee) then return true end
  end

  -- 7. Frost Strike — RP dump
  if SpendFrostStrike(enemies, rp_dump) then return true end

  -- 8. Blood Tap
  if HandleBloodTap() then return true end

  -- 9. Horn of Winter — filler
  if S("FrostUseHoWFiller") and CastNoTarget(Spell.HornOfWinter) then return true end

  return false
end

-- ── Cooldown HUD (ImGui) ─────────────────────────────────────────

local WF_HUD    = 1 + 64 + 4096 + 8192  -- NoTitleBar + AutoResize + NoFocusOnAppear + NoBringToFront
local COND_FIRST = 4

local function draw_frost_hud()
  if not Me or not Me.InCombat then return end

  imgui.set_next_window_pos(450, 10, COND_FIRST)
  imgui.set_next_window_bg_alpha(0.8)
  local visible = imgui.begin_window("##FrostDKHUD", WF_HUD)
  if visible then
    local pillar_rem = cd_remaining(Spell.PillarOfFrost)
    local erw_rem    = cd_remaining(Spell.EmpowerRuneWeapon)

    local style_str = is_dual_wield() and "DW" or "2H"
    local km = Me:HasAura("Killing Machine")
    local rime = Me:HasAura("Rime") or Me:HasAura("Freezing Fog")

    local line1 = string.format("[%s] Pillar: %ds | ERW: %ds",
        style_str,
        pillar_rem >= 0 and pillar_rem or 0,
        erw_rem >= 0 and erw_rem or 0)

    if Me:HasAura("Pillar of Frost") then
      imgui.text_colored(0.4, 0.8, 1, 1, "PILLAR ACTIVE")
    elseif pillar_rem == 0 then
      imgui.text_colored(0.2, 1, 0.2, 1, "Pillar: READY")
    else
      imgui.text_colored(0.7, 0.7, 0.7, 1, line1)
    end

    local procs = ""
    if km then procs = procs .. " [KM]" end
    if rime then procs = procs .. " [Rime]" end
    if procs ~= "" then
      imgui.text_colored(1, 0.8, 0, 1, "Procs:" .. procs)
    end

    -- Rune state summary
    local rs = Rune and Rune.GetState() or nil
    if rs then
      imgui.text_colored(0.6, 0.6, 0.6, 1,
          string.format("Runes: %dB %dF %dU %dD  RP: %d",
              rs.blood_ready, rs.frost_ready, rs.unholy_ready,
              rs.death_ready, Me.Power or 0))
    end
  end
  imgui.end_window()
end

Pallas._behavior_draw = draw_frost_hud

-- ── Main Combat Function ──────────────────────────────────────

local was_in_combat = false

local function FrostDKCombat()
  if Me.IsMounted then return end
  if Me:IsIncapacitated() then return end

  UpdateFaceRestore()

  -- Out of combat
  if not Me.InCombat then
    if was_in_combat then
      was_in_combat = false
      if TTD then TTD.Reset() end
    end
    return
  end

  if not was_in_combat then
    was_in_combat = true
  end

  if Me.IsCasting or Me.IsChanneling then return end
  if Spell:IsGCDActive() then return end

  -- Self-buffs
  if PallasSettings.FrostMaintainPresence and not Me:HasAura("Frost Presence") then
    if CastNoTarget(Spell.FrostPresence) then return end
  end

  if PallasSettings.FrostMaintainHoW and not Me:HasAura("Horn of Winter") then
    if CastNoTarget(Spell.HornOfWinter) then return end
  end

  local enemies = GetCombatEnemies()

  -- Defensives (needs enemies for smart AMS)
  if UseDefensives(enemies) then return end

  if #enemies == 0 then return end

  AutoFaceTarget(enemies)

  -- Interrupts
  if TryInterrupt(enemies) then return end

  -- Smart Soul Reaper: cast on any dying mob for the 50% haste buff
  if TrySmartSoulReaper(enemies) then return end

  -- Cooldowns (Pillar of Frost, Raise Dead, ERW)
  if UseCooldowns(enemies) then return end

  -- AoE vs ST
  local use_aoe = false
  if PallasSettings.FrostAoeEnabled then
    local nearby = EnemiesInRange(enemies, AOE_RANGE)
    use_aoe = nearby >= (PallasSettings.FrostAoeThreshold or 3)
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
  [BehaviorType.Combat] = FrostDKCombat,
}

return { Options = options, Behaviors = behaviors }
