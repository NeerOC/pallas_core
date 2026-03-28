local options = {
	Name = "Warrior (Protection)",

	Widgets = {
		{ type = "text",   text = "=== Offensive ===" },
		{ type = "slider", uid = "ProtWarHeroicThrowDist", text = "Heroic Throw min distance", default = 15, min = 5, max = 30 },
	},
}

local function DoCombat()
	if Me:IsCastingOrChanneling() then return end

	-- Battle Shout — maintain buff (no target needed)
	if not Me:HasAura("Battle Shout") and Spell.BattleShout:CastEx(Me) then return end

	local target = Tank.BestTarget or Combat.BestTarget
	if not target then return end

	if not Me:InMeleeRange(target) then return end

	if not Me:IsAutoAttacking() and Me:StartAttack(target) then return end

	-- Shield Block — off-GCD, use when a mob is in melee range
	if not Me:HasAura("Shield Block") and Combat:GetEnemiesWithinDistance(4) >= 1 then
		Spell.ShieldBlock:CastEx(Me)
	end

	-- Last Stand — off-GCD, emergency defensive
	if Me.HealthPct < 30 then
		Spell.LastStand:CastEx(Me)
	end

	-- Disrupting Shout — off-GCD, AoE interrupt when 2+ nearby enemies are casting
	local casters = 0
	for _, enemy in ipairs(Combat.Targets) do
		if not enemy.IsDead and Me:GetDistance(enemy) <= 10 and enemy:IsCastingOrChanneling() then
			casters = casters + 1
		end
	end
	if casters >= 2 then
		Spell.DisruptingShout:CastEx(Me)
	end

	-- Pummel — interrupt casts
	Spell.Pummel:Interrupt()

	-- Taunt — off-GCD, grab mobs not targeting me
	for _, enemy in ipairs(Combat.Targets) do
		if enemy.InCombat then
			local enemyTarget = enemy:GetTarget()
			if enemyTarget and enemyTarget.Guid ~= Me.Guid and enemyTarget.IsPlayer then
				if Spell.Taunt:CastEx(enemy, { skipFacing = true }) then return end
			end
		end
	end

	if Spell:IsGCDActive() then return end

	-- Heroic Throw — ranged pull on distant mobs not targeting me
	local ht_min = PallasSettings.ProtWarHeroicThrowDist or 15
	for _, enemy in ipairs(Combat.Targets) do
		if enemy.InCombat then
			local enemyTarget = enemy:GetTarget()
			if enemyTarget and enemyTarget.Guid ~= Me.Guid and enemyTarget.IsPlayer then
				local dist = Me:GetDistance(enemy)
				if dist >= ht_min and dist <= 30 then
					if Spell.HeroicThrow:CastEx(enemy) then return end
				end
			end
		end
	end

	-- 1. Impending Victory — heal when low
	if Me.HealthPct < 50 and Spell.ImpendingVictory:CastEx(target) then return end

	-- 2. Thunderclap — spread Deep Wounds when 3+ lack it, or 5+ enemies nearby
	local nearby = 0
	local no_wounds = 0
	for _, enemy in ipairs(Combat.Targets) do
		if not enemy.IsDead and Me:GetDistance(enemy) <= 8 then
			nearby = nearby + 1
			if not enemy:HasAura("Deep Wounds") then
				no_wounds = no_wounds + 1
			end
		end
	end
	if (no_wounds >= 3 or nearby >= 5) and Spell.ThunderClap:CastEx(Me) then return end

	-- 3. Revenge
	if Spell.Revenge:CastEx(target) then return end

	-- 4. Shield Slam
	if Spell.ShieldSlam:CastEx(target) then return end

	-- 4. Execute — scan all nearby targets for executable enemies (needs >30% rage)
	if Me.PowerPct > 30 then
		for _, exec_target in ipairs(Combat.Targets) do
			if not exec_target.IsDead and Me:InMeleeRange(exec_target) then
				if Spell.Execute:CastEx(exec_target, { skipUsable = true }) then return end
			end
		end
	end

	-- 5. Devastate
	if Spell.Devastate:CastEx(target) then return end
end

local behaviors = {
	[BehaviorType.Combat] = DoCombat,
}

return { Options = options, Behaviors = behaviors }
