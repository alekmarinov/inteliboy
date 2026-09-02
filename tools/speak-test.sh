#!/bin/bash
# Have the device read phrases to itself, and report what it made of them.
#
#     tools/speak-test.sh 192.168.1.168
#
# It speaks each phrase through its own speaker and reads the trace back. That
# works because the device hears itself — the same missing echo cancellation
# that makes barge-in impossible makes this test possible, which is worth
# saying out loud rather than relying on quietly.
#
# What it is and is not: synthetic speech at speaker-to-microphone distance is
# the easiest input this device will ever get. A phrase that fails here fails
# everywhere. A phrase that passes here may still fail from across the room,
# which is where the recogniser actually has to work.
set -u
HOST=${1:?usage: speak-test.sh <host>}
SSH=(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
     -o ConnectTimeout=8 "root@$HOST")

# expected-intent|phrase.  "-" means it should escalate.
PHRASES=(
  "greeting|Hello."
  "thanks|Thank you."
  "get_time|What time is it?"
  "get_date|What is the date?"
  "volume_up|Turn the volume up."
  "volume_down|Turn the volume down."
  "mute|Mute."
  "unmute|Unmute."
  "set_volume|Set the volume to forty."
  "power_off|Power off."
  "-|Why is the sea salty?"
)

printf "  %-28s %-12s %s\n" "SAID" "EXPECTED" "WHAT IT DID"
pass=0; fail=0
for entry in "${PHRASES[@]}"; do
    want=${entry%%|*}; phrase=${entry#*|}
    before=$("${SSH[@]}" 'wc -l < /var/log/cogiti-trace.jsonl 2>/dev/null || echo 0')

    "${SSH[@]}" "timeout 90 /usr/bin/inteliboy-say '$phrase' >/dev/null 2>&1 && \
                 timeout 60 aplay -q /run/inteliboy-say.wav 2>/dev/null" >/dev/null 2>&1

    # Collect *every* turn the phrase produced, not just the last.
    #
    # One phrase does not mean one turn. The device hears its own answer as
    # well — that is the missing echo cancellation — so "turn the volume down"
    # produces the turn you wanted and then a second one from the reply. Taking
    # tail -1 reports the echo and calls the real answer a failure, which is
    # what the first version of this script did.
    got=""
    for _ in $(seq 1 40); do
        now=$("${SSH[@]}" 'wc -l < /var/log/cogiti-trace.jsonl 2>/dev/null || echo 0')
        if [ "$now" -gt "$before" ]; then break; fi
        sleep 2
    done
    sleep 6                       # let any echo turns land too
    now=$("${SSH[@]}" 'wc -l < /var/log/cogiti-trace.jsonl 2>/dev/null || echo 0')
    if [ "$now" -le "$before" ]; then
        printf "  %-26s %-12s %-28s\n" "${phrase:0:24}" "$want" "(not heard at all)"
        fail=$((fail+1)); continue
    fi
    got=$("${SSH[@]}" "tail -n +$((before+1)) /var/log/cogiti-trace.jsonl")

    # A phrase matches if ANY of its turns resolved as intended; the rest are
    # reported as extra so the echo is visible rather than hidden.
    read -r hit turns detail <<<"$(printf '%s' "$got" | python3 -c "
import sys, json
want = '$want'
hit, rows = 0, []
for line in sys.stdin:
    line = line.strip()
    if not line.startswith('{'): continue
    d = json.loads(line); r = d.get('resolved') or {}
    v, i = r.get('verdict','-'), r.get('intent') or '-'
    if (want == '-' and v == 'escalate') or (want != '-' and i == want and v != 'escalate'):
        hit = 1
    rows.append('%s->%s/%s@%sms' % (d.get('said','')[:20].replace(' ','_'), v, i, d.get('ms',0)))
print(hit, len(rows), ' | '.join(rows[:3]))")"

    if [ "$hit" = "1" ]; then ok="ok "; pass=$((pass+1)); else ok="   "; fail=$((fail+1)); fi
    printf "%s%-26s %-12s %s turn(s): %s\n" "  $ok" "${phrase:0:24}" "$want" "$turns" "$detail"
done
echo
echo "  $pass matched, $fail did not"
