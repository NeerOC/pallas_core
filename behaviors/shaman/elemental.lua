local options = {
	Name = "Shaman (Elemental)", -- shown as collapsing header

	Widgets = {
		{ type = "text", text = "=== General ===" },
	},
}

local THUNDERSTORM_RANGE = 10
local THUNDERSTORM_COUNT = 3

local function DoCombat()
	local lowest = Heal:GetLowestMember()
	if not lowest then
		return
	end

	if lowest.HealthPct < 50 or Me.PowerPct < 60 then return end

	if not Me:HasAura("Flametongue Weapon (Passive)") and Spell.FlametongueWeapon:CastEx(Me) then
		return
	end

	if Me:IsCastingOrChanneling() then
		return
	end

	if Spell.WindShear:Interrupt() then
		return
	end

	if not Me:HasAura("Lightning Shield") and Spell.LightningShield:CastEx(Me) then
		return
	end

	if Me.HealthPct < 50 and Spell.HealingSurge:CastEx(Me) then
		return
	end

	local target = Combat.BestTarget
	if not target then
		return
	end

	if Spell:IsGCDActive() then
		return
	end

	-- Thunderstorm: knock back melee enemies when too many are close
	local nearby = Combat:GetTargetsAround(Me, THUNDERSTORM_RANGE)
	if nearby >= THUNDERSTORM_COUNT and Spell.Thunderstorm:CastEx(Me) then
		return
	end

	if Spell.EarthShock:CastEx(target) then
		return
	end

	if Spell.LightningBolt:CastEx(target, { skipMoving = true }) then
		return
	end
end

local function DoHeal()
	local lowest = Heal:GetLowestMember()

	-- Cancel Healing Surge if nobody needs healing
	if Me.CastingSpellId == Spell.HealingSurge.Id and (not lowest or lowest.HealthPct > 90) then
		Me:StopCasting()
	end

	if Me:IsCastingOrChanneling() then
		return
	end

	if Spell:IsGCDActive() then
		return
	end

	if not lowest then
		return
	end

	if lowest.HealthPct < 65 and Spell.HealingSurge:CastEx(lowest) then
		return
	end
end

local behaviors = {
	[BehaviorType.Heal] = DoHeal,
	[BehaviorType.Combat] = DoCombat,
}

return { Options = options, Behaviors = behaviors }
