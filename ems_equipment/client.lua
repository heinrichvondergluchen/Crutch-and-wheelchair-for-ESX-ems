------------------------------------------------------------
-- EMS Equipment Script - Client side
-- 
-- Kommando: /emsudstyr (kun ambulancejob) 
--   -> Åbner en NUI-menu, hvor man vælger:
--      * Krykker eller Kørestol
--      * En spiller i nærheden (3m)
--      * Varighed (1-10 minutter)
--   -> Serveren tjekker, om spilleren allerede har udstyr.
-- 
-- KRYKKER:
--   * Spilleren kan smide krykken ved at slå (melee),
--     eller ved at ragdolle/falde meget.
--   * Krykken kan KUN samles op af ejeren.
--   * Den fjernes automatisk efter varighedens udløb.
-- 
-- KØRESTOL:
--   * Spilleren sættes i en driveable kørestol i varighedens tid.
--   * Blokeret "F" exit.
--   * Fjernes automatisk efter varighedens udløb.
--
-- Kode opryddet & /fjernudstyr er fjernet.
-- 
-- God fornøjelse!
------------------------------------------------------------

ESX = exports['es_extended']:getSharedObject()

------------------------------------------------------------
-- Globale variabler
------------------------------------------------------------
local wheelchairActive = false
local currentWheelchair = nil

local activeEquipment = nil  -- "krykker" / "kørestol"
local isUsingCrutch = false

local crutchOwner = nil       -- Server ID på ejeren af krykken
local crutchObject = nil      -- Krykke i hånd
local groundCrutchObject = nil-- Krykke på jorden (hvis smidt)

------------------------------------------------------------
-- Model references
------------------------------------------------------------
local crutchModel = `prop_mads_crutch01`  -- Den custom crutch-model
local clipSet = "move_lester_CaneUp"      -- Clipset for "haltende" gang

------------------------------------------------------------
-- HVORDAN KØRER SCRIPTET?
--
-- 1. Ambulancejob bruger "/emsudstyr" for at åbne menuen.
-- 2. De vælger (krykker/kørestol), spiller, og varighed => "Anvend".
-- 3. Serveren tjekker om spilleren må få udstyr (om tid er udløbet).
-- 4. Hvis ja, trigges "ems:applyCrutchesTarget" eller "ems:applyWheelchairTarget" 
--    hos target-spilleren.
-- 5. Target-spilleren får sin crutch/kørestol, i X minutter.
------------------------------------------------------------

------------------------------------------------------------
-- 1) KOMMANDO: /emsudstyr
------------------------------------------------------------
RegisterCommand('emsudstyr', function()
    local xPlayer = ESX.GetPlayerData()
    if xPlayer and xPlayer.job and xPlayer.job.name == 'ambulance' then
        openEmsMenu()
    else
        ESX.ShowNotification('Du har ikke adgang til dette.')
    end
end)

------------------------------------------------------------
-- 2) Åbn NUI-menu
------------------------------------------------------------
function openEmsMenu()
    local playerPed = PlayerPedId()
    local players = ESX.Game.GetPlayersInArea(GetEntityCoords(playerPed), 3.0)
    local playerIds = {}
    local myServerId = GetPlayerServerId(PlayerId())
    local foundMyself = false

    -- Saml server IDs for de spillere i nærheden
    for i = 1, #players do
        local serverId = GetPlayerServerId(players[i])
        table.insert(playerIds, serverId)
        if serverId == myServerId then
            foundMyself = true
        end
    end

    -- Hvis vi ikke fandt mig selv i listen, tilføj
    if not foundMyself then
        table.insert(playerIds, myServerId)
    end

    if #playerIds == 0 then
        ESX.ShowNotification('Ingen spillere i nærheden.')
        return
    end

    -- Hent ID+navn fra serveren
    ESX.TriggerServerCallback('ems:getNearbyIdentities', function(identities)
        -- Gør NUI aktiv
        SetNuiFocus(true, true)
        SendNUIMessage({
            action = "open",
            players = identities
        })
    end, playerIds)
