local PlayerConfig = {}

local VK_W = string.byte("W")
local VK_A = string.byte("A")
local VK_S = string.byte("S")
local VK_D = string.byte("D")
local VK_Q = string.byte("Q")
local VK_SPACE = 0x20
local VK_LBUTTON = 0x01
local VK_SHIFT = 0x10

PlayerConfig.Default = {
    Input = {
        MoveForwardKey = VK_W,
        MoveBackwardKey = VK_S,
        MoveRightKey = VK_D,
        MoveLeftKey = VK_A,
        JumpKey = VK_SPACE,
        DashKey = VK_SHIFT,
        AttackKey = VK_LBUTTON,
        UltimateKey = VK_Q,
    },

    Action = {
        DashDistance = 8.0,
        DashDuration = 0.2,
        DashChargingHoldThreshold = 0.20,
        AttackStepForwardDistance = 1.5,
        AttackTurnSpeed = 12.0,
    },

    Combat = {
        MaxUltimateGauge = 100,
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
            IdlePath = "Content/Animation/Samurai_UE4/SamuraiIdle.uasset",
            WalkPath = "Content/Animation/Samurai_UE4/SamuraiWalk.uasset",
            RunPath = "Content/Animation/Samurai_UE4/SamuraiSprint.uasset",
            JumpPath = "Content/Animation/Samurai_UE4/SamuraiJump.uasset",

            AttackPaths = {
                "Content/Animation/Samurai_UE4/SamuraiAttack1.uasset",
                "Content/Animation/Samurai_UE4/SamuraiAttack2.uasset",
                "Content/Animation/Samurai_UE4/SamuraiAttack3.uasset",
                "Content/Animation/Samurai_UE4/SamuraiAttack4.uasset",
                "Content/Animation/Samurai_UE4/SamuraiAttack5.uasset",
            },

            DashPath = "Content/Animation/Samurai_UE4/SamuraiAttackHeavy1_Start.uasset",
            DashChargingPath = "Content/Animation/Samurai_UE4/SamuraiAttackHeavy1_Start.uasset",
            DashChargeAttackPath = "Content/Animation/Samurai_UE4/SamuraiAttack1.uasset",
            UltimateAttackPath = "Content/Animation/Samurai_UE4/SamuraiAttackUltimate.uasset",

            WalkThreshold = 0.1,
            RunThreshold = 8.0,
            RunSampleSpeed = 10.0,
            LocomotionSpeedResponse = 12.0,
            JumpLoop = false,

            AttackBlendIn = 0.08,
            AttackBlendOut = 0.15,
            AttackPlayRate = 1.5,

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
