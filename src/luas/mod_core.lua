mods = {}

balamodLoaded = false

RESULT = {
    SUCCESS = 0,
    MOD_NOT_FOUND_IN_REPOS = 1,
    MOD_NOT_FOUND_IN_MODS = 2,
    MOD_ALREADY_PRESENT = 3,
    NETWORK_ERROR = 4,
    MOD_FS_LOAD_ERROR = 5,
    MOD_PCALL_ERROR = 6,
}

if (sendDebugMessage == nil) then
    sendDebugMessage = function(_)
    end
end

if not love.filesystem.getInfo("mods", "directory") then -- Create mods folder if it doesn't exist
    love.filesystem.createDirectory("mods")
end

if not love.filesystem.getInfo("apis", "directory") then -- Create apis folder if it doesn't exist
    love.filesystem.createDirectory("apis")
end

paths = {
    {paths}
} -- Paths to the files that will be loaded
-- current_game_code = love.filesystem.read(path)
current_game_code = {}
for _, path in ipairs(paths) do
    current_game_code[path] = love.filesystem.read(path)
end

function extractFunctionBody(path, function_name)
    local pattern = "\n?%s*function%s+" .. function_name
    local func_begin, fin = current_game_code[path]:find(pattern)

    if not func_begin then
        return "Can't find function begin " .. function_name
    end

    local func_end = current_game_code[path]:find("\n\r?end", fin)

    -- This is to catch functions that have incorrect ending indentation by catching the next function in line.
    -- Can be removed once Card:calculate_joker no longer has this typo.
    local typocatch_func_end = current_game_code[path]:find("\n\r?function", fin)
    if typocatch_func_end and typocatch_func_end < func_end then
        func_end = typocatch_func_end - 3
    end

    if not func_end then
        return "Can't find function end " .. function_name
    end

    local func_body = current_game_code[path]:sub(func_begin, func_end + 3)
    return func_body
end

function inject(path, function_name, to_replace, replacement)
    -- Injects code into a function (replaces a string with another string inside a function)
    local function_body = extractFunctionBody(path, function_name)
    local modified_function_code = function_body:gsub(to_replace, replacement)
    escaped_function_body = function_body:gsub("([^%w])", "%%%1") -- escape function body for use in gsub
    escaped_modified_function_code = modified_function_code:gsub("([^%w])", "%%%1")
    current_game_code[path] = current_game_code[path]:gsub(escaped_function_body, escaped_modified_function_code) -- update current game code in memory

    local new_function, load_error = load(modified_function_code) -- load modified function
    if not new_function then
        -- Safeguard against errors, will be logged in %appdata%/Balatro/err1.txt
        love.filesystem.write("err1.txt", "Error loading modified function: " .. (load_error or "Unknown error"))
    end

    if setfenv then
        setfenv(new_function, getfenv(original_testFunction))
    end -- Set the environment of the new function to the same as the original function

    local status, result = pcall(new_function) -- Execute the new function
    if status then
        testFunction = result -- Overwrite the original function with the result of the new function
    else
        love.filesystem.write("err2.txt", "Error executing modified function: " .. result) -- Safeguard against errors, will be logged in %appdata%/Balatro/err2.txt
    end
end

function injectHead(path, function_name, code)
    local function_body = extractFunctionBody(path, function_name)

    local pattern = "(function%s+" .. function_name .. ".-)\n"
    local modified_function_code, number_of_subs = function_body:gsub(pattern, "%1\n" .. code .. "\n")

    if number_of_subs == 0 then
        love.filesystem.write("err4.txt", "Error: Function start not found in function body or multiple matches encountered.")
        return
    end

    escaped_function_body = function_body:gsub("([^%w])", "%%%1")
    escaped_modified_function_code = modified_function_code:gsub("([^%w])", "%%%1")
    current_game_code[path] = current_game_code[path]:gsub(escaped_function_body, escaped_modified_function_code)

    local new_function, load_error = load(modified_function_code)
    if not new_function then
        love.filesystem.write("err1.txt", "Error loading modified function with head injection: " .. (load_error or "Unknown error"))
        return
    end

    if setfenv then
        setfenv(new_function, getfenv(original_testFunction))
    end

    local status, result = pcall(new_function)
    if status then
        testFunction = result
    else
        love.filesystem.write("err2.txt", "Error executing modified function with head injection: " .. result)
    end
end

function injectTail(path, function_name, code)
    local function_body = extractFunctionBody(path, function_name)

    local pattern = "(.-)(end[ \t]*\n?)$"
    local modified_function_code, number_of_subs = function_body:gsub(pattern, "%1" .. code .. "%2")

    if number_of_subs == 0 then
        love.filesystem.write("err3.txt", "Error: 'end' not found in function body or multiple ends encountered.")
        return
    end

    escaped_function_body = function_body:gsub("([^%w])", "%%%1")
    escaped_modified_function_code = modified_function_code:gsub("([^%w])", "%%%1")
    current_game_code[path] = current_game_code[path]:gsub(escaped_function_body, escaped_modified_function_code)

    local new_function, load_error = load(modified_function_code)
    if not new_function then
        love.filesystem.write("err1.txt", "Error loading modified function with tail injection: " .. (load_error or "Unknown error"))
        return
    end

    if setfenv then
        setfenv(new_function, getfenv(original_testFunction))
    end

    local status, result = pcall(new_function)
    if status then
        testFunction = result
    else
        love.filesystem.write("err2.txt", "Error executing modified function with tail injection: " .. result)
    end
