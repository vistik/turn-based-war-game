#!/bin/sh
# Continuing an online game: two copies play a few rounds (AI on both sides), both leave, both start again
# and continue from their saves, and play to the end with matching checksums. Then the same saves are
# continued by a joiner with no save of its own (it adopts the host's), by a joiner whose loaded game
# differs (both must refuse to play on), and with the players swapping who hosts. Each copy keeps its
# saves in its own temporary folder, never the player's.
#   GODOT=/path/to/Godot tests/net_resume.sh [port] [map size]
# Run from the project folder. Exits non-zero if anything doesn't match.

GODOT=${GODOT:-godot}
PORT=${1:-26000}
SIZE=${2:-44}
DIR=$(mktemp -d)
FAILED=0

run_pair() {
	# run_pair NAME HOST_DIR JOIN_DIR HOST_ARGS JOIN_ARGS
	"$GODOT" --headless --path . -s tests/net_match.gd -- host "$PORT" $4 "--save-dir=$2" > "$DIR/$1-host.log" 2>&1 &
	HOST_PID=$!
	sleep 1
	"$GODOT" --headless --path . -s tests/net_match.gd -- join "$PORT" $5 "--save-dir=$3" > "$DIR/$1-join.log" 2>&1
	wait $HOST_PID
	echo "--- $1"
	grep -E "^(LEFT|OFFERED|JOINER|RESUMED|FINISHED|STOPPED|DESYNC|DISCONNECTED|NO SAVE)" "$DIR/$1-host.log" | sed 's/^/host: /'
	grep -E "^(LEFT|OFFERED|JOINER|RESUMED|FINISHED|STOPPED|DESYNC|DISCONNECTED|NO SAVE)" "$DIR/$1-join.log" | sed 's/^/join: /'
	grep -E "SCRIPT ERROR|Parse Error" "$DIR/$1-host.log" "$DIR/$1-join.log" && FAILED=1
}

final_checksum() {
	grep "^FINISHED" "$1" | sed 's/.*checksum \([0-9a-f]*\).*/\1/'
}

expect() {
	# expect DESCRIPTION COMMAND...
	if sh -c "$2"; then echo "ok: $1"; else echo "FAIL: $1"; FAILED=1; fi
}

# 1. Play into round 3, then both leave. Both saves must be of the same, agreed state.
run_pair first "$DIR/host" "$DIR/join" "$SIZE stop 3" "stop 3"
HOST_SAVED=$(grep '^LEFT' "$DIR/first-host.log" | sed 's/.*saved //')
JOIN_SAVED=$(grep '^LEFT' "$DIR/first-join.log" | sed 's/.*saved //')
expect "both saved the same state ($HOST_SAVED)" "[ -n '$HOST_SAVED' ] && [ '$HOST_SAVED' = '$JOIN_SAVED' ] && ! echo '$HOST_SAVED' | grep -q none"
cp -R "$DIR/host" "$DIR/host-copy"
cp -R "$DIR/host" "$DIR/host-copy2"
cp -R "$DIR/join" "$DIR/join-copy"
cp -R "$DIR/host" "$DIR/host-copy3"
cp -R "$DIR/join" "$DIR/join-copy3"

# 2. Both start again and continue from their own saves, then play to the end.
run_pair resumed "$DIR/host" "$DIR/join" "resume" "resume"
expect "the joiner's save matched the host's" "grep -q 'JOINER: saves match' $DIR/resumed-join.log"
expect "both finished with the same checksum" "[ -n \"$(final_checksum "$DIR/resumed-host.log")\" ] && [ \"$(final_checksum "$DIR/resumed-host.log")\" = \"$(final_checksum "$DIR/resumed-join.log")\" ]"
expect "the finished game cleared both saves" "[ ! -f $DIR/host/online.sav ] && [ ! -f $DIR/join/online.sav ]"

# 3. A joiner with no save adopts the host's and the game finishes the same way.
run_pair adopted "$DIR/host-copy" "$DIR/empty" "resume" "resume"
expect "the joiner without a save adopted the host's" "grep -q 'JOINER: You have no saved online game' $DIR/adopted-join.log"
expect "adopted game finished with the same checksum" "[ -n \"$(final_checksum "$DIR/adopted-host.log")\" ] && [ \"$(final_checksum "$DIR/adopted-host.log")\" = \"$(final_checksum "$DIR/adopted-join.log")\" ]"

# 4. A joiner whose loaded game differs: neither side plays on, and both keep their saves.
run_pair tampered "$DIR/host-copy2" "$DIR/join-copy" "resume" "resume tamper"
expect "the host refused the different game" "grep -q 'DESYNC DETECTED' $DIR/tampered-host.log && ! grep -q '^RESUMED' $DIR/tampered-host.log"
expect "the joiner was told" "grep -q 'DESYNC DETECTED' $DIR/tampered-join.log && ! grep -q '^RESUMED' $DIR/tampered-join.log"
expect "both saves were kept" "[ -f $DIR/host-copy2/online.sav ] && [ -f $DIR/join-copy/online.sav ]"

# 5. The player who joined before hosts this time: each keeps their side.
run_pair swapped "$DIR/join-copy3" "$DIR/host-copy3" "resume" "resume"
expect "swapped hosts: saves match" "grep -q 'JOINER: saves match' $DIR/swapped-join.log"
expect "swapped hosts finished with the same checksum" "[ -n \"$(final_checksum "$DIR/swapped-host.log")\" ] && [ \"$(final_checksum "$DIR/swapped-host.log")\" = \"$(final_checksum "$DIR/swapped-join.log")\" ]"

if [ $FAILED -eq 0 ]; then
	rm -rf "$DIR"
	echo "ALL PASSED"
else
	echo "SOME CHECKS FAILED, logs and saves in $DIR"
fi
exit $FAILED
