local PlayerConfig = {}

PlayerConfig.Default = {
    -- Gameplay scripts read only semantic names. Physical device mapping lives in C++
    -- Lua Input bindings: WASD/LeftStick -> Move, LMB/X -> Attack, Shift/RT -> Dash, Q/Y -> Ultimate.
    Input = {
        MoveAxis = "Move",
        LookAxis = "Look",
        JumpAction = "Jump",
        DashAction = "Dash",
        AttackAction = "Attack",
        UltimateAction = "Ultimate",
        SecondaryDashAction = "SecondaryDash",
    },

    Action = {
        DashDistance = 8.0,
        DashDuration = 0.2,
        DashChargingHoldThreshold = 0.20,
        AttackStepForwardDistance = 1.5,
        AttackStepForwardDuration = 0.12,
        AttackStepForwardDistances = {
            3,
            3,
            3,
            3,
            3,
        },
        AttackStepForwardDurations = {
            0.12,
            0.12,
            0.12,
            0.12,
            0.12,
        },
        DashChargeAttackStepForwardDistance = 10.0,
        DashChargeAttackStepForwardDuration = 0.12,
        AttackTurnSpeed = 12.0,
    },

    Combat = {
        MaxHP = 100,
        MaxUltimateGauge = 100,

        -- Player -> Enemy damage. AttackIndex 1~5 uses AttackDamages.
        AttackDamages = {
            8,
            10,
            12,
            14,
            18,
        },
        DashChargeAttackDamage = 30,
        UltimateDamage = 100,

        -- Gauge/anti-duplicate policy.
        AttackHitGaugeDelta = 10,
        DashChargeAttackGaugeDelta = 15,
        PerfectDodgeGaugeDelta = 20,
        DuplicateHitLifetime = 1.0,

        -- Player defense / perfect dodge.
        HitInvincibleDuration = 0.5,
        DashPerfectDodgeDuration = 0.22,
        PerfectDodgeGraceAfterDash = 0.05,
        PerfectDodgeSlomoDuration = 1.5,
        PerfectDodgeSlomoScale = 0.1,

        -- Lua-triggered hit feedback. Player attack hitstop is still primarily
        -- driven by AnimNotifyState_AttackHitWindow, but these values are used
        -- by boss->player hits and non-notify based hit windows.
        HitStopDuration = 0.05,
        EnemyHitStopDuration = 0.04,
    },

    Feedback = {
        KatanaMeshPath = "Content/Mesh/Katana/source/red cyber katana_StaticMesh.uasset",
        KatanaSocketName = "WeaponR",
        TrailParticlePath = "Content/Data/SwordTrail2.uasset",

        UltimateCamera = {
            BackDistance = 7.0,
            Height = 10,
            SlashCameraDistance = 30.0,
            SlashCameraRightOffset = 15,
            SlashCameraHeightOffset = -5.0,
            PitchSwing = 0.0,
            YawSwing = 0.0,
            RollSwing = 2.0,
            RotationStart = 0.5,
        },

        UltimateVfx = {
            SlashSubUVResource = "SlashTexture",
            SlashFrameRate = 15.0,
            SlashFlashPath = "Content/Data/DirectionalBeam.uasset",
            LightningMaterialPath = "Content/Material/VFX/M_Lightning.mat",
            GroundCrackMaterialPath = "Content/Material/VFX/M_GroundCrack.mat",
        },

        UltimateMove = {
            StartDistance = 100.0,
            EndDistance = 30,
            SideOffset = -10.0,
            ControlSideOffset = 40.0,
            Duration = 0.3,
            FrameStep = 1.0 / 60.0,
            EndRightDistance = 5,
        },
    },

    Animation = {
        Samurai = {
            IdlePath = "Content/Animation/Samurai_Player/SamuraiIdle.uasset",
            WalkPath = "Content/Animation/Samurai_Player/SamuraiWalk.uasset",
            RunPath = "Content/Animation/Samurai_Player/SamuraiSprint.uasset",
            JumpPath = "Content/Animation/Samurai_Player/SamuraiJump.uasset",

            AttackPaths = {
                "Content/Animation/Samurai_Player/SamuraiAttack1.uasset",
                "Content/Animation/Samurai_Player/SamuraiAttack2.uasset",
                "Content/Animation/Samurai_Player/SamuraiAttack3.uasset",
                "Content/Animation/Samurai_Player/SamuraiAttack4.uasset",
                "Content/Animation/Samurai_Player/SamuraiAttack5.uasset",
            },

            DashPath = "Content/Animation/Samurai_Player/SamuraiAttackHeavy1_Start.uasset",
            DashChargingPath = "Content/Animation/Samurai_Player/SamuraiAttackHeavy1_Start.uasset",
            DashChargeAttackPath = "Content/Animation/Samurai_Player/SamuraiAttackHeavy1.uasset",
            UltimateAttackPath = "Content/Animation/Samurai_Player/SamuraiAttackUltimate.uasset",

            WalkThreshold = 0.1,
            RunThreshold = 8.0,
            RunSampleSpeed = 10.0,
            LocomotionSpeedResponse = 12.0,
            JumpLoop = false,

            AttackBlendIn = 0.08,
            AttackBlendOut = 0.15,
            AttackPlayRate = 1.5,
            AttackPlayRates = {
                2,
                3,
                3,
                3,
                3,
            },

            DashBlendIn = 0.05,
            DashBlendOut = 0.12,
            DashPlayRate = 3.0,
            DashChargingBlendIn = 0.05,
            DashChargingPlayRate = 1.0,
            DashChargingToAttackBlend = 0.03,
            DashChargeAttackBlendOut = 0.12,
            DashChargeAttackPlayRate = 1.4,
            DashChargeAttackFallbackDuration = 0.65,

            UltimateAttackBlendIn = 0.05,
            UltimateAttackBlendOut = 0.12,
            UltimateAttackPlayRate = 1.2,

            JumpBlendIn = 0.1,
            JumpBlendOut = 0.2,
            JumpPlayRate = 1.0,
        }
    }
}

local function CloneTable(source)
    local result = {}
    for key, value in pairs(source) do
        if type(value) == "table" then
            result[key] = CloneTable(value)
        else
            result[key] = value
        end
    end
    return result
end

function PlayerConfig.Create()
    return CloneTable(PlayerConfig.Default)
end

return PlayerConfig
