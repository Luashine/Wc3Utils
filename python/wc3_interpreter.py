
# wc3_interpreter.py
VERSION = "1.0.1"

import os
import re
import time
import signal
import sys
import traceback
from typing import Optional

# You might need to change `D:` to your Warcraft III installation drive
CUSTOM_MAP_DATA_PATH = r"D:\Users\{username}\Documents\Warcraft III\CustomMapData\\".format(username=os.getlogin())
FILES_ROOT = CUSTOM_MAP_DATA_PATH + "Interpreter" + "\\" # This should match the folder defined in the lua code

# find any pattern starting with `call Preload( "]]i([[` and ending with `]])--[[" )` and concatenate the innter strings
REGEX_PATTERN = rb'call Preload\( "\]\]i\(\[\[(.*?)\]\]\)--\[\[" \)'

FILE_PREFIX = """function PreloadFiles takes nothing returns nothing

	call PreloadStart()
	call Preload( "")
endfunction
//!beginusercode
local p={} local i=function(s) table.insert(p,s) end--[[" )
	"""

FILE_POSTFIX = """\n	call Preload( "]]BlzSetAbilityTooltip(1095656547, table.concat(p), 0)
//!endusercode
function a takes nothing returns nothing
//" )
	call PreloadEnd( 0.1 )

endfunction

"""

LINE_PREFIX = '\n	call Preload( "]]i([['
LINE_POSTFIX = ']])--[[" )'

def load_lua_directory(path: str):
    lua_files = {}
    for root, _, files in os.walk(path):
        for f in files:
            if f.endswith('.lua'):
                full_path = os.path.join(root, f)
                with open(full_path, 'r', encoding='utf-8') as file:
                    lua_files[full_path] = file.read()
    return lua_files

import re

def find_lua_function(content: str, func_name: str=None, line_number: int=None):
    """
    Returns (start_index, end_index, body_text)
    """
    lines = content.splitlines(keepends=True)
    if line_number is not None:
        # Find the nearest 'function ' line before the given line
        for i in range(line_number - 1, -1, -1):
            if re.match(r'\s*function\b', lines[i]):
                func_line = i
                break
        else:
            return None
    elif func_name:
        # Find by function name
        pattern = rf'\bfunction\s+{re.escape(func_name)}\b'
        for i, line in enumerate(lines):
            if re.search(pattern, line):
                func_line = i
                break
        else:
            return None
    else:
        return None

    # Find the matching 'end'
    depth = 0
    for j in range(func_line, len(lines)):
        if re.match(r'\s*function\b', lines[j]):
            depth += 1
        elif re.match(r'\s*end\b', lines[j]):
            depth -= 1
            if depth == 0:
                start = sum(len(l) for l in lines[:func_line])
                end = sum(len(l) for l in lines[:j + 1])
                return start, end, ''.join(lines[func_line:j + 1])
    return None

def inject_into_function(content: str, start: int, end: int, inject_str: str, after_line: int=None):
    func = content[start:end]
    func_lines = func.splitlines(keepends=True)
    if after_line is None:
        # Insert after first line (after function header)
        func_lines.insert(1, inject_str + '\n')
    else:
        func_lines.insert(after_line, inject_str + '\n')

    new_func = ''.join(func_lines)
    return content[:start] + new_func + content[end:]

def modify_function(lua_files: dict[str,str], func_name: Optional[str] = None, target_file: str='', target_line: Optional[int]=None, inject_str: str=''):
    if target_file != '':
        content = lua_files[target_file]
    else:
        # Search for name across all files
        for f, c in lua_files.items():
            if func_name in c:
                target_file = f
                content = c
                break
        else:
            raise ValueError("Function not found")

    match = find_lua_function(content, func_name=func_name, line_number=target_line)
    if not match:
        raise ValueError("Could not locate function boundaries")

    start, end, _ = match
    new_content = inject_into_function(content, start, end, inject_str)
    return new_content

