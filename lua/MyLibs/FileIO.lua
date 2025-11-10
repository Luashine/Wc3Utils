if Debug then Debug.beginFile("FileIO") end
--[[
    Optimized FileIO based on Trokkin's version

    Provides functionality to read and write files, optimized with lua functionality in mind.

    API:

        FileIO.Save(filename, data, isLoadable?)
            - Write string data to a file
            ---@param isLoadable boolean? -- Use false only if you never plan to load the file to make it format nicer and be more size efficient. Default is true.

        FileIO.Load(filename) -> string?
            - Read string data from a file. Returns nil if file doesn't exist.

        FileIO.SaveAsserted(filename, data, onFail?) -> bool
            - Saves the file and checks that it was saved successfully.
              If it fails, passes (filename, data, loadResult) to onFail.

        FileIO.enabled : bool
            - field that indicates that files can be accessed correctly.

    Requirements:
        StringEscape by Tomotz

    Optional requirements:
        DebugUtils by Eikonium                          @ https://www.hiveworkshop.com/threads/330758/
        Total Initialization by Bribe                   @ https://www.hiveworkshop.com/threads/317099/

    Inspired by:
        - TriggerHappy's Codeless Save and Load         @ https://www.hiveworkshop.com/threads/278664/
        - ScrewTheTrees's Codeless Save/Sync concept    @ https://www.hiveworkshop.com/threads/325749/
        - Luashine's LUA variant of TH's FileIO         @ https://www.hiveworkshop.com/threads/307568/post-3519040
        - HerlySQR's LUA variant of TH's Save/Load      @ https://www.hiveworkshop.com/threads/331536/post-3565884

    Updated: 8 Mar 2023

    Patch by Tomotz 1 Mar 2025:
        - Added escaping to all characters unsupported by FileIO. Those include null terminator (for saving and loading),
        and line feed, opening square bracket, backslash, closing square bracket.
        - Added optional parameter isLoadable to savefile, which defaults to true. If false, the file will have nicer format -
        less character are escaped, and there is less extra characters added by FileIO. This also means there is more room for user
        data in each Preload call. But the file will not be loadable with FileIO.Load.
--]]
OnInit.global("FileIO", function()
    local RAW_PREFIX = ']]i([['
    local RAW_SUFFIX = ']])--[['
    local MAX_PRELOAD_SIZE = 256
    local RAW_SIZE = MAX_PRELOAD_SIZE - #RAW_PREFIX - #RAW_SUFFIX
    local LOAD_ABILITY = FourCC('ANdc')
    local LOAD_EMPTY_KEY = '!@#$, empty data'
    local name = nil ---@type string?

    -- carriage return seems to turn into new line when written and read back
    FileIO_unsupportedLoadChars = {0, 10, 13, 91, 92, 93} -- null terminator, line feed, carriage return, opening square bracket, backslash, closing square bracket
    FileIO_unsupportedSaveChars = {0, 92} -- only null terminator is not supported when saving. \ becomed \\ though, so the string becomes longer and we lose the last characters in the Preload

    ---@param filename any
    ---@param isLoadable any
    local function open(filename, isLoadable)
        -- turns out you can't save a file without an extension.
        Debug.assert(filename:find('.', 1, true), "FileIO: filename must have an extension")
        name = filename
        PreloadGenClear()
        if isLoadable then
            Preload('")\nendfunction\n//!beginusercode\nlocal p={} local i=function(s) table.insert(p,s) end--[[')
        end
    end

    local function write(s, isLoadable)
        if isLoadable then
            for i = 1, #s, RAW_SIZE do
                Preload(RAW_PREFIX .. s:sub(i, i + RAW_SIZE - 1) .. RAW_SUFFIX)
            end
        else
            for i = 1, #s, MAX_PRELOAD_SIZE do
                Preload(s:sub(i, i + MAX_PRELOAD_SIZE - 1))
            end
        end
    end

    local function close(isLoadable)
        if isLoadable then
            Preload(']]BlzSetAbilityTooltip(' ..
                LOAD_ABILITY .. ', table.concat(p), 0)\n//!endusercode\nfunction a takes nothing returns nothing\n//')
        end
        PreloadGenEnd(name --[[@as string]])
        name = nil
    end

    ---@param filename string
    ---@param data string
    ---@param isLoadable boolean? -- Use false only if you never plan to load the file. Default is true.
    -- This controls which characters are escaped and replaced. For loadable files, we must remove more characters.
    local function savefile(filename, data, isLoadable)
        if isLoadable == nil then
            isLoadable = true
        end
        local unsupportedChars ---@type integer[]
        if isLoadable then
            unsupportedChars = FileIO_unsupportedLoadChars
        else
            unsupportedChars = FileIO_unsupportedSaveChars
        end
        local data2 = AddEscaping(data,  unsupportedChars)
        open(filename, isLoadable)
        write(data2, isLoadable)
        close(isLoadable)
    end

    ---@param filename string
    ---@return string?
    local function loadfile(filename)
        local s = BlzGetAbilityTooltip(LOAD_ABILITY, 0)
        BlzSetAbilityTooltip(LOAD_ABILITY, LOAD_EMPTY_KEY, 0)
        Preloader(filename)
        local loaded = BlzGetAbilityTooltip(LOAD_ABILITY, 0)
        if loaded == LOAD_EMPTY_KEY then
            return nil
        end
        return RemoveEscaping(loaded, FileIO_unsupportedLoadChars)
    end

    ---@param filename string
    ---@param data string
    ---@param onFail nil | fun(filename:string, data:string, loadResult:string?)
    ---@return boolean
    local function saveAsserted(filename, data, onFail)
        savefile(filename, data)
        local res = loadfile(filename)
        if res == data then
            return true
        end
        if onFail then
            onFail(filename, data, res)
        end
        return false
    end

    local fileIO_enabled = saveAsserted('TestFileIO.pld', 'FileIO is Enabled')

    FileIO = {
        Save = savefile,
        Load = loadfile,
        SaveAsserted = saveAsserted,
        enabled = fileIO_enabled,
    }
end)
if Debug then Debug.endFile() end
