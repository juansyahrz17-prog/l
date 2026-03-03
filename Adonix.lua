-- Adonis bypass
local getinfo = getinfo or debug.getinfo
local DEBUG = false
setthreadidentity(2)
for _, v in getgc(true) do
    if typeof(v) == "table" then
        local DetectFunc = rawget(v, "Detected")
        local KillFunc = rawget(v, "Kill")
    
        if typeof(DetectFunc) == "function" then
            hookfunction(DetectFunc, function(Action, Info, NoCrash)
                if Action ~= "_" and DEBUG then
                    warn("Adonis flag bypassed: " .. tostring(Action))
                end
                return true
            end)
        end
    
        if typeof(KillFunc) == "function" then
            hookfunction(KillFunc, function(Info)
                if DEBUG then warn("Adonis kick bypassed: " .. tostring(Info)) end
            end)
        end
    end
end
hookfunction(getrenv().debug.info or debug.getinfo, newcclosure(function(...)
    if (...) == "Detected" then
        return coroutine.yield(coroutine.running())
    end
    return debug.info(...)
end))
setthreadidentity(7)