def load_file(filename: str):
    """loads a file in wc3 preload format (saved by FileIO) and parses it"""
    if not os.path.exists(filename):
        return None
    with open(filename, 'rb') as file:
        data = file.read()
    matches = re.findall(REGEX_PATTERN, data, flags=re.DOTALL)
    if matches:
        return b''.join(matches)
    return b''

def create_file(filename: str, content: str):
    """
    creates a file in wc3 preload format (that can be loaded by FileIO)
    @content: The data that will be returned from FileIO after loading this file
    """
    assert len(content) > 0
    data = FILE_PREFIX
    # Split content into 255 char chunks
    for i in range(0, len(content), 255):
        chunk = content[i : i+255]
        data += LINE_PREFIX + chunk + LINE_POSTFIX
    data += FILE_POSTFIX
    with open(filename, 'w', encoding='utf-8') as file:
        file.write(data)

def remove_all_files():
    """Removes all input and output files from the FILES_ROOT directory.
    If we leave the files there, the next game might read and run them"""
    if not os.path.isdir(FILES_ROOT):
        return
    for filename in os.listdir(FILES_ROOT):
        file_path = os.path.join(FILES_ROOT, filename)
        if (filename.startswith("in") or filename.startswith("out")) and filename.endswith(".txt") and os.path.isfile(file_path):
            try:
                os.unlink(file_path)
            except Exception as e:
                print(f"Error deleting file {file_path}: {e}")

def signal_handler(sig, frame):
    """On any termination of the program we want to remove the input and output files"""
    remove_all_files()
    sys.exit(0)

nextFile = 0
def main():
    global nextFile
    remove_all_files()
    # add a signal handler that handles all signals by removing all files and calling the default handler

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGABRT, signal_handler)
    signal.signal(signal.SIGSEGV, signal_handler)
    signal.signal(signal.SIGILL, signal_handler)

    print(f"Wc3 Interpreter {VERSION}. For help, type `help`.")
    while True:
        # get console input
        command = input(str(nextFile) + " >>> ")
        if command == "exit":
            remove_all_files()
            break
        elif command == "help":
            print("Available commands:")
            print("  help - Show this help message")
            print("  exit - Exit the program")
            print("  restart - Cleans the state to allow a new game to be started (this is the same as exiting and restarting the script)")
            print("  jump <number> - use in case of closing the interpreter (or crashing) while game is still running. Starts sending commands from a specific file index. Should use the index printed in the prompt before the `>>>`")
            print("  file <full file path> - send a file with lua commands to the game. end the file with `return <data>` to print the data to the console")
            print("  <lua command> - run a lua command in the game. If the command is a `return` statement, the result will be printed to the console.")
            print("** Note: exiting or restarting the script while the game is running will cause it to stop working until the game is also restarted **")
            continue
        elif command == "restart":
            remove_all_files()
            nextFile = 0
            print("State reset. You can start a new game now.")
            continue
        elif command.startswith("jump "):
            nextFile = int(command[5:].strip())
            continue
        elif command.startswith("file "):
            filepath = command[5:].strip()
            if os.path.exists(filepath):
                with open(filepath, 'r', encoding='utf-8') as f:
                    data = f.read()
                print(f"Sent file {filepath} to game as in{nextFile}.txt")
            else:
                print(f"File `{filepath}` does not exist.")
                continue
        else:
            data = command
        if data == "":
            continue
        create_file(FILES_ROOT + f"in{nextFile}.txt", data)
        while not os.path.exists(FILES_ROOT + f"out{nextFile}.txt"):
            time.sleep(0.1)
        try:
            result = load_file(FILES_ROOT + f"out{nextFile}.txt")
            if result != "nil":
                print(result)
        except Exception as e:
            print("failed. Got exception: ", e)
            traceback.print_exc()
        nextFile += 1

if __name__ == "__main__":
    main()