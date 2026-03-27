local options = {
	Name = "Warrior (Protection)",

	Widgets = {
		{ type = "text",   text = "=== Offensive ===" },
		{ type = "slider", uid = "ProtWarHeroicThrowDist", text = "Heroic Throw min distance", default = 15, min = 5, max = 30 },
		{ type = "text",   text = "=== AoE ===" },
		{ type = "slider", uid = "ProtWarThunderclapTargets", text = "Thunderclap min targets", default = 5, min = 1, max = 10 },
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

	-- 2. Revenge
	if Spell.Revenge:CastEx(target) then return end

	-- 2. Shield Slam
	if Spell.ShieldSlam:CastEx(target) then return end

	-- 2. Thunderclap — AoE when enough targets nearby
	local tc_targets = PallasSettings.ProtWarThunderclapTargets or 5
	if Combat:GetEnemiesWithinDistance(8) >= tc_targets and Spell.ThunderClap:CastEx(Me) then return end

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
