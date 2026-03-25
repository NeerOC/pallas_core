local options = {
    Name = "Shaman (Restoration)", -- shown as collapsing header

    Widgets = {
        { type = "text", text = "=== General ===" },
    },
}

local function DoRotation()
    local lowest = Heal:GetLowestMember()

    -- Cancel Healing Surge if nobody needs healing
    if Me.CastingSpellId == Spell.HealingSurge.Id and (not lowest or lowest.HealthPct > 90) then
        Me:StopCasting()
    end

    if Me:IsCastingOrChanneling() then
        return
    end

    if Spell.WindShear:Interrupt() then
        return
    end

    if Spell:IsGCDActive() then
        return
    end

    -- Healing
    if lowest then
        if lowest.HealthPct < 65 and Spell.HealingSurge:CastEx(lowest) then
            return
        end

        if lowest.HealthPct < 90 and Spell.Riptide:CastEx(lowest) then
            return
        end
    end

    -- Utility
    if Spell.PurifySpirit:Dispel(true, { DispelType.Magic, DispelType.Curse }) then
        return
    end

    -- Damage (only when healing is comfortable)
    if lowest and (lowest.HealthPct < 80 or Me.PowerPct < 60) then
        return
    end

    if not Me:HasAura("Flametongue Weapon (Passive)") and Spell.FlametongueWeapon:CastEx(Me) then
        return
    end

    if not Me:HasAura("Lightning Shield") and Spell.LightningShield:CastEx(Me) then
        return
    end

    local target = Combat.BestTarget
    if not target then
        return
    end

    if Spell.EarthShock:CastEx(target) then
        return
    end

    if Spell.LightningBolt:CastEx(target, { skipMoving = true }) then
        return
    end
end

local behaviors = {
    [BehaviorType.Heal] = DoRotation,
    [BehaviorType.Combat] = DoRotation,
}

return { Options = options, Behaviors = behaviors }
