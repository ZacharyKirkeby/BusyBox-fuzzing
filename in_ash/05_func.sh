trap 'exit 0' INT
f() { local z="internal"; return 0; }
f
