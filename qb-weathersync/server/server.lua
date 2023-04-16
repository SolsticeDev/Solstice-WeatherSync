local QBCore = exports['qb-core']:GetCoreObject()
local CurrentWeather = Config.StartWeather
local baseTime = Config.BaseTime
local timeOffset = Config.TimeOffset
local freezeTime = Config.FreezeTime
local blackout = Config.Blackout
local newWeatherTimer = Config.NewWeatherTimer
local OpenWeatherAPIKey = "YOUR_OPEN_WEATHER_API_KEY" --can get free key here https://openweathermap.org/
local WeatherAPIUrl = "http://api.openweathermap.org/data/2.5/weather?q=Los%20Angeles&appid=" .. OpenWeatherAPIKey .. "&units=imperial" --Modify to your open weathermaps api key here 
local WeatherNotificationInterval = 5 * 60 * 1000 -- 2 minutes in milliseconds (how often the weather update with notification will be)
local TimeZoneDBAPIKey = "YOUR_TIMEZONE_DB_API_KEY" --can get free key here https://timezonedb.com/
local TimeZoneDBAPIUrl = "http://api.timezonedb.com/v2.1/get-time-zone?key=" .. TimeZoneDBAPIKey .. "&format=json&by=zone&zone=America/Los_Angeles"

local function fetchWeatherData(callback)
    PerformHttpRequest(WeatherAPIUrl, function(statusCode, data, headers)
        if statusCode == 200 then
            local weatherData = json.decode(data)
            callback(weatherData)
        else
            print("Error fetching weather data: " .. statusCode)
            callback(nil)
        end
    end, "GET", "", {})
end

local function convertToEasternTime(time)
    local easternTime = time - (5 * 60 * 60) -- Subtract 5 hours in seconds (for EST)
    if easternTime < 0 then
        easternTime = easternTime + (24 * 60 * 60) -- If the result is negative, add 24 hours in seconds
    end
    return easternTime
end

--- Is the source a client or the server
--- @param src string | number - source to check
--- @return int - source
local function getSource(src)
    if src == '' then
        return 0
    end
    return src
end

--- Does source have permissions to run admin commands
--- @param src number - Source to check
--- @return boolean - has permission
local function isAllowedToChange(src)
    if src == 0 or QBCore.Functions.HasPermission(src, "admin") or IsPlayerAceAllowed(src, 'command') then
        return true
    end
    return false
end

--- Sets time offset based on minutes provided
--- @param minute number - Minutes to offset by
local function shiftToMinute(minute)
    timeOffset = timeOffset - (((baseTime + timeOffset) % 60) - minute)
end

--- Sets time offset based on hour provided
--- @param hour number - Hour to offset by
local function shiftToHour(hour)
    timeOffset = timeOffset - ((((baseTime + timeOffset) / 60) % 24) - hour) * 60
end

--- Triggers event to switch weather to next stage
local function nextWeatherStage()
    fetchWeatherData(function(weatherData)
        if weatherData then
            local weatherId = weatherData.weather[1].id

            if weatherId >= 200 and weatherId <= 232 then
                CurrentWeather = "THUNDER"
            elseif weatherId >= 300 and weatherId <= 321 then
                CurrentWeather = "RAIN" -- Drizzle will be treated as light rain
            elseif weatherId >= 500 and weatherId <= 531 then
                CurrentWeather = "RAIN"
            elseif weatherId >= 600 and weatherId <= 622 then
                CurrentWeather = "SNOW"
                if weatherId >= 620 then
                    CurrentWeather = "SNOWLIGHT"
                end
            elseif weatherId >= 701 and weatherId <= 741 then
                CurrentWeather = "FOGGY"
            elseif weatherId == 741 then
                CurrentWeather = "SMOG"
            elseif weatherId == 800 then
                CurrentWeather = "EXTRASUNNY"
            elseif weatherId == 801 then
                CurrentWeather = "CLEAR"
            elseif weatherId == 802 then
                CurrentWeather = "CLOUDS"
            elseif weatherId == 803 or weatherId == 804 then
                CurrentWeather = "OVERCAST"
            else
                CurrentWeather = "NEUTRAL"
            end

            -- Additional weather types not based on weatherId
            local temperature = weatherData.main.temp
            local windSpeed = weatherData.wind.speed

            if CurrentWeather == "SNOW" and windSpeed >= 10 then
                CurrentWeather = "BLIZZARD"
            end

            if CurrentWeather == "RAIN" and temperature >= 10 and windSpeed >= 8 then
                CurrentWeather = "CLEARING"
            end

            TriggerEvent("qb-weathersync:server:RequestStateSync")
        end
    end)