end

------------------------------------------------------------
-- 3) CRUTCH-FUNKTIONER
------------------------------------------------------------
local disableSprint = true
local disableWeapons = true
local unarmed = `WEAPON_UNARMED`

------------------------------------------------------------
-- HJÆLPEFUNKTIONER
------------------------------------------------------------
local function LoadClipSet(set)
    RequestClipSet(set)
    while not HasClipSetLoaded(set) do
        Wait(10)
    end
end

local function LoadAnimDict(dict)
    RequestAnimDict(dict)
    while not HasAnimDictLoaded(dict) do
        Wait(10)
    end
end

local function DisplayHelpText(msg)
    BeginTextCommandDisplayHelp("STRING")
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandDisplayHelp(0, false, true, 50)
end

local function DisplayNotification(msg)
    BeginTextCommandThefeedPost("STRING")
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandThefeedPostTicker(false, false)
end

------------------------------------------------------------
-- Afmonter alt + ryd variabler
------------------------------------------------------------
function UnequipCrutch()
    -- Slet hånd-krykke
    if crutchObject and DoesEntityExist(crutchObject) then
        DeleteEntity(crutchObject)
    end
    crutchObject = nil

    -- Slet jord-krykke
    if groundCrutchObject and DoesEntityExist(groundCrutchObject) then
        DeleteEntity(groundCrutchObject)
    end
    groundCrutchObject = nil

    isUsingCrutch = false
    activeEquipment = nil
    crutchOwner = nil

    if disableSprint then
        SetPlayerSprint(PlayerId(), true)
    end
    ResetPedMovementClipset(PlayerPedId(), 1.0)
end

------------------------------------------------------------
-- Tjek om spiller overhovedet kan få krykker
------------------------------------------------------------
local function CanPlayerEquipCrutch()
    local playerPed = PlayerPedId()
    local hasWeapon, _weaponHash = GetCurrentPedWeapon(playerPed, true)
    if hasWeapon then
        return false, "Du kan ikke bruge krykker, mens du har et våben i hånden."
    elseif IsPedInAnyVehicle(playerPed, false) then
        return false, "Du kan ikke bruge krykker i et køretøj."
    elseif IsEntityDead(playerPed) then
        return false, "Du er død..."
    elseif IsPedInMeleeCombat(playerPed) then
        return false, "Du kan ikke bruge krykker midt i et slagsmål."
    elseif IsPedFalling(playerPed) then
        return false, "Du kan ikke bruge krykker, mens du falder."
    elseif IsPedRagdoll(playerPed) then
        return false, "Du kan ikke bruge krykker, mens du er ragdoll."
    end
    return true
end

------------------------------------------------------------
-- Lav en krykke i hånd
------------------------------------------------------------
local function CreateCrutchObjectInHand()
    if not HasModelLoaded(crutchModel) then
        RequestModel(crutchModel)
        while not HasModelLoaded(crutchModel) do
            Wait(10)
        end
    end
    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed)
    crutchObject = CreateObject(crutchModel, coords.x, coords.y, coords.z, true, true, false)
    AttachEntityToEntity(crutchObject, playerPed, 70, 1.18, -0.36, -0.20, -20.0, -87.0, -20.0, true, true, false, true, 1, true)
end

------------------------------------------------------------
-- Smid krykken på jorden (detach)
------------------------------------------------------------
local function DetachCrutchToGround()
    local playerPed = PlayerPedId()
    if crutchObject then
        DetachEntity(crutchObject, true, true)
        -- Fjernet ClearPedTasksImmediately for at undgå, at animationen fryser:
        -- ClearPedTasksImmediately(playerPed)

        SetEntityAsMissionEntity(crutchObject, true, true)

        local coords = GetEntityCoords(playerPed)
        SetEntityCoords(crutchObject, coords.x, coords.y, coords.z - 0.9, false, false, false, true)
        PlaceObjectOnGroundProperly(crutchObject)

        groundCrutchObject = crutchObject
        crutchObject = nil
    end
