if Debug and Debug.beginFile then Debug.beginFile("Interpreter") end
do
--[[
Interpreter v1.0.0 by Tomotz
This tool allows connecting to your game with an external cli, and run lua code in it - it allows you to open a windows terminal and run code inside your game. Works for single player and in replays

Features:
 - A cli interpreter that connects to your game while it's running, and runs lua code inside the game.
 - Write single line lua instructions in the terminal, and have them run inside the game.
 - Get command output in the terminal.
 - Run lua script files.
 - Run new code during replay and let you debug the replay.
Note that currently the interpreter does not support multiplayer (It will not run if there is more than one active player). Support for multiplayer can be added but will be a bit complicated since the backend files data needs to be synced. If I'll see a demand for the feature, I'll add it.

Installation and usage instructions:
 - Copy the lua code to your map and install the requirements.
 - Install python3 (tested with python 3.9 but would probably work with any python3 version)
 - Create wc3_interpreter.py script, and edit `CUSTOM_MAP_DATA_PATH` to point to your `CustomMapData` folder
 - In windows terminal run `python ...\wc3_interpreter.py` (type help for list of commands and usage)
 - Tip - if you want to debug a replay, run warcraft with nowfpause, and then you can alt tab to the shell without the game pausing:
    "C:\Program Files (x86)\Warcraft III\_retail_\x86_64\Warcraft III.exe" -launch -nowfpause

cli commands:
 - help - Print all available commands and descriptions
 - exit - Exit the program
 - restart - Cleans the state to allow a new game to be started (this is the same as exiting and restarting the script)
 - file <full file path> - send a file with lua commands to the game. end the file with `return <data>` to print the data to the console
 - <lua command> - run a lua command in the game. If the command is a `return` statement, the result will be printed to the console.
* Note: exiting or restarting the script while the game is running will cause it to stop working until the game is also restarted **
Requires:

Algorithm explanation:
The lua code polls on the creation of new files with increasing indices (in0.txt, in1.txt, ...). When a new file is found, it reads the content, runs it as lua code, and saves the output to the corresponding outN.txt file.
For each command you type in the cli, the python script creates a files in the wc3 preload format and reads and prints the output file returned.

Suggested usages:
 - Map Development - You created a new global function, you test your map and it doesn't do what you meant. You can now create a file with this function, edit what you wish, and run `file` command. The new function will run over the old one, and you can test it again without restarting wc3 and rebuilding the map.
 - Value Lookups - You can check variable values and other state checks while playing (in single player). You could already do that with DebugUtils `-console`, but this was annoying to do with the limited ingame chat. If you're playing in multiplayer, you can later check the values in the replay.
 - Map Debugging - Reimplement global functions dynamically while playing, and add prints and logs as needed
 - Replay Debugging - Perform quarries or make things happen differently at replay - change values of variables, create new units etc.

Requires:
FileIO (lua) by Trokkin - https://www.hiveworkshop.com/threads/fileio-lua-optimized.347049/
TotalInitialization by Bribe - https://www.hiveworkshop.com/threads/total-initialization.317099/

To be able to run in replay mode of a multiplayer game, you either need
LogUtils (by me) - https://www.hiveworkshop.com/threads/logutils.357625/
or just to copy the `SetGameStatus` function from there and call it in your map init.

Credits:
TriggerHappy GameStatus (Replay Detection) https://www.hiveworkshop.com/threads/gamestatus-replay-detection.293176/
 * SetGameStatus was taken from there to allow detecting that the game is running in replay mode.

Updated: 28 Oct 2025
--]]

-- Period to check for new commands to execute
-- Note that once a command was executed, the polling period increases to 0.1 seconds to allow fast interpreting.
-- The period goes back to normal after no new commands were found for 60 seconds.
local PERIOD = 5
-- Directory to save the input/output files. Must match the python script path
local FILES_ROOT = "Interpreter"

-- The code will desync in multiplayer, so we only allow running it in single player or replay mode
local isMultiplayer ---@type boolean


local nextFile = 0
local curPeriod = PERIOD
local lastCommandExecuteTime = 0
function CheckFiles()
    local timer = GetExpiredTimer()
    --- first we trigger the next run in case this run crashes or returns
    TimerStart(timer, curPeriod, false, CheckFiles)
    -- To make the replay as close as possible to the original game, we do call the timer on both, and just return right away if multiplayer
    if isMultiplayer then return end
    local commands = FileIO.Load(FILES_ROOT .. "\\in" .. nextFile .. ".txt")
    if commands ~= nil then
        -- command found, increase period to 0.1s, run the command and return the result
        curPeriod = 0.1
        TimerStart(timer, 0.1, false, CheckFiles)
        lastCommandExecuteTime = os.clock()
        local cur_func = load(commands)
        local result = nil
        if cur_func ~= nil then
            result = cur_func()
        end
        FileIO.Save(FILES_ROOT .. "\\out" .. nextFile .. ".txt", tostring(result))
        nextFile = nextFile + 1
    end
    if os.clock() - lastCommandExecuteTime > 60 then
        -- over 60s passed since last command sent. Return the period to normal
        curPeriod = PERIOD
    end
end

function CountActivePlayers()
    local count = 0
    for plr = 0, bj_MAX_PLAYER_SLOTS - 1 do
        if GetPlayerController(Player(plr)) == MAP_CONTROL_USER and GetPlayerSlotState(Player(plr)) == PLAYER_SLOT_STATE_PLAYING then
            count = count + 1
        end
    end
    return count
end

function TryInterpret()
    isMultiplayer = ((not GameStatus) or GameStatus == GAME_STATUS_ONLINE) and CountActivePlayers() > 1
    -- Timer is leaked on purpose to keep it running throughout the entire game
    TimerStart(CreateTimer(), 5, false, CheckFiles)
end

OnInit(TryInterpret)

end
if Debug and Debug.endFile then Debug.endFile() end