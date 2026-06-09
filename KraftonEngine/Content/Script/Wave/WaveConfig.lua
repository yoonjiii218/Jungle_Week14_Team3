-- Wave/WaveConfig.lua
-- 웨이브 데이터 정의(로직 없음, 데이터만 보유).
-- 각 웨이브는 enemies 배열을 가지며, 그룹별로 종류/수/간격/거리를 따로 지정한다.
-- 한 웨이브에 여러 종류를 섞거나(Elite + Mob), 보스 동반 스폰으로 확장할 수 있다.

local WaveConfig = {
    -- [웨이브 1] 일반 몹 3마리, 0.5초 간격
    {
        waveType = "Normal",
        enemies = {
            { spawnType = "Mob", mobId = "Goblin", count = 3, spawnDelay = 0.5, distance = 15.0 },
        },
    },

    -- [웨이브 2] 일반 몹 5마리, 더 빠르게
    {
        waveType = "Normal",
        enemies = {
            { spawnType = "Mob", mobId = "Goblin", count = 5, spawnDelay = 0.3, distance = 20.0 },
        },
    },

    -- [웨이브 3] 보스 1마리 (지연 없이 바로)
    {
        waveType = "Boss",
        enemies = {
            { spawnType = "Boss", mobId = "Boss", count = 1, spawnDelay = 0.0, distance = 25.0, maxHP = 300.0 },
        },
    },

    -- 확장 예시) 일반 몹 + 엘리트 혼합 스폰
    -- {
    --     waveType = "Elite",
    --     enemies = {
    --         { spawnType = "Mob",   mobId = "Goblin", count = 4, spawnDelay = 0.4, distance = 18.0 },
    --         { spawnType = "Elite", mobId = "Ogre",   count = 1, spawnDelay = 0.0, distance = 22.0 },
    --     },
    -- },
}

return WaveConfig
