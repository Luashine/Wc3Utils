if Debug and Debug.beginFile then Debug.beginFile("DebugDumps") end
--[[
DebugDumps v1.2.0 by Tomotz
This library is meant to help with debugging desyncs.
It dumps the stacktrace and names of any functions that are currently in progress or ended not long ago.
(which can be triggered when a player leaves the game).
It's main purpose is to help investigating desyncs by letting the developer know what functions recently started/finished
execution, and what functions are still in progress. This info can be dumped when a player leaves the game.

Features:
 - Save a list of functions that recently started/ended execution
 - Save all locations of the current context switching functions (functions that release execution and allow other threads to run)
   TriggerSleepAction (TSA), ExecuteFunc, TriggerExecute, TriggerEvaluate calls. Will save those from the time the function released
   execution, until the thread returns to that point in the code.
   Saves all coroutins that have yielded and weren't resumed yet
 - Save all timers that are currently counting (started and weren't paused/destroyed) including the location in the code where they
   were started
 - Dump all the above info to a file
 - For each timer/context switch, will dump the name of the function that used the TSA/CS function, and the traceback where this
   call was performed.

Interface:
    - LogRecentFuncs()
        Dumps the recent functions to the log file

    - DebugDumpsEndRecording()
    - DebugDumpsStartRecording()
        Not required to use. If you to skip wrapping some functions, you can use `DebugDumpsEndRecording` at the start of such
        function block, and DebugDumpsStartRecording at the end, causing all functions in between no to be recorded

Installation instructions:
 - DebugDumps should be copied to your map and put above any part of your code you wish to be included in the dumps.
   (but after all the libraries it depends on which of course will not be included in the dumps)

Performance:
I did not see a notable performance impact on my map from all the wrapping functions, but I'm sure it has some performance impact.
It shouldn't be very hard to implement that the code here will only be ran in replay mode if necessary.

Known issues:
 - If the same function is called multiple times, it will appear multiple times in the log (reducing the amount of overall unique functions in the log)
 - Does not dump traces from local functions.
 - Does not dump traces from table functions.
    * I think this one should be solvable by adding `table` recursive behavior to __newindex, but I didn't really needed it so didn't implement it.
 - These last two cases might also cause a wrong function name to appear in the log in the case TSA or another context switching function
   is used in a local/table function.
 - Cannot dump anything that happens before OnInit (or anything in itself/the libraries it depends on)

Requires:
TotalInitialization by Bribe - https://www.hiveworkshop.com/threads/total-initialization.317099/
SyncedTable by Eikonium - https://www.hiveworkshop.com/threads/syncedtable.353715/
Hook by Bribe - https://www.hiveworkshop.com/threads/hook.339153/

LogUtils (By me) or any implementations of LogWrite and LogWriteNoFlush - https://www.hiveworkshop.com/threads/logutils.357625/
    For LogUtils - FileIO (lua) by Trokkin - https://www.hiveworkshop.com/threads/fileio-lua-optimized.347049/

--]]


-- Configurations:

-- Maximum number of recently ended functions to print.
local RECENT_END_MAX = 50

-- A table for functions that we don't want to dump to the recent function trace.
-- Note that they could still appear on Current timers/Context switches.
---@type table<string>
local EXCLUDE_LIST = {
    ["RegisterFastTimer"] = true
}

-- If true, will dump the recent functions whenever a player leaves the game
local DUMP_ON_PLAYER_LEAVE = true


-- Local variables for internal use

--functions that recently ended
---@type table<integer, string>
local recent_end_functions = {}
local cur_func_end_idx = 0
local next_func_end_idx = 1
local recent_funcs_end_full = false

---@type string -- the last user function seen in the current thread
local last_function_seen = ""

---@type SyncedTable<string, integer>
local cur_functions = SyncedTable.create()

---@type SyncedTable<timer, string>
local cur_timers = SyncedTable.create()

---@type SyncedTable<thread, {trace:string, prev_func:string}>
local cur_coroutines = SyncedTable.create()

---@type SyncedTable<string, string>
local recent_TSA = SyncedTable.create()

---@type Hook.property
DebugWrapHook = nil

function LogRecentFuncs()
    LogWriteNoFlush("###Current funcs###")
    for funcName, count in pairs(cur_functions) do
        LogWriteNoFlush(funcName .. ": " .. count)
    end
    LogWriteNoFlush("###Current coroutines###")
    for tid, cr_data in pairs(cur_coroutines) do
        LogWriteNoFlush(cr_data.prev_func .. "(" .. tostring(tid) .. ")")
    end
    LogWriteNoFlush("###Current timers###")
    for _, traceback in pairs(cur_timers) do
        LogWriteNoFlush(traceback)
    end
    LogWriteNoFlush("###Current Context Switches###")
    for traceback, funcType in pairs(recent_TSA) do
        LogWriteNoFlush(funcType .. ": " .. traceback)
    end
    LogWriteNoFlush("###Recently ended funcs###")
    if recent_funcs_end_full then
        for i = next_func_end_idx, RECENT_END_MAX do
            LogWriteNoFlush(recent_end_functions[i])
        end
    end
    for i = 1, next_func_end_idx - 1 do
        LogWriteNoFlush(recent_end_functions[i])
    end
    LogWrite("######")
end

local function init()
    local function TimerStartHook(hook, whichTimer, timeout, periodic, handlerFunc)
        cur_timers[whichTimer] = Debug.traceback() .. " (" .. last_function_seen .. ")"
        -- save the last function seen from the caller, and restore it at the end of the run
        local prev_function = last_function_seen

        local WrapperFunc = function()
            last_function_seen = prev_function
            if handlerFunc ~= nil then
                handlerFunc()
            end
        end

        hook.next(whichTimer, timeout, periodic, WrapperFunc)
        last_function_seen = prev_function
    end

    local function StopTimerHook(hook, whichTimer)
        cur_timers[whichTimer] = nil
        hook.next(whichTimer)
    end

    Hook.add("TimerStart", TimerStartHook)
    Hook.add("PauseTimer", StopTimerHook)
    Hook.add("DestroyTimer", StopTimerHook)

    ---@param hook Hook.property
    local function CoroutineYieldHook(hook, ...)
        cur_coroutines[coroutine.running()] = {
            trace = Debug.traceback() .. " (" .. last_function_seen .. ")",
            prev_func =
                last_function_seen
        }
        hook.next(...)
    end

    ---@param hook Hook.property
    ---@param cur_thread thread
    local function CoroutineResumeHook(hook, cur_thread, ...)
        thread_data = cur_coroutines[cur_thread]
        if thread_data ~= nil then
            last_function_seen = thread_data.prev_func
            cur_coroutines[cur_thread] = nil
        end
        hook.next(cur_thread, ...)
    end

    Hook.add("yield", CoroutineYieldHook, 0, coroutine)
    Hook.add("resume", CoroutineResumeHook, 0, coroutine)


    ---@param hook Hook.property
    ---@param func_type string
    local function WrapContextSwitchFunc(hook, func_type, ...)
        local tb = Debug.traceback() .. " (" .. last_function_seen .. ")"
        -- save the last function seen from the caller, and restore it at the end of the run
        local prev_function = last_function_seen
        recent_TSA[tb] = func_type
        hook.next(...)
        last_function_seen = prev_function
        recent_TSA[tb] = nil
    end

    ---@param hook Hook.property
    local function TriggerSleepActionHook(hook, ...)
        WrapContextSwitchFunc(hook, "TSA", ...)
    end

    ---@param hook Hook.property
    local function ExecuteFuncHook(hook, ...)
        WrapContextSwitchFunc(hook, "ExFunc", ...)
    end

    ---@param hook Hook.property
    local function TriggerExecuteHook(hook, ...)
        WrapContextSwitchFunc(hook, "TrigEx", ...)
    end

    ---@param hook Hook.property
    local function TriggerEvaluateHook(hook, ...)
        WrapContextSwitchFunc(hook, "TrigEval", ...)
    end
    Hook.add("TriggerSleepAction", TriggerSleepActionHook)
    Hook.add("ExecuteFunc", ExecuteFuncHook)
    Hook.add("TriggerExecute", TriggerExecuteHook)
    Hook.add("TriggerEvaluate", TriggerEvaluateHook)

    if DUMP_ON_PLAYER_LEAVE then
        local player_leaves_trig = CreateTrigger()
        for i = 0, GetBJMaxPlayers() - 1 do
            TriggerRegisterPlayerEvent(player_leaves_trig, Player(i), EVENT_PLAYER_LEAVE)
        end
        TriggerAddAction(player_leaves_trig, LogRecentFuncs)
    end
end

local function OnStart(funcName)
    if cur_functions[funcName] == nil then
        cur_functions[funcName] = 0
    end
    cur_functions[funcName] = cur_functions[funcName] + 1
end

local function OnEnd(funcName)
    cur_functions[funcName] = cur_functions[funcName] - 1
    if cur_functions[funcName] == 0 then
        cur_functions[funcName] = nil
    end
    if recent_end_functions[cur_func_end_idx] ~= funcName then
        recent_end_functions[next_func_end_idx] = funcName
        cur_func_end_idx = next_func_end_idx
        next_func_end_idx = ModuloInteger(next_func_end_idx, RECENT_END_MAX) + 1
        if next_func_end_idx == 1 then
            recent_funcs_end_full = true
        end
    end
end

local function WrapFunction(func, funcName)
    return function(...)
        -- save the last function seen from the caller, and restore it at the end of the run
        local prev_function = last_function_seen
        last_function_seen = funcName
        if EXCLUDE_LIST[funcName] == nil then
            OnStart(funcName)
        end
        local result = { func(...) } -- Capture all return values
        if EXCLUDE_LIST[funcName] == nil then
            OnEnd(funcName)
        end
        last_function_seen = prev_function
        return table.unpack(result) -- Return all results
    end
end

---@param hook Hook.property
---@param _G table
---@param key string
---@param value unknown
local function __newindex(hook, _G, key, value)
    if type(value) == "function" then
        value = WrapFunction(value, key)
    end
    hook.next(_G, key, value)
end

function DebugDumpsStartRecording()
    if DebugWrapHook == nil then
        DebugWrapHook = Hook.add('__newindex', __newindex, 0, _G, rawset)
    end
end

function DebugDumpsEndRecording()
    if DebugWrapHook ~= nil then
        Hook.delete(DebugWrapHook)
        DebugWrapHook = nil
    end
end

OnInit(init)

if Debug and Debug.endFile then Debug.endFile() end

DebugDumpsStartRecording()
