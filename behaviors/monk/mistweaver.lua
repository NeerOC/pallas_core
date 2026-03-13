local options = {
  Name = "Monk (Mistweaver)", -- shown as collapsing header

  Widgets = {
    { type = "text", text = "=== General ===" },
  },
}

local function DoCombat()
  local target = Combat.BestTarget
  if not target then return end
  --if not Me:InMeleeRange(target) then return end

  if Spell.TigerPalm:CastEx(target) then return end
  if Spell.Jab:CastEx(target) then return end
end

-- Heal logic (optional) — called every tick while the heal system runs.
-- local function DoHeal()
--   local lowest = Heal:GetLowestMember()
--   if not lowest then return end
--   -- if lowest.HealthPct < 60 and Spell.FlashHeal:CastEx(lowest) then return end
-- end

local behaviors = {
  [BehaviorType.Combat] = DoCombat,
  -- [BehaviorType.Heal] = DoHeal,
  -- [BehaviorType.Tank] = DoTank,
}

return { Options = options, Behaviors = behaviors }
