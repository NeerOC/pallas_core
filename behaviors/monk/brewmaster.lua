local options = {
	Name = "Monk (Brewmaster)", -- shown as collapsing header

	Widgets = {
		{ type = "text", text = "=== General ===" },
	},
}

local auras = { tiger_palm = 125359 }

local function DoCombat()
	if Me.HealthPct < 70 and Spell.Guard:CastEx(Me) then
		return
	end

	if Spell.SpearHandStrike:Interrupt() then
		return
	end

	if Me.HealthPct < 20 and Combat.Get and Spell.FortifyingBrew:CastEx(Me) then
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

	local spellToUse = nil
	local nearbyEnemies = Combat:GetEnemiesWithinDistance(8)
	if (Spell.KegSmash:GetCooldown().remaining > 3 or Me.PowerPct > 90) and nearbyEnemies < 3 then
		spellToUse = Spell.Jab
	else
		spellToUse = Spell.SpinningCraneKick
	end

	if spellToUse and spellToUse:CastEx(target) then
		return
	end
end

local behaviors = {
	[BehaviorType.Combat] = DoCombat,
}

return { Options = options, Behaviors = behaviors }
