if Debug then Debug.beginFile("TestLib") end
OnInit.final("TestLib", function()
    Debug = Debug or {assert=assert, endFile=function() end, throwError=function(...) assert(false, ...) end}
    LogWrite = LogWrite or function(...) print(...) end

    --- Recursively compares two tables for deep equality.
    ---@param t1 table
    ---@param t2 table
    ---@param visited table? -- Used internally to track already compared tables
    ---@return boolean
    function deepCompare(t1, t2, visited)
        -- If both are not tables, compare directly
        if type(t1) ~= type(t2) then
            Debug.throwError("deepCompare: tables not equal: " .. tostring(t1) .. " and " .. tostring(t2))
            return false
        end
        if type(t1) ~= "table" then
            if t1 == t2 then
                return true
            elseif type(t1) == "number" and math.abs(t1 - t2) < 0.00001 then
                return true
            end

            Debug.throwError("deepCompare: tables not equal: " .. tostring(t1) .. " and " .. tostring(t2))
            return false
        end

        -- Prevent infinite loops by tracking already visited tables
        visited = visited or {}
        if visited[t1] and visited[t2] then
            return true
        end
        visited[t1], visited[t2] = true, true

        -- Compare number of keys
        local keys1, keys2 = {}, {}
        local hasNil1, hasNil2 = false, false
        for k in pairs(t1) do
            if type(k) == "number" and math.floor(k) ~= k then
                --floats might lose some precision when converted to string, so we round them to 5 decimal places
                keys1[string.format("\x25.5f", k)] = true
            elseif type(k) == "nil" then
                hasNil1 = true
            else
                keys1[k] = true
            end
        end
        for k in pairs(t2) do
            if type(k) == "number" and math.floor(k) ~= k then
                --floats might lose some precision when converted to string, so we round them to 5 decimal places
                keys2[string.format("\x25.5f", k)] = true
            elseif type(k) == "nil" then
                hasNil2 = true
            else
                keys2[k] = true
            end
        end
        for k in pairs(keys1) do
            -- LogWrite("comparing key " .. tostring(k) .. ". First table: " .. tostring(t1[k]):sub(1, 100) .. ", second table: " .. tostring(t2[k]):sub(1, 100))
            if not keys2[k] then
                Debug.throwError("deepCompare: tables not equal: key " .. tostring(k) .. " not found in second table")
                return false
            end
            if not deepCompare(t1[k], t2[k], visited) then return false end
        end
        if hasNil1 ~= hasNil2 then
            local which = hasNil1 and "first" or "second"
            Debug.throwError("deepCompare: tables not equal: " .. which .. " has nil keys and the other doesn't")
            return false
        end
        for k in pairs(keys2) do
            if not keys1[k] then
                Debug.throwError("deepCompare: tables not equal: key " .. tostring(k) .. " not found in first table")
                return false
            end
        end

        return true
    end

    function test_AddEscaping()
        local tests = {
            {"hello", "hello"},
            {"\0\10\13\91\92\93", "\248\249\250\251\252\253"}, -- fileio_unsupported_chars replaced
            {"\247", "\247\247"}, -- escape_char doubled
            {"\250", "\247\250"}, -- unprintable_replacables escaped
            {"\251", "\247\251"},
            {"hello\n\247\0world", "hello\249\247\247\248world"},
            {"hello\250world", "hello\247\250world"}
        }

        for i, test in ipairs(tests) do
            local input, expected = test[1], test[2]
            local result = AddEscaping(input, FileIO_unsupportedLoadChars)
            Debug.assert(result == expected, string.format("AddEscaping failed on test \x25d: expected \x25q, got \x25q", i, expected, result))
        end
        LogWrite("All AddEscaping tests passed!")
    end

    function test_RemoveEscaping()
        local tests = {
            {"hello", "hello"},
            {"\248\249\250\251\252\253", "\0\10\13\91\92\93"}, -- reversed replacements
            {"\247\247", "\247"}, -- double escape_char restored
            {"\247\248", "\248"}, -- escaped chars restored
            {"\247\251", "\251"},
            {"hello\249\247\247\248world", "hello\n\247\0world"},
            {"hello\247\248world", "hello\248world"}
        }

        for i, test in ipairs(tests) do
            local input, expected = test[1], test[2]
            local result = RemoveEscaping(input, FileIO_unsupportedLoadChars)
            Debug.assert(result == expected, string.format("RemoveEscaping failed on test \x25d: expected \x25q, got \x25q", i, expected, result))
        end
        LogWrite("All RemoveEscaping tests passed!")
    end

    function test_roundtrip()
        local tests = {
            "hello",
            "\0\13\91\92\93",
            "\247",
            "\248\249\250\251\252",
            "so\nme\247text\250here",
            "\247\248\249\250\251\252"
        }

        for i, test in ipairs(tests) do
            local escaped = AddEscaping(test, FileIO_unsupportedLoadChars)
            local unescaped = RemoveEscaping(escaped, FileIO_unsupportedLoadChars)
            Debug.assert(unescaped == test, string.format("Roundtrip failed on test \x25d: expected \x25q, got \x25q", i, test, unescaped))
        end
        LogWrite("All roundtrip tests passed!")
    end

    ---@type any[]
    local origTable = {
        true,
        false,
        1,
        -1, -- only works for 32 bit lua
        0,
        255,
        256^2 - 1,
        0x7FFFFFFF, -- the maximum positive integer
        0x7FFFFFFF, -- the maximum positive integer
        0xFFFFFFFF, -- -1
        0x80000000, -- the minimum negative integer
        math.pi,
        "hello",
        "\0\10\13\91\92\93\248\249\250\251\252\253",
        string.rep("s", 257 ),
        "",
        -- string.rep("d", 256*175 ), -- this test is spamming the log so skipping it by default
        "h",
        "ab!!",
        {},  -- Empty table
        { key1 = "value1", key2 = "value2" },  -- Table with string keys
        { 100, 200, 300 },  -- Table with only numeric values
        { 0, 1, 2, 1000, 256^3 },  -- Table with growing values
        { 256^3, 1000, 2, 1, 0 },  -- Table with decreasing values
        { [1] = "a", [3] = "c", [5] = "e" },  -- Sparse array
        { nested = { a = 1, b = { c = 2, d = { e = 3 } } } },  -- Deeply nested table
        { { { { { "deep" } } } } },  -- Extreme nesting level
        { special = { "\x0A", "\x09", "\x0D", "\x00", "\x5D", "\x5C" } },  -- Special characters (\n, \t, \r, \0, ], \)
        { mixed = { "string", 123, true, false, 0, { nested = "inside" } } },  -- Mixed types
        { largeNumbers = { 0x40000000, 0x7FFFFFFF, 0x80000000, 0xBFFFFFFF } },  -- Large numbers (2^30, 2^31-1, -2^31, -2^30)
    }
    -- for i=0, 255 do
    --     origTable[#origTable + 1] = string.char(i)
    -- end

    function test_dumpLoad()
        local packedStr = Serializer.dumpVariable(origTable)
        LogWrite("writing done")
        if packedStr then
            LogWrite(tostring(packedStr:byte(1, #packedStr)))
        end
        local loadedVar, charsConsumed = Serializer.loadVariable(packedStr)
        LogWrite("load done")
        Debug.assert(loadedVar ~= nil, "loadVariable failed")
        Debug.assert(charsConsumed == #packedStr, "loadVariable didn't consume all characters. " .. tostring(charsConsumed) .. ", " .. tostring(#packedStr))
        Debug.assert(deepCompare(origTable, loadedVar), "loaded table doesn't match the original table")
    end

    ---@param testName string
    ---@param datas string[]
    function singleSyncTest(testName, datas)
        local doneSyncs = {}
        local totalFlits = 0
        local startTime = os.clock()
        for i, data in ipairs(datas) do
            totalFlits = totalFlits + math.ceil((#data + 1) / FLIT_DATA_SIZE)

            doneSyncs[i] = false
            SyncStream.sync(Player(0), data, function (syncedData, whichPlayer)
                Debug.assert(type(syncedData) == "string", "got " .. type(syncedData) .. " sync data")
                Debug.assert(#syncedData == #data, "wrong len for syncData. Expected: " .. #data .. ", got: " .. #syncedData .. ". " .. string.sub(syncedData, 1, 50) .. "...")
                Debug.assert(syncedData == data, "wrong data for syncData. Expected: " .. string.sub(data, 1, 50)  .. ". got: " .. syncedData)
                doneSyncs[i] = true
                -- LogWrite(testName, "sync", i, "done")
            end)
        end
        local expectedTransferTimer = (totalFlits * FLIT_DATA_SIZE) / TRANSFER_RATE
        LogWrite(testName, "test started. Expected time:", expectedTransferTimer * 1.1, "seconds") -- add some time for the sleep
        print(testName, "test started. Expected time:", expectedTransferTimer * 1.1, "seconds") -- add some time for the sleep
        local allDone = true
        for _ = 0, 100 do
            TriggerSleepAction(math.max(expectedTransferTimer / 10, 0.1))
            allDone = true
            for i = 1, #datas do
                if not doneSyncs[i] then
                    allDone = false
                    break
                end
            end
            if allDone then
                break
            end
        end
        local endTime = os.clock()
        if allDone then
            LogWrite(testName, "test done. Took", endTime-startTime, "seconds")
            print(testName, "test done. Took", endTime-startTime, "seconds")
        else
            LogWrite(testName, "test timed out")
            print(testName, "test timed out")
            Debug.throwError(testName, "test timed out")
        end
    end

    function test_sync()
        LogWrite("testing syncs")
        singleSyncTest("empty sync", {""})
        local singleByteDatas = {}
        local longData = ""
        for i = 0, 255 do
            table.insert(singleByteDatas, string.char(i))
            longData = longData .. string.rep(string.char(i), 256)
        end
        -- singleSyncTest("single char sync", singleByteDatas)
        singleSyncTest("same char + large string sync", {"a", "a", longData, "a", "a"})
        singleSyncTest("same char + large string sync", {"a", "a", longData, "a", "a"})
        singleSyncTest("same char + large string sync", {"a", "a", longData, "a", "a"})
        singleSyncTest("same char + large string sync", {"a", "a", longData, "a", "a"})
        singleSyncTest("same char + large string sync", {"a", "a", longData, "a", "a"})
        singleSyncTest("same char + large string sync", {"a", "a", longData, "a", "a"})
        singleSyncTest("same char + large string sync", {"a", "a", longData, "a", "a"})
        singleSyncTest("same char + large string sync", {"a", "a", longData, "a", "a"})
        singleSyncTest("same char + large string sync", {"a", "a", longData, "a", "a"})
        singleSyncTest("same char + large string sync", {"a", "a", longData, "a", "a"})
        singleSyncTest("same char + large string sync", {"a", "a", longData, "a", "a"})

        -- singleSyncTest("all chars", {table.concat(singleByteDatas)})

        print("test_sync validation done")
        LogWrite("test_sync validation done")
    end

    function test_saveLoad()
        local success = Serializer.saveFile(Player(0), origTable, "Savegames\\DotD 6\\test_save_load_" .. PlayersArr[0].rawName .. ".txt")
        Debug.assert(success, "saveFile failed")
        LogWrite("saveFile saved")

        function EndFunc(loadedVars, whichPlayer)
            LogWrite("in callback")
            if loadedVars == nil then
                Debug.throwError("loadFile returned nil")
                return
            end
            Debug.assert(deepCompare(origTable, loadedVars[1]), "loaded table doesn't match the original table")
            LogWrite("EndFunc test ended! validation done")

        end

        local error = Serializer.loadFile(Player(0),"Savegames\\DotD 6\\test_save_load_" ..
        PlayersArr[GetPlayerId((GetLocalPlayer()))].rawName .. ".txt", EndFunc)
        LogWrite("(If this is an error it might be ok for the wrong player) loaded returned:", error)
    end

    -- Run tests
    -- test_AddEscaping()
    -- test_RemoveEscaping()
    -- test_roundtrip()
    -- LogWrite("escaping validation done")
    -- test_dumpLoad()
    -- LogWrite("test_dumpLoad validation done")
    -- ExecuteFunc(test_sync)
    -- ExecuteFunc(test_saveLoad)

    -- ExecuteFunc(function()
    --     local syncTrigger = CreateTrigger()
    --     BlzTriggerRegisterPlayerSyncEvent(syncTrigger, Player(0), "abkh", false)

    --     totalReceived = 0
    --     local nextExpected = 1
    --     TriggerAddAction(syncTrigger, function()
    --         totalReceived = totalReceived + 1
    --         local package = BlzGetTriggerSyncData()
    --         if nextExpected == 0 then
    --             Debug.assert(#package == 0, "bad package len. Got:" .. #package .. "for packet #" .. totalReceived)
    --         else
    --             Debug.assert(#package == 255, "bad package len. Got:" .. #package .. "for packet #" .. totalReceived)
    --             Debug.assert(package == string.rep(string.char(nextExpected), 255), "bad package. Expected 255 of char:" .. nextExpected .. "Got: " .. package)
    --         end
    --         nextExpected = math.fmod(nextExpected, 256)
    --     end)

    --     local syncTimer = CreateTimer()
    --     local nextPacket = 1
    --     TimerStart(syncTimer, 1 / 32, true, function()
    --         if nextPacket == 0 then
    --             Debug.assert(BlzSendSyncData("abkh", ""), "send failed!!!!")
    --         else
    --             Debug.assert(BlzSendSyncData("abkh", string.rep(string.char(nextPacket), 255)), "send failed!!!!")
    --         end
    --         nextPacket = math.fmod(nextPacket, 256)
    --     end)
    -- end)

end)

if Debug then Debug.endFile() end