local options = {
	Name = "Monk (Brewmaster)", -- shown as collapsing header

	Widgets = {
		{ type = "text", text = "=== General ===" },
	},
}

local auras = { tiger_palm = 125359 }

local function DoCombat()
	if Spell.SpearHandStrike:Interrupt() then
		return
	end

	local target = Combat.BestTarget
	if not target then
		return
	end

	if not Me:InMeleeRange(target) then
		return
	end

	if not Me:IsAutoAttacking() and Me:StartAttack(target) then
		return
	end

	if Me.HealthPct < 70 and Spell.Guard:CastEx(Me) then
		return
	end

	if Spell:IsGCDActive() then
		return
	end

	if Me.HealthPct < 80 and Spell.ChiWave:CastEx(target) then
		return
	end

	if
		not target:HasAura("Breath of Fire")
		and target:HasAura("Dizzying Haze")
		and Spell.BreathOfFire:CastEx(target)
	then
		return
	end

	if not Me:HasAura(auras.tiger_palm) and Spell.TigerPalm:CastEx(target) then
		return
	end

	if Spell.KegSmash:CastEx(target) then
		return
	end

	if Spell.BlackoutKick:CastEx(target) then
		return
	end

	if (Spell.KegSmash:GetCooldown().remaining > 3 or Me.PowerPct > 90) and Spell.Jab:CastEx(target) then
		return
	end

	if Spell.TigerPalm:CastEx(target) then
		return
	end
end

local behaviors = {
	[BehaviorType.Combat] = DoCombat,
}

return { Options = options, Behaviors = behaviors }
