local options = {
    Name = "Monk (Mistweaver)",

    Widgets = {
        { type = "header",   text = "General" },
        { type = "slider",   uid = "MWDPSAboveHP",          text = "DPS Above Health %",             default = 85,  min = 0,                                            max = 100 },
        { type = "slider",   uid = "MWDPSManaFloor",        text = "DPS Mana Floor %",               default = 50,  min = 0,                                            max = 100 },

        { type = "header",   text = "Single Target Healing" },
        { type = "slider",   uid = "MWSoothingMist",        text = "Soothing Mist %",                default = 80,  min = 0,                                            max = 100 },
        { type = "slider",   uid = "MWSurgingMist",         text = "Surging Mist %",                 default = 55,  min = 0,                                            max = 100 },
        { type = "slider",   uid = "MWEnvelopingMist",      text = "Enveloping Mist %",              default = 65,  min = 0,                                            max = 100 },
        { type = "slider",   uid = "MWRenewingMist",        text = "Renewing Mist %",                default = 95,  min = 0,                                            max = 100 },
        { type = "slider",   uid = "MWHealingSphereHP",     text = "Healing Sphere %",               default = 50,  min = 0,                                            max = 100 },

        { type = "header",   text = "AoE Healing" },
        { type = "slider",   uid = "MWUpliftCount",         text = "Uplift - Members Below",         default = 3,   min = 1,                                            max = 10 },
        { type = "slider",   uid = "MWUpliftHP",            text = "Uplift - Health %",              default = 85,  min = 0,                                            max = 100 },
        { type = "slider",   uid = "MWSpinningCraneHP",     text = "Spinning Crane Kick - Health %", default = 75,  min = 0,                                            max = 100 },
        { type = "slider",   uid = "MWSpinningCraneCount",  text = "Spinning Crane Kick - Members",  default = 4,   min = 1,                                            max = 10 },

        { type = "header",   text = "Mana Management" },
        { type = "slider",   uid = "MWManaTeaBelow",        text = "Mana Tea Below Mana %",          default = 80,  min = 0,                                            max = 100 },
        { type = "slider",   uid = "MWManaTeaMinStacks",    text = "Mana Tea Min Stacks",            default = 2,   min = 1,                                            max = 20 },

        { type = "header",   text = "Cooldowns" },
        { type = "slider",   uid = "MWLifeCocoonHP",        text = "Life Cocoon %",                  default = 25,  min = 0,                                            max = 100 },
        { type = "slider",   uid = "MWRevivalHP",           text = "Revival - Health %",             default = 40,  min = 0,                                            max = 100 },
        { type = "slider",   uid = "MWRevivalCount",        text = "Revival - Members Below",        default = 3,   min = 1,                                            max = 10 },
        { type = "checkbox", uid = "MWUseThunderFocusTea",  text = "Use Thunder Focus Tea",          default = true },
        { type = "slider",   uid = "MWTFTUpliftCount",      text = "TFT Uplift - Members Below",     default = 3,   min = 1,                                            max = 10 },
        { type = "slider",   uid = "MWTFTUpliftHP",         text = "TFT Uplift - Health %",          default = 80,  min = 0,                                            max = 100 },

        { type = "header",   text = "Utility" },
        { type = "checkbox", uid = "MWStopCasting",         text = "Cancel overheals",               default = true },
        { type = "checkbox", uid = "MWLegacyOfTheEmperor",  text = "Legacy of the Emperor",          default = true },
        { type = "combobox", uid = "MWTalentTier4",         text = "Tier 4 Talent",                  default = 0,   options = { "Chi Wave", "Zen Sphere", "Chi Burst" } },
    },
}

local auras = {
    soothing_mist     = 115175,
    renewing_mist     = 119611,
    enveloping_mist   = 132120,
    muscle_memory     = 139597,
    vital_mists       = 118674,
    tiger_power       = 125359,
    teachings         = 118672, -- Teachings of the Monastery
    thunder_focus_tea = 116680,
    mana_tea_stacks   = 115867, -- Mana Tea (stacking buff)
    legacy_of_emperor = 117666,
    life_cocoon       = 116849,
    serpents_zeal     = 127722,
    zen_sphere        = 124081,
}

local JADE_STATUE_KEY = 550 -- ImGuiKey E key


