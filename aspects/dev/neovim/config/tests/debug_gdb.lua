-- Exercise the pinned GDB DAP server implementation through the exact GDB
-- wrapper/data directory shipped to Neovim. The mock only replaces GDB's
-- command execution boundary; the real request decorators and patched module
-- control flow run in GDB's embedded Python.
local tools = require("mayon.generated").tools
local versions = require("mayon.generated").versions
local wrapper = assert(tools.gdb, "generated GDB wrapper is missing")
local wrapper_text = table.concat(vim.fn.readfile(wrapper), "\n")
local original_binary, data_dir = wrapper_text:match("exec%s+([^%s]+/bin/gdb)%s+%-%-data%-directory=([^%s]+)")
assert(original_binary and data_dir, "GDB wrapper must invoke the stock binary with a patched data directory")
assert(vim.fn.executable(original_binary) == 1 and vim.fn.executable(wrapper) == 1)
assert(vim.fn.filereadable(data_dir .. "/python/gdb/dap/server.py") == 1)

local function version(binary)
	local output = vim.fn.system({ binary, "--version" })
	assert(vim.v.shell_error == 0, "could not query GDB version: " .. output)
	return output:match("GNU gdb %(GDB%) ([^%s]+)")
end

local stock_version, wrapped_version = version(original_binary), version(wrapper)
assert(stock_version == wrapped_version, "patched data wrapper changed GDB binary version/ABI")
assert(not versions.gdb or stock_version == versions.gdb, "wrapper GDB version differs from generated metadata")

local python = [=[
import os
import queue
import threading
import types

import gdb
from gdb.dap import server, startup

expected = os.path.realpath(os.path.join(os.environ["NVIM_GDB_DAP_DATA"], "python/gdb/dap/server.py"))
assert os.path.realpath(server.__file__) == expected, (server.__file__, expected)
assert "_detach_inferior" in open(server.__file__, encoding="utf-8").read()
assert server._capabilities.get("supportTerminateDebuggee") is True
gdb_thread = threading.current_thread()
assert startup._gdb_thread is gdb_thread

class FakeServer:
    def __init__(self):
        self.deferred = []
        self.shutdown_threads = []
    def set_defer_events(self):
        self.deferred.append(threading.current_thread())
    def shutdown(self):
        self.shutdown_threads.append(threading.current_thread())

fake_server = FakeServer()
server._server = fake_server
executed = []
def fake_execute(command, **kwargs):
    executed.append((command, threading.current_thread()))
    return ""

gdb.execute = fake_execute
requests = queue.Queue()

def dispatch(command):
    response = queue.Queue(maxsize=1)
    requests.put((command, response))
    ok, result = response.get(timeout=3)
    if not ok:
        raise result
    return result

server.send_gdb_with_response = dispatch

def run_case(pid, terminate):
    executed.clear()
    fake_server.deferred.clear()
    fake_server.shutdown_threads.clear()
    gdb.selected_inferior = lambda: types.SimpleNamespace(pid=pid)
    result = queue.Queue(maxsize=1)
    worker = threading.Thread(
        target=lambda: _invoke(worker, terminate, result),
        name="mock-dap-thread",
    )
    startup._dap_thread = worker
    worker.start()
    while worker.is_alive() or not requests.empty():
        try:
            command, response = requests.get(timeout=0.02)
        except queue.Empty:
            continue
        try:
            if callable(command):
                value = command()
            else:
                gdb.execute(command, from_tty=True, to_string=True)
                value = None
            response.put((True, value))
        except BaseException as error:
            response.put((False, error))
    worker.join(timeout=1)
    assert not worker.is_alive(), "disconnect worker did not finish"
    success, value = result.get_nowait()
    assert success, value
    assert fake_server.deferred == [worker], "request must enter the DAP thread"
    assert fake_server.shutdown_threads == [worker], "shutdown must stay on the DAP thread"
    assert all(thread is gdb_thread for _, thread in executed), "GDB commands must execute on the GDB thread"
    return [command for command, _ in executed]

def _invoke(worker, terminate, result):
    try:
        value = server._commands["disconnect"](terminateDebuggee=terminate)
        result.put((True, value))
    except BaseException as error:
        result.put((False, error))

assert run_case(1234, False) == ["detach"], "disconnect(false) must detach an active inferior"
assert run_case(1234, True) == ["kill"], "disconnect(true) must keep terminating the inferior"
assert run_case(0, False) == [], "disconnect(false) with no inferior must not issue detach or kill"
print("Patched GDB DAP disconnect branches and thread dispatch passed")
]=]

local python_path = vim.fn.tempname() .. ".py"
assert(vim.fn.writefile(vim.split(python, "\n", { plain = true }), python_path) == 0)
vim.env.NVIM_GDB_DAP_DATA = data_dir
local command = "python exec(open(" .. string.format("%q", python_path) .. ").read())"
local output = vim.fn.system({ wrapper, "--quiet", "--nx", "--batch", "-ex", command })
vim.fn.delete(python_path)
assert(vim.v.shell_error == 0, "embedded GDB DAP regression failed: " .. output)
assert(output:find("Patched GDB DAP disconnect branches and thread dispatch passed", 1, true), output)
print("Patched GDB DAP false/true/no-inferior flow and stock binary wrapper passed")