end

--- Sets sun position based on time to specified
--- @param hour number|string - Hour to set (0-24)
--- @param minute number|string `optional` - Minute to set (0-60)
--- @return boolean - success
local function setTime(hour, minute)
    local argh = tonumber(hour)
    local argm = tonumber(minute) or 0
    if argh == nil or argh > 24 then
        print(Lang:t('time.invalid'))
        return false
    end
    shiftToHour((argh < 24) and argh or 0)
    shiftToMinute((argm < 60) and argm or 0)
    print(Lang:t('time.change', {value = argh, value2 = argm}))
    TriggerEvent('qb-weathersync:server:RequestStateSync')
    return true
end

local function getLocalTime(callback)
    if Config.UseRealTime then
        PerformHttpRequest(TimeZoneDBAPIUrl, function(statusCode, data, headers)
            if statusCode == 200 then
                local timeData = json.decode(data)
                local localHour = os.date("%H", timeData.timestamp) -- Get the hour in 24-hour format
                local localMinute = os.date("%M", timeData.timestamp) -- Get the minute
                callback(localHour, localMinute)
                setTime(localHour, localMinute) -- Update the in-game time
            else
                print("Error fetching time data: " .. statusCode)
                callback(nil)
            end
        end, "GET", "", {})
    else
        local localHour = os.date("%H")
        local localMinute = os.date("%M")
        callback(localHour, localMinute)
        setTime(localHour, localMinute) -- Update the in-game time
    end
end

local function sendWeatherNotification()
    fetchWeatherData(function(weatherData)
        if weatherData then
            local weatherDescription = weatherData.weather[1].description
            local temperature = math.floor(weatherData.main.temp)

            getLocalTime(function(currentHour, currentMinute)
                if currentHour and currentMinute then
                    for _, playerId in ipairs(GetPlayers()) do
                        TriggerClientEvent("QBCore:Notify", tonumber(playerId), "Weather: " .. weatherDescription .. ", Temperature: " .. temperature .. "°F, Current LA Time: " .. currentHour .. ":" .. currentMinute)
                    end
                else
                    print("Error: Could not fetch current time from TimeZoneDB API.")
                end
            end)
        end
    end)
end

--- Switch to a specified weather type
--- @param weather string - Weather type from Config.AvailableWeatherTypes
--- @return boolean - success
local function setWeather(weather)
    local validWeatherType = false
    for _, weatherType in pairs(Config.AvailableWeatherTypes) do
        if weatherType == string.upper(weather) then
            validWeatherType = true
        end
    end
    if not validWeatherType then return false end
    CurrentWeather = string.upper(weather)
    newWeatherTimer = Config.NewWeatherTimer
    TriggerEvent('qb-weathersync:server:RequestStateSync')
    return true
end



--- Sets or toggles blackout state and returns the state
--- @param state boolean `optional` - enable blackout?
--- @return boolean - blackout state
local function setBlackout(state)
    if state == nil then state = not blackout end
    if state then blackout = true
    else blackout = false end
    TriggerEvent('qb-weathersync:server:RequestStateSync')
    return blackout
end

--- Sets or toggles time freeze state and returns the state
--- @param state boolean `optional` - Enable time freeze?
--- @return boolean - Time freeze state
local function setTimeFreeze(state)
    if state == nil then state = not freezeTime end
    if state then freezeTime = true
    else freezeTime = false end
    TriggerEvent('qb-weathersync:server:RequestStateSync')
    return freezeTime
end

--- Sets or toggles dynamic weather state and returns the state
--- @param state boolean `optional` - Enable dynamic weather?
--- @return boolean - Dynamic Weather state
local function setDynamicWeather(state)
    if state == nil then state = not Config.DynamicWeather end
    if state then Config.DynamicWeather = true
    else Config.DynamicWeather = false end
    TriggerEvent('qb-weathersync:server:RequestStateSync')
    return Config.DynamicWeather
end

