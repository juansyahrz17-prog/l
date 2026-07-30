local cloneref = cloneref or function(x) return x end

local game = cloneref(game)
local http_service = cloneref(game:GetService("HttpService"))
local players = cloneref(game:GetService("Players"))
local starter_gui = cloneref(game:GetService("StarterGui"))

--// Types
type loader_config = {
    name: string,
    url: string,
    version: string?,
    author: string?,
}

--// Game Loaders
local ___loaders: { [number]: loader_config } = {
    [6701277882] = {
        name = "fish it",
        url = "https://luaegis.net/scripts/v4/loaders/5825dfde-5490-47f1-9af0-9da0ad0a7cb5.lua",
        version = "1.0.0",
        author = "Andra",
    },

    [10200395747] = {
        name = "grow-a-garden2",
        url = "https://luaegis.net/scripts/v4/loaders/4beed4ad-c904-4b0e-a96b-adc3f88965f5.lua",
        version = "0.0.1",
        author = "Andra",
    },
}

--// Universal Loader (Fallback)
local UNIVERSAL_LOADER: loader_config = {
    name = "Universal",
    url = "https://luaegis.net/scripts/v4/loaders/f7a5c212-de02-4a28-8c5a-b4cdad31710a.lua",
    version = "1.0.0",
    author = "Andra",
}

--// Notify
local function __notify(title: string, text: string)
    pcall(function()
        starter_gui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = 5,
        })
    end)
end

--// Load Script
local function __load_script(url: string): boolean
    local success, result = pcall(function()
        local script_content = game:HttpGet(url)
        local loaded_function = loadstring(script_content)

        assert(loaded_function, "failed to compile script")
        loaded_function()
    end)

    if not success then
        warn("[Loader] Failed:", result)
        __notify("Vora Loader", "Failed to load script.")
        return false
    end

    return true
end

--// Main
local place_id = game.PlaceId
local universe_id = game.GameId

local loader_config =
    ___loaders[place_id]
    or ___loaders[universe_id]
    or UNIVERSAL_LOADER

if loader_config == UNIVERSAL_LOADER then
    warn("[Loader] No game-specific loader found. Loading Universal.")
    __notify("Vora Loader", "Loading Universal Loader...")
else
    warn(("[Loader] Loading %s (%s)"):format(loader_config.name, loader_config.version or "Unknown"))
    __notify("Vora Loader", "Loading " .. loader_config.name)
end

__load_script(loader_config.url)
