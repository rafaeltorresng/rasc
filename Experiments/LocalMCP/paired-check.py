"""Exercise the paired fixture end to end over the Swift SDK's stdio transport."""

import base64
from contextlib import ExitStack
import json
import os
import select
import signal
import subprocess
import sys

ENDPOINT = "com.rafaeltorres.rasc.mcpspike"
THOUGHT_ID = "055D1B41-AF7E-4C06-A645-0C97B56980FE"


def make_key():
    return base64.b64encode(os.urandom(32)).decode("ascii")


def read_line(stream):
    if not select.select([stream], [], [], 5)[0]:
        raise TimeoutError("Sent a request but received no reply")
    result = stream.readline()
    if not result:
        raise RuntimeError("Probe exited before replying")
    return result


def stop(process):
    if process.poll() is None:
        process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()


class Client:
    def __init__(self, stack, path, key):
        self.process = stack.enter_context(subprocess.Popen(
            [path, "--mach", ENDPOINT],
            env={**os.environ, "RASC_SPIKE_PAIR_KEY": key},
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            text=True,
        ))
        stack.callback(stop, self.process)
        self.request_id = 0
        result = self.send("initialize", {
            "protocolVersion": "2025-11-25",
            "capabilities": {},
            "clientInfo": {"name": "paired fixture test", "version": "1"},
        })
        assert result["protocolVersion"] == "2025-11-25", result
        self.send("notifications/initialized", notification=True)
        result = self.send("tools/list")
        assert {tool["name"] for tool in result["tools"]} == {"search_thoughts", "get_thought"}, result

    def send(self, method, parameters=None, notification=False):
        self.request_id += 1
        request = {"jsonrpc": "2.0", "method": method}
        if not notification:
            request["id"] = self.request_id
        if parameters is not None:
            request["params"] = parameters
        self.process.stdin.write(json.dumps(request) + "\n")
        self.process.stdin.flush()
        if notification:
            return None
        response = json.loads(read_line(self.process.stdout))
        assert response["id"] == self.request_id and "result" in response, response
        return response["result"]

    def call(self, tool, key, value):
        return self.send("tools/call", {
            "name": tool,
            "arguments": {key: value},
        })["content"][0]["text"]

    def close(self):
        self.process.stdin.close()
        assert self.process.wait(timeout=5) == 0


def main(host_path, helper_path):
    key = make_key()
    with ExitStack() as stack:
        host = stack.enter_context(subprocess.Popen(
            [host_path], env={**os.environ, "RASC_SPIKE_PAIR_KEY": key},
            stdout=subprocess.PIPE, text=True,
        ))
        stack.callback(stop, host)
        assert read_line(host.stdout).strip() == "READY"
        permitted = Client(stack, helper_path, key)
        unauthorized = Client(stack, helper_path, make_key())
        assert permitted.call("search_thoughts", "query", "teal") == THOUGHT_ID
        assert permitted.call("get_thought", "id", THOUGHT_ID) == "Synthetic approved text"
        assert permitted.call("get_thought", "id", "unshared") == "Thought unavailable"
        assert unauthorized.call("get_thought", "id", THOUGHT_ID) == "Rasc IPC unavailable"
        host.send_signal(signal.SIGUSR1)
        assert read_line(host.stdout).strip() == "REVOKED"
        assert permitted.call("get_thought", "id", THOUGHT_ID) == "Thought unavailable"
        unauthorized.close()
        permitted.close()
    print("Paired lookup passed. Wrong keys and revoked access returned no note content.")


if __name__ == "__main__":
    main(*sys.argv[1:])