end

local function processDirectory(directory, depth)
    if depth > 2 then
        return
    end

    for _, filename in ipairs(love.filesystem.getDirectoryItems(directory)) do
        local filePath = directory .. "/" .. filename
        if love.filesystem.getInfo(filePath).type == "directory" then
            processDirectory(filePath, depth + 1)
        elseif filename:match("%.lua$") then -- Only load lua files
            local modContent, loadErr = love.filesystem.load(filePath) -- Load the file

            if modContent then  -- Check if the file was loaded successfully
                local success, mod = pcall(modContent) -- Execute the file
                if success and mod == nil then
                    table.insert(mods, mod) -- Add the mod to the list of mods
                elseif mod == nil then
                    print("Error loading mod: " .. filePath .. "\n" .. mod) -- Log the error to the console Todo: Log to file
                end
            else
                print("Error reading mod: " .. filePath .. "\n" .. loadErr) -- Log the error to the console Todo: Log to file
            end
        end
    end
end

-- apis will be loaded first, then mods
processDirectory("apis", 1)
processDirectory("mods", 1)

for _, mod in ipairs(mods) do
	if mod.enabled and mod.on_pre_load and type(mod.on_pre_load) == "function" then
		pcall(mod.on_pre_load) -- Call the on_pre_load function of the mod if it exists
	end
end

repoMods = {}

function getModByModId(tables, mod_id)
    for _, mod in ipairs(tables) do
        if mod.mod_id and mod.mod_id == mod_id then
            return mod
        end
    end
    sendDebugMessage('Mod ' .. mod_id .. ' not found')
    return nil
end

function isModPresent(modId)
    if getModByModId(mods, modId) then
        return true
    else
        return false
    end
end