end


------------------------------------------------------------
-- Overvågningstråde til crutch
------------------------------------------------------------
local function FrameThread()
    CreateThread(function()
        while isUsingCrutch do
            SetPedCanPlayAmbientAnims(PlayerPedId(), false)
            Wait(0)
        end
    end)
end

local function MainThread()
    CreateThread(function()
        local fallCount = 0
        while isUsingCrutch do
            Wait(250)
            local playerPed = PlayerPedId()
            
            -- Er vi døde/ragdoll => slip krykken
            if IsPedRagdoll(playerPed) or IsEntityDead(playerPed) then
                DetachCrutchToGround()

            -- Er vi i melee => slip krykken
            elseif IsPedInMeleeCombat(playerPed) then
                Wait(500)
                if isUsingCrutch and crutchObject then
                    DetachCrutchToGround()
                end

            -- Falder vi? Efter 3 ticks => slip krykken
            elseif IsPedFalling(playerPed) then
                fallCount = fallCount + 1
                if fallCount > 3 and isUsingCrutch and crutchObject then
                    DetachCrutchToGround()
                    fallCount = 0
                end
            elseif fallCount > 0 then
                fallCount = fallCount - 1
            end
        end
    end)
end

------------------------------------------------------------
-- Spor krykke på jorden => Ejeren kan samle op
------------------------------------------------------------
local function TraceGroundCrutch()
    local trace = true
    while trace do
        Wait(0)

        if not groundCrutchObject or not DoesEntityExist(groundCrutchObject) then
            trace = false
            break
        end
        if not isUsingCrutch then
            -- Spiller har ikke længere krykke => stop
            trace = false
            break
        end

        local playerPed = PlayerPedId()
        if not IsPedFalling(playerPed) and not IsPedRagdoll(playerPed) then
            local dist = #(GetEntityCoords(playerPed) - GetEntityCoords(groundCrutchObject))
            if dist < 2.0 then
                -- KUN ejeren får prompt
                if GetPlayerServerId(PlayerId()) == crutchOwner then
                    DisplayHelpText("Tryk ~INPUT_PICKUP~ for at samle din krykke op.")
                    if IsControlJustReleased(0, 38) then
                        SetCurrentPedWeapon(playerPed, unarmed, true)
                        LoadAnimDict("pickup_object")
                        TaskPlayAnim(playerPed, "pickup_object", "pickup_low", 2.0, 2.0, 1000, 0, 0, false, false, false)

                        local failCount = 0
                        while not IsEntityPlayingAnim(playerPed, "pickup_object", "pickup_low", 3) and failCount < 25 do
                            failCount = failCount + 1
                            Wait(40)
                        end

                        Wait(600)
                        RemoveAnimDict("pickup_object")

                        DeleteEntity(groundCrutchObject)
                        groundCrutchObject = nil

                        CreateCrutchObjectInHand()
                        trace = false
                        break
                    end
                end
            end
        end
    end
end

------------------------------------------------------------
-- Hovedfunktion: Få krykke
------------------------------------------------------------
function EquipCrutch()
    local canEquip, msg = CanPlayerEquipCrutch()
    if not canEquip then
        DisplayNotification(msg)
        return
    end

    -- Sæt gangstil
    LoadClipSet(clipSet)
    SetPedMovementClipset(PlayerPedId(), clipSet, 1.0)
    RemoveClipSet(clipSet)

    CreateCrutchObjectInHand()

    isUsingCrutch = true
    activeEquipment = "krykker"
    crutchOwner = GetPlayerServerId(PlayerId())

    if disableSprint then
        SetPlayerSprint(PlayerId(), false)
    end

    FrameThread()
    MainThread()

    -- Spor om vi har smidt krykken på jorden => giv muligheden at samle op
    CreateThread(function()
        while isUsingCrutch do
            if not crutchObject and groundCrutchObject then
                TraceGroundCrutch()
            end
            Wait(500)
        end
    end)
