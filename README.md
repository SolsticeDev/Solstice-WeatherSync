# Solstice-WeatherSync

Welcome to my version of qb-weather sync

Featuring full real weather and time by using 2 different api to pull weather and timezone information from the real world and implement this into your server, also sends a notification every 5mins (can be changed) that will display the current time and current weather forecast

Fully rewritten serverside code of weather sync to accomplish this while keeping all exports of the original intact so this will drag and drop into any qbcore server after setting api keys

Both api used here can be found below 

Go here to get weather api key - https://openweathermap.org/

Go here for timezone api key - https://timezonedb.com/

Both api keys will be required for this script to work

0.03 ms idle (mainly for the api http requests)

# Install Guide

replace your qb-weathersync with mine

open the server.lua you will see this at the top

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

install your api keys here

if you need any help with this open a ticket in the discord https://discord.gg/6uUJvRukhD

# Known Issues
If you encounter any other bugs please join my discord and tell me
I will be updating and maintaing this script

-Sun and moon stuttering
-time updates could look better
-Self updating time so time doesnt update with every notification interval