-- EVENTS
RegisterNetEvent('qb-weathersync:server:RequestStateSync', function()
    TriggerClientEvent('qb-weathersync:client:SyncWeather', -1, CurrentWeather, blackout)
    TriggerClientEvent('qb-weathersync:client:SyncTime', -1, baseTime, timeOffset, freezeTime)
end)

RegisterNetEvent('qb-weathersync:server:setWeather', function(weather)
    local src = getSource(source)
    if isAllowedToChange(src) then
        local success = setWeather(weather)
        if src > 0 then
            if (success) then TriggerClientEvent('QBCore:Notify', src, Lang:t('weather.updated'))
            else TriggerClientEvent('QBCore:Notify', src, Lang:t('weather.invalid'))
            end
        end
    end
end)

RegisterNetEvent('qb-weathersync:server:setTime', function(hour, minute)
    local src = getSource(source)
    if isAllowedToChange(src) then
        local success = setTime(hour, minute)
        if src > 0 then
            if (success) then TriggerClientEvent('QBCore:Notify', src, Lang:t('time.change', {value = hour, value2 = minute or "00"}))
            else TriggerClientEvent('QBCore:Notify', src, Lang:t('time.invalid'))
            end
        end
    end
end)

RegisterNetEvent('qb-weathersync:server:toggleBlackout', function(state)
    local src = getSource(source)
    if isAllowedToChange(src) then
        local newstate = setBlackout(state)
        if src > 0 then
            if (newstate) then TriggerClientEvent('QBCore:Notify', src, Lang:t('blackout.enabled'))
            else TriggerClientEvent('QBCore:Notify', src, Lang:t('blackout.disabled'))
            end
        end
    end
end)

RegisterNetEvent('qb-weathersync:server:toggleFreezeTime', function(state)
    local src = getSource(source)
    if isAllowedToChange(src) then
        local newstate = setTimeFreeze(state)
        if src > 0 then
            if (newstate) then TriggerClientEvent('QBCore:Notify', src, Lang:t('time.now_frozen'))
            else TriggerClientEvent('QBCore:Notify', src, Lang:t('time.now_unfrozen'))
            end
        end
    end
end)

RegisterNetEvent('qb-weathersync:server:toggleDynamicWeather', function(state)
    local src = getSource(source)
    if isAllowedToChange(src) then
        local newstate = setDynamicWeather(state)
        if src > 0 then
            if (newstate) then TriggerClientEvent('QBCore:Notify', src, Lang:t('weather.now_unfrozen'))
            else TriggerClientEvent('QBCore:Notify', src, Lang:t('weather.now_frozen'))
            end
        end
    end
end)

-- COMMANDS
QBCore.Commands.Add('freezetime', Lang:t('help.freezecommand'), {}, false, function(source)
    local newstate = setTimeFreeze()
    if source > 0 then
        if (newstate) then return TriggerClientEvent('QBCore:Notify', source, Lang:t('time.frozenc')) end
        return TriggerClientEvent('QBCore:Notify', source, Lang:t('time.unfrozenc'))
    end
    if (newstate) then return print(Lang:t('time.now_frozen')) end
    return print(Lang:t('time.now_unfrozen'))
end, 'admin')

QBCore.Commands.Add('freezeweather', Lang:t('help.freezeweathercommand'), {}, false, function(source)
    local newstate = setDynamicWeather()
    if source > 0 then
        if (newstate) then return TriggerClientEvent('QBCore:Notify', source, Lang:t('dynamic_weather.enabled')) end
        return TriggerClientEvent('QBCore:Notify', source, Lang:t('dynamic_weather.disabled'))
    end
    if (newstate) then return print(Lang:t('weather.now_unfrozen')) end
    return print(Lang:t('weather.now_frozen'))
end, 'admin')

QBCore.Commands.Add('weather', Lang:t('help.weathercommand'), {{name = Lang:t('help.weathertype'), help = Lang:t('help.availableweather')}}, true, function(source, args)
    local success = setWeather(args[1])
    if source > 0 then
        if (success) then return TriggerClientEvent('QBCore:Notify', source, Lang:t('weather.willchangeto', {value = string.lower(args[1])})) end
        return TriggerClientEvent('QBCore:Notify', source, Lang:t('weather.invalidc'), 'error')
    end
    if (success) then return print(Lang:t('weather.updated')) end
    return print(Lang:t('weather.invalid'))
end, 'admin')