-- Find the friend unit we're currently casting/channeling on
local function get_cast_target()
    local lo = Me.CastTargetLo
    if not lo or lo == 0 then return nil end
    for _, f in ipairs(Heal.Friends and Heal.Friends.All or {}) do
        if f.guid_lo == lo then return f end
    end
    return nil
end


local function DoRotation()
    if Me.IsMounted then return end
    if Me:IsDisabled() then return end

    -- ── Jade Serpent Statue: hold E key to place at player position
    if imgui.is_key_pressed(JADE_STATUE_KEY) and Spell.SummonJadeSerpentStatue then
        print("YES")
        Spell.SummonJadeSerpentStatue:CastAtPos(Me)
    end

    local lowest = Heal:GetLowestMember()
    local channeling_soothing = (Me.ChannelingSpellId == Spell.SoothingMist.Id)

    -- ── Stop Casting: cancel heals/channels that are no longer needed ──
    if Me:IsCastingOrChanneling() then
        -- Cancel Mana Tea if mana is full or someone needs urgent healing
        if Me.ChannelingSpellId == Spell.ManaTea.Id then
            if Me.PowerPct >= 100 or (lowest and lowest.HealthPct < 50) then
                Me:StopCasting()
            end
        end

        -- Cancel overheals
        if PallasSettings.MWStopCasting ~= false then
            local ct = get_cast_target()
            if ct then
                local spell_id = Me.CastingSpellId
                if spell_id == Spell.SurgingMist.Id and ct.HealthPct > 92 then
                    Me:StopCasting()
                elseif spell_id == Spell.EnvelopingMist.Id and ct.HealthPct > 90 then
                    Me:StopCasting()
                end
                -- Cancel Soothing Mist channel if target is near full
                if channeling_soothing and ct.HealthPct > 95 then
                    Me:StopCasting()
                    channeling_soothing = false
                end
            end
        end
    end

    -- Allow Soothing Mist channel to continue, block other casts/channels
    if Me:IsCastingOrChanneling() and not channeling_soothing then
        return
    end

    -- ── Off-GCD: Interrupt ──────────────────────────────────────────
    if Spell.SpearHandStrike:Interrupt() then
        return
    end

    -- ── Off-GCD: Mana Tea (channeled, drink between heals) ─────────
    local mana_tea_pct = PallasSettings.MWManaTeaBelow or 80
    local mana_tea_min = PallasSettings.MWManaTeaMinStacks or 2
    if Me.PowerPct < mana_tea_pct and not channeling_soothing then
        local tea_aura = Me:GetAura(auras.mana_tea_stacks)
        local tea_stacks = tea_aura and tea_aura.stacks or 0
        if tea_stacks >= mana_tea_min then
            -- Only drink Mana Tea if nobody is in immediate danger
            if not lowest or lowest.HealthPct > 60 then
                if Spell.ManaTea:CastEx(Me) then
                    return
                end
            end
        end
    end

    -- ── Off-GCD: Thunder Focus Tea (activate before GCD spells) ─────
    if PallasSettings.MWUseThunderFocusTea ~= false and not Me:HasAura(auras.thunder_focus_tea) then
        local tft_uplift_hp        = PallasSettings.MWTFTUpliftHP or 80
        local tft_uplift_count     = PallasSettings.MWTFTUpliftCount or 3
        local members_below_tft, _ = Heal:GetMembersBelow(tft_uplift_hp)
        if #members_below_tft >= tft_uplift_count and Spell.ThunderFocusTea:CastEx(Me) then
            return
        end
    end

    if Spell:IsGCDActive() then
        return
    end

    -- ── Emergency cooldowns ─────────────────────────────────────────
    -- Life Cocoon: emergency absorb shield
    if lowest then
        local cocoon_pct = PallasSettings.MWLifeCocoonHP or 25
        if lowest.HealthPct < cocoon_pct and Spell.LifeCocoon:CastEx(lowest, { skipFacing = true }) then
            return
        end
    end

    -- Healing Sphere: spam on critically low targets
    local hs_pct = PallasSettings.MWHealingSphereHP or 50
    if lowest and lowest.HealthPct < hs_pct then
        if Spell.HealingSphere:CastAtPos(lowest) then
            return
        end
    end

    -- Revival: raid-wide emergency heal
    local revival_hp               = PallasSettings.MWRevivalHP or 40
    local revival_count            = PallasSettings.MWRevivalCount or 3
    local members_below_revival, _ = Heal:GetMembersBelow(revival_hp)
    if #members_below_revival >= revival_count and Spell.Revival:CastEx(Me, { skipFacing = true }) then
        return
    end

    -- ── Pre-compute AoE healing state (used by Chi Brew, TFT, Uplift) ─
    local all_friends              = Heal.Friends and Heal.Friends.All or {}
    local uplift_hp                = PallasSettings.MWUpliftHP or 85
    local uplift_count             = PallasSettings.MWUpliftCount or 3
    local members_below_uplift, _  = Heal:GetMembersBelow(uplift_hp)
    local uplift_ready             = #members_below_uplift >= uplift_count

    -- ── Chi Brew: pop when low mana, low tea stacks, and low Chi ─────
    if Spell.ChiBrew and Me.Chi < 3 and Me.PowerPct < 60 then
        local tea_aura = Me:GetAura(auras.mana_tea_stacks)
        local tea_stacks = tea_aura and tea_aura.stacks or 0
        if tea_stacks < 5 and Spell.ChiBrew:CastEx(Me) then
            return
        end
    end

    -- ── Vital Mists: instant free Surging Mist at 5 stacks ─────────
    if lowest then
        local vm_aura = Me:GetAura(auras.vital_mists)
        local vm_stacks = vm_aura and vm_aura.stacks or 0
        if vm_stacks >= 5 and lowest.HealthPct < 90 and lowest:HasAura(auras.soothing_mist) then
            if Spell.SurgingMist:CastEx(lowest, { skipFacing = true }) then
                return
            end
        end
    end

    -- ── Muscle Memory: spend proc on Blackout Kick for Serpent's Zeal
    if Me:HasAura(auras.muscle_memory) then
        local target = Combat.BestTarget
        if target and Spell.BlackoutKick:CastEx(target) then
            return
        end
    end

    -- ── Thunder Focus Tea: consume buff on Uplift or Surging Mist ───
    if Me:HasAura(auras.thunder_focus_tea) then
        -- TFT Uplift: double healing on all Renewing Mist targets
        if uplift_ready and Spell.Uplift:CastEx(Me, { skipFacing = true }) then
            return
        end
        -- Fallback: free Surging Mist for single target (requires Soothing Mist)
        if lowest and lowest.HealthPct < 70 and lowest:HasAura(auras.soothing_mist) then
            if Spell.SurgingMist:CastEx(lowest, { skipFacing = true }) then
                return
            end
        end
    end

    -- ── Renewing Mist: keep on cooldown (generates Chi, Uplift targets)
    local renew_pct = PallasSettings.MWRenewingMist or 95
    for _, f in ipairs(all_friends) do
        if f.HealthPct < renew_pct and not f:HasAura(auras.renewing_mist) then
            if Spell.RenewingMist:CastEx(f, { skipFacing = true }) then
                return
            end
        end
    end

    -- ── AoE Healing: Uplift (reuses pre-computed uplift state) ──────
    if uplift_ready and Spell.Uplift:CastEx(Me, { skipFacing = true }) then
        return
    end

    -- ── AoE Healing: Spinning Crane Kick ────────────────────────────
    local sck_hp               = PallasSettings.MWSpinningCraneHP or 75
    local sck_count            = PallasSettings.MWSpinningCraneCount or 4
    local members_below_sck, _ = Heal:GetMembersBelow(sck_hp)
    if #members_below_sck >= sck_count and Spell.SpinningCraneKick:CastEx(Me, { skipFacing = true }) then
        return
    end

    -- ── Single Target Healing ───────────────────────────────────────
    if lowest then
        local surging_pct    = PallasSettings.MWSurgingMist or 55
        local enveloping_pct = PallasSettings.MWEnvelopingMist or 65
        local soothing_pct   = PallasSettings.MWSoothingMist or 80

        -- Soothing Mist must be channeling on target before Surging/Enveloping
        -- become instant casts (core MoP Mistweaver mechanic)
        if lowest.HealthPct < surging_pct or lowest.HealthPct < enveloping_pct then
            if lowest:HasAura(auras.soothing_mist) then
                -- Target has Soothing Mist: cast instant Surging / Enveloping
                if lowest.HealthPct < surging_pct then
                    if Spell.SurgingMist:CastEx(lowest, { skipFacing = true }) then
                        return
                    end
                end

                if lowest.HealthPct < enveloping_pct and not lowest:HasAura(auras.enveloping_mist) then
                    if Spell.EnvelopingMist:CastEx(lowest, { skipFacing = true }) then
                        return
                    end
                end
            else
                -- Target doesn't have Soothing Mist yet: start channeling on them
                if Spell.SoothingMist:CastEx(lowest, { skipFacing = true }) then
                    return
                end
            end
        end

        -- Soothing Mist: light sustained healing
        if lowest.HealthPct < soothing_pct then
            if Spell.SoothingMist:CastEx(lowest, { skipFacing = true }) then
                return
            end
        end
    end

    -- ── Tier 4 Talent: Chi Wave / Zen Sphere / Chi Burst ────────────
    local talent_choice = PallasSettings.MWTalentTier4 or 0

    if talent_choice == 0 then
        -- Chi Wave: smart bounce heal/damage
        if lowest and lowest.HealthPct < 90 then
            if Spell.ChiWave:CastEx(lowest, { skipFacing = true }) then
                return
            end
        end
    elseif talent_choice == 1 then
        -- Zen Sphere: HoT on injured target without it
        if lowest and lowest.HealthPct < 85 and not lowest:HasAura(auras.zen_sphere) then
            if Spell.ZenSphere:CastEx(lowest, { skipFacing = true }) then
                return
            end
        end
    else
        -- Chi Burst: line projectile, heals friends and damages enemies in path
        local CHI_BURST_CONE = 0.15 -- tight cone (~8.5 degrees half-angle)
        if Spell.ChiBurst then
            local enemies_hit = 0
            local friends_hit = 0
            for _, e in ipairs(Combat.Targets or {}) do
                if Me:GetDistance(e) <= 40 and Me:IsFacing(e, CHI_BURST_CONE) then
                    enemies_hit = enemies_hit + 1
                end
            end
            if enemies_hit >= 1 then
                for _, f in ipairs(all_friends) do
                    if f.HealthPct < 95 and Me:GetDistance(f) <= 40 and Me:IsFacing(f, CHI_BURST_CONE) then
                        friends_hit = friends_hit + 1
                        break
                    end
                end
            end
            if enemies_hit >= 1 and friends_hit >= 1 and Spell.ChiBurst:CastEx(Me) then
                return
            end
        end
    end

    -- ── Detox ───────────────────────────────────────────────────────
    if Spell.Detox:Dispel(true, { DispelType.Magic, DispelType.Poison, DispelType.Disease }) then
        return
    end

    -- ── Resurrect current target if dead ────────────────────────────
    local myTarget = Me.Target
    if myTarget and myTarget.IsDead and myTarget.IsPlayer and Spell.Resuscitate:CastEx(myTarget, { skipFacing = true }) then
        return
    end

    -- ── Legacy of the Emperor (out of combat buff) ──────────────────
    if not Me.InCombat and PallasSettings.MWLegacyOfTheEmperor ~= false then
        for _, f in ipairs(all_friends) do
            if not f:HasAura(auras.legacy_of_emperor) and Spell.LegacyOfTheEmperor:CastEx(f, { skipFacing = true }) then
                return
            end
        end
    end

    -- ── Damage / Fistweaving (only when healing is comfortable) ─────
    local dps_above_hp = PallasSettings.MWDPSAboveHP or 85
    if lowest and lowest.HealthPct < dps_above_hp then
        return
    end

    local mana_floor = PallasSettings.MWDPSManaFloor or 50
    if Me.PowerPct < mana_floor then
        return
    end

    local target = Combat.BestTarget
    if not target then
        return
    end

    if not Me:IsAutoAttacking() and Me:StartAttack(target) then
        return
    end

    -- Chi Wave (offensive) if not used for healing above
    if talent_choice == 0 and Spell.ChiWave:CastEx(target) then
        return
    end

    -- Maintain Tiger Power buff
    if not Me:HasAura(auras.tiger_power) and Spell.TigerPalm:CastEx(target) then
        return
    end

    -- Blackout Kick: builds Serpent's Zeal (increases healing from Eminence)
    if Spell.BlackoutKick:CastEx(target) then
        return
    end

    -- Jab: Chi builder, builds Vital Mists stacks
    if Spell.Jab:CastEx(target) then
        return
    end
end

local behaviors = {
    [BehaviorType.Heal] = DoRotation,
    [BehaviorType.Combat] = DoRotation,
}

return { Options = options, Behaviors = behaviors }
