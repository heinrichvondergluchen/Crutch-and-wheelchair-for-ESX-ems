ESX = exports['es_extended']:getSharedObject()

-- Gemmer hvornår en spiller er "fri" for udstyr igen
--   activeTimers[playerId] = tidsstempel (sekunder) for hvornår spillerens udstyrs-tid er udløbet
local activeTimers = {}

-- Hjælpefunktion: Returnerer current server-tid i sekunder siden serverstart
-- (Du kan også bruge os.time(), men her bruger vi GetGameTimer() for at være uafhængig af system-uret.)
local function nowInSeconds()
    return math.floor(GetGameTimer() / 1000)
end

-- Fjern en spiller fra activeTimers, når de forlader serveren (valgfrit)
AddEventHandler('playerDropped', function(reason)
    local src = source
    if activeTimers[src] then
        activeTimers[src] = nil
    end
end)

RegisterServerEvent('ems:applyEquipment')
AddEventHandler('ems:applyEquipment', function(equipmentType, targetId, duration)
    local _source = source
    local xPlayer = ESX.GetPlayerFromId(_source)
    
    if xPlayer and xPlayer.job and xPlayer.job.name == 'ambulance' then
        if duration > 10 then duration = 10 end

        local currentTime = nowInSeconds()

        -- Check om target allerede har (eller lige har haft) udstyr
        if activeTimers[targetId] and activeTimers[targetId] > currentTime then
            -- Tiden er ikke udløbet endnu => de har "stadig" udstyr
            TriggerClientEvent('esx:showNotification', _source, 'Denne spiller har allerede udstyr, eller tiden er ikke udløbet endnu.')
            return
        end

        -- Ellers sæt ny "slut-tid"
        local endTime = currentTime + (duration * 60)
        activeTimers[targetId] = endTime

        -- Udstyr
        if equipmentType == 'krykker' then
            TriggerClientEvent('ems:applyCrutchesTarget', targetId, duration)
            TriggerClientEvent('esx:showNotification', _source, 'Du har udstyret personen med krykker i ' .. duration .. ' minut(ter).')
        elseif equipmentType == 'kørestol' then
            TriggerClientEvent('ems:applyWheelchairTarget', targetId, duration)
            TriggerClientEvent('esx:showNotification', _source, 'Du har udstyret personen med kørestol i ' .. duration .. ' minut(ter).')
        else
            TriggerClientEvent('esx:showNotification', _source, 'Ugyldigt udstyr.')
        end
    else
        TriggerClientEvent('esx:showNotification', _source, 'Du har ikke adgang til dette.')
    end
end)

ESX.RegisterServerCallback('ems:getNearbyIdentities', function(source, cb, playerIds)
    local players = {}
    for i = 1, #playerIds do
        local xPlayer = ESX.GetPlayerFromId(playerIds[i])
        if xPlayer then
            table.insert(players, { id = xPlayer.source, name = xPlayer.getName() })
        end
    end
    cb(players)
end)