QBCore.Commands.Add('blackout', Lang:t('help.blackoutcommand'), {}, false, function(source)
    local newstate = setBlackout()
    if source > 0 then
        if (newstate) then return TriggerClientEvent('QBCore:Notify', source, Lang:t('blackout.enabledc')) end
        return TriggerClientEvent('QBCore:Notify', source, Lang:t('blackout.disabledc'))
    end
    if (newstate) then return print(Lang:t('blackout.enabled')) end
    return print(Lang:t('blackout.disabled'))
end, 'admin')

QBCore.Commands.Add('morning', Lang:t('help.morningcommand'), {}, false, function(source)
    setTime(9, 0)
    if source > 0 then return TriggerClientEvent('QBCore:Notify', source, Lang:t('time.morning')) end
end, 'admin')

QBCore.Commands.Add('noon', Lang:t('help.nooncommand'), {}, false, function(source)
    setTime(12, 0)
    if source > 0 then return TriggerClientEvent('QBCore:Notify', source, Lang:t('time.noon')) end
end, 'admin')

QBCore.Commands.Add('evening', Lang:t('help.eveningcommand'), {}, false, function(source)
    setTime(18, 0)
    if source > 0 then return TriggerClientEvent('QBCore:Notify', source, Lang:t('time.evening')) end
end, 'admin')

QBCore.Commands.Add('night', Lang:t('help.nightcommand'), {}, false, function(source)
    setTime(23, 0)
    if source > 0 then return TriggerClientEvent('QBCore:Notify', source, Lang:t('time.night')) end
end, 'admin')

QBCore.Commands.Add('time', Lang:t('help.timecommand'), {{ name=Lang:t('help.timehname'), help=Lang:t('help.timeh') }, { name=Lang:t('help.timemname'), help=Lang:t('help.timem') }}, true, function(source, args)
    local success = setTime(args[1], args[2])
    if source > 0 then
        if (success) then return TriggerClientEvent('QBCore:Notify', source, Lang:t('time.changec', {value = args[1] .. ':' .. (args[2] or "00")})) end
        return TriggerClientEvent('QBCore:Notify', source, Lang:t('time.invalidc'), 'error')
    end
    if (success) then return print(Lang:t('time.change', {value = args[1], value2 = args[2] or "00"})) end
    return print(Lang:t('time.invalid'))
end, 'admin')

-- THREAD LOOPS
CreateThread(function()
    local previous = 0
    while true do
        Wait(0)
        local newBaseTime = convertToEasternTime(os.time(os.date("!*t"))) / 2 + 360
        if (newBaseTime % 60) ~= previous then --Check if a new minute is passed
            previous = newBaseTime % 60 --Only update time with plain minutes, seconds are handled in the client
            if freezeTime then
                timeOffset = timeOffset + baseTime - newBaseTime
            end
            baseTime = newBaseTime
        end
    end
end)

CreateThread(function()
    while true do
        Wait(2000)--Change to send every minute in game sync
        TriggerClientEvent('qb-weathersync:client:SyncTime', -1, baseTime, timeOffset, freezeTime)
    end
end)

CreateThread(function()
    while true do
        Wait(300000)
        TriggerClientEvent('qb-weathersync:client:SyncWeather', -1, CurrentWeather, blackout)
    end
end)

CreateThread(function()
    while true do
        Wait(WeatherNotificationInterval)
        nextWeatherStage()
        sendWeatherNotification()
    end
end)

AddEventHandler('onResourceStart', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then
      return
    end
    Wait(10000)
    nextWeatherStage()
    sendWeatherNotification()
  end)
  

-- EXPORTS
exports('nextWeatherStage', nextWeatherStage)
exports('setWeather', setWeather)
exports('setTime', setTime)
exports('setBlackout', setBlackout)
exports('setTimeFreeze', setTimeFreeze)
exports('setDynamicWeather', setDynamicWeather)
exports('getBlackoutState', function() return blackout end)
exports('getTimeFreezeState', function() return freezeTime end)
exports('getWeatherState', function() return CurrentWeather end)
exports('getDynamicWeather', function() return Config.DynamicWeather end)

exports('getTime', function()
    local hour = math.floor(((baseTime+timeOffset)/60)%24)
    local minute = math.floor((baseTime+timeOffset)%60)

    return hour,minute
end)
