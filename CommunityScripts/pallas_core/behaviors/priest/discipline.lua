local options = {
	Name = "Priest (Discipline)", -- shown as collapsing header

	Widgets = {
		{ type = "text", text = "=== General ===" },
	},
}

local function DoHeal()
	if Me:IsCastingOrChanneling() then
		return
	end

	if Spell:IsGCDActive() then
		return
	end

	-- Shield allies being targeted by mobs
	local friend_set = {}
	for _, ally in ipairs(Heal.Friends.All) do
		friend_set[ally.Guid] = ally
	end

	for _, enemy in ipairs(Combat.Targets or {}) do
		local tgt = enemy:GetTarget()
		if tgt then
			local ally = friend_set[tgt.Guid]
			if ally and not ally:HasAura("Power Word: Shield") and not ally:HasAura("Weakened Soul") then
				if Spell.PowerWordShield:CastEx(ally) then
					return
				end
			end
		end
	end

	-- Penance at 50%, Flash Heal at 75%
	local lowest = Heal:GetLowestMember()
	if lowest then
		if lowest.HealthPct <= 50 then
			if Spell.Penance:CastEx(lowest) then
				return
			end
		end

		if lowest.HealthPct <= 75 then
			if Spell.FlashHeal:CastEx(lowest) then
				return
			end
		end
	end

	-- Damage filler
	local target = Combat.BestTarget
	if not target then
		return
	end

	if not target:HasAura("Shadow Word: Pain") then
		if Spell.ShadowWordPain:CastEx(target) then
			return
		end
	end

	if Spell.Smite:CastEx(target) then
		return
	end
end

local function DoDraw()
	local visible = imgui.begin_window("Pallas", 0)
	if visible then
		if imgui.collapsing_header("GetTarget Debug") then
			local targets = Combat.Targets or {}
			if #targets == 0 then
				imgui.text("No enemies in Combat.Targets")
			end
			for _, enemy in ipairs(targets) do
				local tgt = enemy:GetTarget()
				local tgt_name = "nil"
				local tgt_guid = "nil"
				if tgt then
					tgt_name = tgt.Name or "?"
					tgt_guid = tostring(tgt.guid_lo or "?")
				end
				imgui.text(string.format("%s -> %s (guid_lo: %s)", enemy.Name or "?", tgt_name, tgt_guid))
			end
		end
	end
	imgui.end_window()
end

-- No-op combat behavior — needed so Combat:WantToRun() returns true
-- and Combat.Targets / Combat.BestTarget get populated.
-- All logic runs in DoHeal to guarantee heal-first priority.
local function DoCombat() end

local behaviors = {
	[BehaviorType.Heal] = DoHeal,
	[BehaviorType.Combat] = DoCombat,
}

return { Options = options, Behaviors = behaviors, Draw = DoDraw }
