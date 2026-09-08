#!/bin/bash
# Release regression: real loopback SMB I/O; does not touch a running App/Simulator.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
python=${SMB_FIXTURE_PYTHON:-python3}
"$python" -c 'import impacket' || { echo 'Set SMB_FIXTURE_PYTHON to a Python with impacket installed.' >&2; exit 1; }
out=$(mktemp -d)
server_pid=
cleanup() { if [[ -n "$server_pid" ]]; then kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true; fi; rm -rf "$out"; }
trap cleanup EXIT
swift build --package-path "$root" --product AMSMB2
bin=$(swift build --package-path "$root" --show-bin-path)
swiftc -O -I"$bin/Modules" -I"$root/Dependencies/libsmb2/include" -L"$bin" -lAMSMB2 \
  -Xlinker -rpath -Xlinker "$bin" "$root/Tests/ReadMemoryRegression.swift" -o "$out/probe"
"$python" "$root/Tests/read_memory_fixture.py" "$out" >"$out/server.log" 2>&1 &
server_pid=$!
for ((i=0;i<100;i++)); do
  [[ -s "$out/port" ]] && break
  kill -0 "$server_pid" 2>/dev/null || { cat "$out/server.log" >&2; exit 1; }
  sleep 0.1
done
[[ -s "$out/port" ]] || { echo 'SMB fixture startup timed out' >&2; exit 1; }
"$out/probe" "$(cat "$out/port")"