function installMod(modId)
    local modInfo = getModByModId(repoMods, modId)
    if modInfo == nil then
        sendDebugMessage('Mod ' .. modId .. ' not found in repos')
        return RESULT.MOD_NOT_FOUND_IN_REPOS
    end

    local isModPresent = isModPresent(modId)
    if isModPresent then
        sendDebugMessage('Mod ' .. modId .. ' is already present')
        local modVersion = modInfo.version
        local skipUpdate = false
        for _, mod in ipairs(mods) do
            if mod.mod_id == modId then
                if mod.version then
                    if mod.version == modVersion then
                        sendDebugMessage('Mod ' .. modId .. ' is up to date')
                        skipUpdate = true
                        break
                    else
                        sendDebugMessage('Mod ' .. modId .. ' is outdated')
                        sendDebugMessage('Updating mod ' .. modId)
                    end
                else
                    sendDebugMessage('Mod ' .. modId .. ' is up to date')
                    skipUpdate = true
                    break
                end
            end
        end
        if skipUpdate then
            return RESULT.SUCCESS
        end

        -- remove old mod
        for i, mod in ipairs(mods) do
            if mod.mod_id == modId then
                if mod.on_disable then
                    mod.on_disable()
                end

                table.remove(mods, i)
                break
            end
        end
    end

    sendDebugMessage('Downloading mod ' .. modId)
    local modUrl = modInfo.url

    local owner, repo, branch, path = modUrl:match('https://github%.com/([^/]+)/([^/]+)/(tree/blob)/([^/]+)/(.*)')

    if path == nil then
        owner, repo, branch, path = modUrl:match('https://github%.com/([^/]+)/([^/]+)/blob/([^/]+)/(.*)')
    end

    if path == nil then
        owner, repo, branch, path = modUrl:match('https://github%.com/([^/]+)/([^/]+)/tree/([^/]+)/(.*)')
    end

    while path:sub(-1) == '/' do
        path = path:sub(1, -2)
    end

    sendDebugMessage('Owner: ' .. owner)
    sendDebugMessage('Repo: ' .. repo)
    sendDebugMessage('Branch: ' .. branch)
    sendDebugMessage('Path: ' .. path)

    local https = require 'https'
    local headers = {
        ['User-Agent'] = 'Balamod/1.0'
    }
    local url = 'https://api.github.com/repos/' .. owner .. '/' .. repo .. '/git/trees/' .. branch .. '?recursive=1'
    local code, body = https.request(url, {headers = headers})
    if code ~= 200 then
        sendDebugMessage('Request failed')
        sendDebugMessage('Code: ' .. code)
        sendDebugMessage('Response: ' .. body)
        return RESULT.NETWORK_ERROR
    end

    sendDebugMessage('Files to download:')

    local paths = {}

    for p, type in body:gmatch('"path":"(.-)".-"type":"(.-)"') do
        if type == 'blob' then
            if p:sub(1, #path) == path then
                table.insert(paths, p)
            end
        end
    end

    for _, p in ipairs(paths) do
        sendDebugMessage(p)
    end

    for _, p in ipairs(paths) do
        code, body = https.request(
                         'https://raw.githubusercontent.com/' .. owner .. '/' .. repo .. '/' .. branch .. '/' .. p)
        if code ~= 200 then
            sendDebugMessage('Request failed')
            sendDebugMessage('Code: ' .. code)
            sendDebugMessage('Response: ' .. body)
            return RESULT.NETWORK_ERROR
        end
        sendDebugMessage('Downloaded ' .. p)
        local filePath = p:sub(#path + 2)
        sendDebugMessage('Writing to ' .. filePath)
        local dir = filePath:match('(.+)/[^/]+')
        love.filesystem.createDirectory(dir)
        --[[if not love.filesystem.getInfo(filePath) then
            love.filesystem.write(filePath, body)
        else
            sendDebugMessage("File " .. filePath .. " already exists")
        end]] --
        love.filesystem.write(filePath, body)
    end

    -- apis first
    for _, p in ipairs(paths) do
        if p:match('apis/.*%.lua') then
            sendDebugMessage('Loading ' .. p:sub(#path + 2))

            local modContent, loadErr = love.filesystem.load(p:sub(#path + 2))

            if modContent then
                local success, mod = pcall(modContent)
                if success then
                    sendDebugMessage('API ' .. p:sub(#path + 2) .. ' loaded')
                else
                    print('Error loading api: ' .. p:sub(#path + 2) .. '\n' .. mod)
                    return RESULT.MOD_PCALL_ERROR
                end
            else
                print('Error reading api: ' .. p:sub(#path + 2) .. '\n' .. loadErr)
                return RESULT.MOD_FS_LOAD_ERROR
            end
        end
    end

    -- mods second
    for _, p in ipairs(paths) do
        if p:match('mods/.*%.lua') then
            sendDebugMessage('Loading ' .. p:sub(#path + 2))

            local modContent, loadErr = love.filesystem.load(p:sub(#path + 2))

            if modContent then
                local success, mod = pcall(modContent)
                if success and mod == nil then
                    table.insert(mods, mod)
                    sendDebugMessage('Mod ' .. p:sub(#path + 2) .. ' loaded')
                elseif mod == nil then
                    print('Error loading mod: ' .. p:sub(#path + 2) .. '\n' .. mod)
                    return RESULT.MOD_PCALL_ERROR
                end
            else
                print('Error reading mod: ' .. p:sub(#path + 2) .. '\n' .. loadErr)
                return RESULT.MOD_FS_LOAD_ERROR
            end
        end
    end

    local installed = getModByModId(mods, modId)
    if installed and installed.enabled and installed.on_enable and type(installed.on_enable) == 'function' then
        pcall(installed.on_enable)
    end

    return RESULT.SUCCESS
end

function refreshRepos()
    local reposIndex = 'https://raw.githubusercontent.com/UwUDev/balamod/master/repos.index'
    local https = require 'https'
    local code, body = https.request(reposIndex)

    if code ~= 200 then
        sendDebugMessage('Request failed')
        sendDebugMessage('Code: ' .. code)
        sendDebugMessage('Response: ' .. body)
        return RESULT.NETWORK_ERROR
    end

    for repoUrl in string.gmatch(body, '([^\n]+)') do
        sendDebugMessage('Refreshing ' .. repoUrl)
        if refreshRepo(repoUrl) ~= RESULT.SUCCESS then
            return RESULT.NETWORK_ERROR
        end
        sendDebugMessage('Refreshed ' .. repoUrl)
    end
    return RESULT.SUCCESS
end

function refreshRepo(url)
    local https = require 'https'
    local code, body = https.request(url)

    if code ~= 200 then
        sendDebugMessage('Request failed')
        sendDebugMessage('Code: ' .. code)
        sendDebugMessage('Response: ' .. body)
        return RESULT.NETWORK_ERROR
    end

    -- clear repoMods
    repoMods = {}
    for modInfo in string.gmatch(body, '([^\n]+)') do
        local modId, modVersion, modName, modDesc, modUrl = string.match(modInfo,
                                                                         '([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)')
        table.insert(repoMods, {
            mod_id = modId, 
            name = modName, 
            description = modDesc, 
            url = modUrl, 
            version = modVersion
        })
    end

    sendDebugMessage('Mods available:')
    for i, modInfo in pairs(repoMods) do
        local modId = modInfo.mod_id
        local isModPresent = isModPresent(modId)
        sendDebugMessage(modId .. ' - ' .. modInfo.name .. ' - ' .. modInfo.version .. ' - ' .. modInfo.description .. ' - ' .. tostring(isModPresent))
    end
    return RESULT.SUCCESS
end