end

------------------------------------------------------------
-- 4) KØRESTOL-FUNKTIONER
------------------------------------------------------------
function EquipWheelchair(duration)
    ESX.ShowNotification('Du er nu udstyret med kørestol i ' .. duration .. ' minut(ter).')
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local groundZ = playerCoords.z

    local success, foundZ = GetGroundZFor_3dCoord(playerCoords.x, playerCoords.y, playerCoords.z + 5.0, 0)
    if success then
        groundZ = foundZ
    end

    local wheelchairModelHash = GetHashKey("iak_wheelchair")
    RequestModel(wheelchairModelHash)
    while not HasModelLoaded(wheelchairModelHash) do
        Wait(10)
    end

    local wheelchair = CreateVehicle(wheelchairModelHash, playerCoords.x, playerCoords.y, groundZ, GetEntityHeading(playerPed), true, false)
    TaskWarpPedIntoVehicle(playerPed, wheelchair, -1)
    
    -- Forhindr at spilleren bliver sparket ud af kørestolen ved kollisioner eller ragdoll
    SetPedCanBeKnockedOffVehicle(playerPed, false)
    -- Lås kørestolen, så ingen andre kan tage den
    SetVehicleDoorsLocked(wheelchair, 2)  -- 2 = låst for alle undtagen føreren

    activeEquipment = "kørestol"
    wheelchairActive = true
    currentWheelchair = wheelchair

    -- Bloker F (Exit) mens stolen er aktiv
    CreateThread(function()
        while wheelchairActive and DoesEntityExist(currentWheelchair) do
            DisableControlAction(0, 75, true)
            Wait(0)
        end
    end)
    
    -- Sørg for, at spilleren bliver i kørestolen, hvis de af en eller anden grund kommer ud
    CreateThread(function()
        while wheelchairActive and DoesEntityExist(currentWheelchair) do
            if GetVehiclePedIsIn(PlayerPedId(), false) ~= currentWheelchair then
                TaskWarpPedIntoVehicle(PlayerPedId(), currentWheelchair, -1)
            end
            Wait(100)
        end
    end)

    -- Fjern stolen efter X minutter
    SetTimeout(duration * 60000, function()
        if DoesEntityExist(currentWheelchair) then
            DeleteVehicle(currentWheelchair)
        end
        -- Giv spilleren lov til at blive sparket ud af køretøjer igen
        SetPedCanBeKnockedOffVehicle(playerPed, true)
        activeEquipment = nil
        wheelchairActive = false
        ESX.ShowNotification('Kørestolen er nu fjernet.')
    end)
end

RegisterNetEvent('ems:applyWheelchairTarget')
AddEventHandler('ems:applyWheelchairTarget', function(duration)
    EquipWheelchair(duration)
end)

RegisterNetEvent('ems:applyCrutchesTarget')
AddEventHandler('ems:applyCrutchesTarget', function(duration)
    ESX.ShowNotification('Du er nu udstyret med krykker i ' .. duration .. ' minut(ter).')
    EquipCrutch()
    SetTimeout(duration * 60000, function()
        if isUsingCrutch then
            UnequipCrutch()
            ESX.ShowNotification('Krykkerne er nu fjernet.')
        end
    end)
end)

------------------------------------------------------------
-- 5) NUI Callbacks
--   -> "chooseEquipment": 
--        * TriggerServerEvent('ems:applyEquipment', ... )
--   -> "closeMenu": 
--        * Bare luk menu, sæt fokus false.
------------------------------------------------------------
RegisterNUICallback('chooseEquipment', function(data, cb)
    local targetId = data.targetId
    local duration = data.duration
    local equipmentType = data.equipmentType

    TriggerServerEvent('ems:applyEquipment', equipmentType, targetId, duration)
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('closeMenu', function(_, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)
