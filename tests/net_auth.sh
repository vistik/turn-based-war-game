#!/bin/sh
# Passwords and hole punching for online play: two copies on this computer (AI on both sides).
#   1. the same password: they play into round 2 and agree;
#   2. a wrong password: the joiner is turned away and told why;
#   3. the joiner sends from a fixed port that the host "lets in", as over the internet.
#   GODOT=/path/to/Godot tests/net_auth.sh [port]
# Run from the project folder. Exits non-zero if anything doesn't match.

GODOT=${GODOT:-godot}
PORT=${1:-26100}
DIR=$(mktemp -d)
FAILED=0

expect() {
	if sh -c "$2"; then echo "ok: $1"; else echo "FAIL: $1"; FAILED=1; fi
}

play() {
	# play NAME HOST_ARGS JOIN_ARGS
	"$GODOT" --headless --path . -s tests/net_match.gd -- host "$PORT" $2 "--save-dir=$DIR/$1-host" > "$DIR/$1-host.log" 2>&1 &
	HOST_PID=$!
	sleep 1
	"$GODOT" --headless --path . -s tests/net_match.gd -- join "$PORT" $3 "--save-dir=$DIR/$1-join" > "$DIR/$1-join.log" 2>&1
	sleep 2
	kill $HOST_PID 2>/dev/null
	wait $HOST_PID 2>/dev/null
	grep -E "SCRIPT ERROR|Parse Error" "$DIR/$1-host.log" "$DIR/$1-join.log" && FAILED=1
}

play right "44 stop 2 --password=fox-hole" "stop 2 --password=fox-hole"
expect "the right password gets in and both agree" "grep -q '^LEFT' $DIR/right-host.log && grep -q '^LEFT' $DIR/right-join.log && ! grep -q DESYNC $DIR/right-join.log"

play wrong "44 --password=fox-hole" "refused --password=foxhole"
expect "a wrong password is turned away" "grep -q '^REFUSED: Wrong password.' $DIR/wrong-join.log"
expect "the host never started" "! grep -qE '^(LEFT|FINISHED|STOPPED)' $DIR/wrong-host.log"

play punched "44 stop 2 --password=p --local-port=$((PORT + 7))" "stop 2 --password=p --local-port=$((PORT + 7))"
expect "a joiner sending from a fixed port gets in" "grep -q '^LEFT' $DIR/punched-host.log && grep -q '^LEFT' $DIR/punched-join.log"

if [ $FAILED -eq 0 ]; then
	rm -rf "$DIR"
	echo "ALL PASSED"
else
	echo "SOME CHECKS FAILED, logs in $DIR"
fi
exit $FAILED
