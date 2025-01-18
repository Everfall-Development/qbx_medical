local sharedConfig = require 'config.shared'
local WEAPONS = exports.qbx_core:GetWeapons()
local allowRespawn = false

local deadAnimDict = 'dead'
local deadVehAnimDict = 'veh@low@front_ps@idle_duck'
local deadVehAnim = 'sit'

local playerState = LocalPlayer.state

local function playDeadAnimation()
    local deadAnim = not QBX.PlayerData.metadata.ishandcuffed and 'dead_a' or 'dead_f'

    ClearPedTasks(cache.ped)
    SetPedCanRagdoll(cache.ped, false)

    while DeathState == sharedConfig.deathState.DEAD do
        if cache.vehicle then
            if not IsEntityPlayingAnim(cache.ped, deadVehAnimDict, deadVehAnim, 3) then
                lib.requestAnimDict(deadVehAnimDict, 5000)
                TaskPlayAnim(cache.ped, deadVehAnimDict, deadVehAnim, 100.0, 100.0, -1, 1, 1 | 32, false, false, false)
            end
        else
            if playerState.isCarried then
                if not IsEntityPlayingAnim(cache.ped, "nm", "firemans_carry", 3) then
                    lib.requestAnimDict("nm")
                    TaskPlayAnim(cache.ped, "nm", "firemans_carry", 8.0, -8.0, -1, 1 | 32, 1.0, false, false, false)
                end
            else
                if not IsEntityPlayingAnim(cache.ped, deadAnimDict, deadAnim, 3) then
                    lib.requestAnimDict(deadAnimDict, 5000)
                    TaskPlayAnim(cache.ped, deadAnimDict, deadAnim, 100.0, 100.0, -1, 1, 1 | 32, false, false, false)
                end
            end
        end

        Wait(0)
    end

    SetPedCanRagdoll(cache.ped, true)
end

exports('playDeadAnimation', playDeadAnimation)

---put player in death animation and make invincible
function OnDeath()
    if DeathState == sharedConfig.deathState.DEAD then return end
    SetDeathState(sharedConfig.deathState.DEAD)
    TriggerEvent('qbx_medical:client:onPlayerDied')
    TriggerServerEvent('qbx_medical:server:onPlayerDied')
    TriggerEvent('InteractSound_CL:PlayOnOne', 'demo', 0.1)

    --WaitForPlayerToStopMoving()

    CreateThread(function()
        while DeathState == sharedConfig.deathState.DEAD do
            DisableControls()
            SetCurrentPedWeapon(cache.ped, `WEAPON_UNARMED`, true)
            Wait(0)
        end
    end)

    ResurrectPlayer()
    CreateThread(function()
        playDeadAnimation()
    end)
    LocalPlayer.state:set('invBusy', true, false)
    SetEntityInvincible(cache.ped, true)
    SetEntityHealth(cache.ped, GetEntityMaxHealth(cache.ped))

    --[[
    TriggerServerEvent('cd_dispatch:AddNotification', {
        job_table = { "fire" },
        coords = pos,
        title = "Downed Individual",
        message = "Citizens reporting a downed individual.",
        flash = 0,
        unique_id = tostring(math.random(0000000, 9999999)),
        blip = {
            sprite = 366,
            scale = 1.2,
            colour = 1,
            flashes = true,
            text = "Downed Individual",
            time = (5 * 60 * 1000),
            sound = 1,
        }
    })
    ]]
end

exports('killPlayer', OnDeath)

local function respawn()
    local success = lib.callback.await('qbx_medical:server:respawn')
    if not success then return end
    if exports.qbx_policejob:IsHandcuffed() then
        TriggerEvent('police:client:GetCuffed', -1)
    end
    TriggerEvent('police:client:DeEscort')
end

---Allow player to respawn
function AllowRespawn()
    allowRespawn = true
    RespawnHoldTime = 5
    while DeathState == sharedConfig.deathState.DEAD do
        Wait(1000)
        DeathTime -= 1
        if DeathTime <= 0 then
            if IsControlPressed(0, 38) and RespawnHoldTime <= 1 and allowRespawn then
                respawn()
            end
            if IsControlPressed(0, 38) then
                RespawnHoldTime -= 1
            end
            if IsControlReleased(0, 38) then
                RespawnHoldTime = 5
            end
            if RespawnHoldTime <= 1 then
                RespawnHoldTime = 0
            end
        end
    end
end

exports('allowRespawn', AllowRespawn)

exports('disableRespawn', function()
    allowRespawn = false
end)

---log the death of a player along with the attacker and the weapon used.
---@param victim number ped
---@param attacker number ped
---@param weapon string weapon hash
local function logDeath(victim, attacker, weapon)
    local playerId = NetworkGetPlayerIndexFromPed(victim)
    local playerName = (' %s (%d)'):format(GetPlayerName(playerId), GetPlayerServerId(playerId)) or
        Lang:t('info.self_death')
    local killerId = NetworkGetPlayerIndexFromPed(attacker)
    local killerName = ('%s (%d)'):format(GetPlayerName(killerId), GetPlayerServerId(killerId)) or
        Lang:t('info.self_death')
    local weaponLabel = WEAPONS[weapon].label or 'Unknown'
    local weaponName = WEAPONS[weapon].name or 'Unknown'
    local message = Lang:t('logs.death_log_message',
        { killername = killerName, playername = playerName, weaponlabel = weaponLabel, weaponname = weaponName })

    lib.callback.await('qbx_medical:server:log', false, 'logDeath', message)
end

---when player is killed by another player, set last stand mode, or if already in last stand mode, set player to dead mode.
---@param event string
---@param data table
AddEventHandler('gameEventTriggered', function(event, data)
    if event ~= 'CEventNetworkEntityDamage' then return end

    if not LocalPlayer.state.isLoggedIn then return end

    local victim, attacker, victimDied, weapon = data[1], data[2], data[4], data[7]
    if not IsEntityAPed(victim) or not victimDied or NetworkGetPlayerIndexFromPed(victim) ~= cache.playerId or not IsEntityDead(cache.ped) then return end

    TriggerEvent('ox_inventory:disarm', true)

    if DeathState == sharedConfig.deathState.ALIVE then
        StartLastStand()
    elseif DeathState == sharedConfig.deathState.LAST_STAND then
        EndLastStand()
        --logDeath(victim, attacker, weapon)
        DeathTime = 0
        OnDeath()
        AllowRespawn()
    end
end)

function DisableControls()
    DisableAllControlActions(0)
    EnableControlAction(0, 1, true)
    EnableControlAction(0, 2, true)
    EnableControlAction(0, 245, true)
    EnableControlAction(0, 38, true)
    EnableControlAction(0, 0, true)
    EnableControlAction(0, 322, true)
    EnableControlAction(0, 288, true)
    EnableControlAction(0, 213, true)
    EnableControlAction(0, 249, true)
    EnableControlAction(0, 46, true)
    EnableControlAction(0, 47, true)

    SetPedResetFlag(cache.ped, 309, 1) -- Prevents ped from doing in vehicle actions like closing door, hotwiring, starting engine, putting on helmet etc
end
