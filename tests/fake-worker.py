#!/usr/bin/env python3
import json
import os
import sys

mode = os.environ["KEYBOARD_SOUND_TEST_MODE"]
if mode == "crash":
    sys.exit(3)
if mode == "error":
    print("Test audio device unavailable.", file=sys.stderr, flush=True)

with open(os.environ["KEYBOARD_SOUND_TEST_LOG"], "a", encoding="utf-8") as log:
    for line in sys.stdin:
        json.loads(line)
        log.write(line)
        log.flush()
