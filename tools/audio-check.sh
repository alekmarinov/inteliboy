#!/bin/sh
# Where the sound stops, on a development workstation.
#
# The chain from a synthesised wav to a speaker has four links here, and each
# one fails with a different message that does not name the link. This walks
# them in order and says which is broken.
#
#   avatari  ->  ALSA 'default'  ->  PulseAudio  ->  WSLg  ->  Windows
#
# On the appliance none of this applies: there is a real sound card, ALSA talks
# to it directly, and /etc/avatari.conf already sets audio.enabled = true.
echo "audio chain:"

# 1. a real card, which WSL2 does not have
if aplay -l 2>/dev/null | grep -q "^card"; then
    echo "  [ok]   ALSA sees a sound card"
    HAVE_CARD=1
else
    echo "  [--]   no ALSA sound card (normal under WSL2 — audio comes via WSLg)"
    HAVE_CARD=
fi

# 2. the plugin that lets ALSA reach PulseAudio
if ls /usr/lib/*/alsa-lib/libasound_module_pcm_pulse.so >/dev/null 2>&1; then
    echo "  [ok]   ALSA->PulseAudio plugin installed"
else
    echo "  [FAIL] ALSA->PulseAudio plugin missing"
    echo "         sudo apt install libasound2-plugins"
    exit 1
fi

# 3. the config that routes 'default' through it. Without this avatari opens
#    'default', finds nothing and plays silently — the mouth still moves, which
#    is exactly why this is easy to misread as a cogiti problem.
if [ -f "$HOME/.asoundrc" ] && grep -q "type pulse" "$HOME/.asoundrc" 2>/dev/null; then
    echo "  [ok]   ~/.asoundrc routes default -> pulse"
elif [ -n "$HAVE_CARD" ]; then
    echo "  [--]   no ~/.asoundrc, but there is a real card, so none is needed"
else
    echo "  [FAIL] no ~/.asoundrc routing default -> pulse, and no card either"
    echo "         avatari will report: no playback device 'default'"
    exit 1
fi

# 4. the server itself
if pactl info >/dev/null 2>&1; then
    echo "  [ok]   PulseAudio answers"
    echo "  sinks: $(pactl list short sinks 2>/dev/null | wc -l)"
    echo
    echo "the chain is whole — 'make face AUDIO=1' should be audible."
    exit 0
fi

echo "  [FAIL] PulseAudio is not answering"
if ss -xl 2>/dev/null | grep -q "PulseServer"; then
    echo "         Its socket is listening but it refuses connections, so the"
    echo "         server is wedged rather than absent. WSLg starts it and only"
    echo "         a WSL restart restarts it:"
    echo
    echo "             (in Windows PowerShell)  wsl --shutdown"
    echo "             then reopen the terminal"
else
    echo "         No PulseServer socket at all. Is WSLg running?"
fi
echo
echo "Until then the mouth still moves and the line is silent, which is the"
echo "renderer behaving correctly: lipsync never depended on playback."
exit 1
