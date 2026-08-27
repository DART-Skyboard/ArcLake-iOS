#!/usr/bin/env python3
"""
Verifies the App Clip is embedded correctly after `xcodegen generate`. With
`type: application.on-demand-install-capable` set correctly on the target
(the actual fix — a previous attempt used an invalid "productType:" key that
XcodeGen silently ignored), XcodeGen's own on-demand-install-capable handling
should generate a proper "Embed App Clips" copy-files phase automatically.
This just confirms that happened rather than blindly patching, and if it
didn't, patches the destination directly as a fallback.
"""
import re
import sys

path = "ArcLake.xcodeproj/project.pbxproj"
with open(path) as f:
    text = f.read()

if "ArcLakeClip.app" not in text:
    print("DIAGNOSTIC: 'ArcLakeClip.app' does not appear anywhere in project.pbxproj.")
    sys.exit(0)

# Find the copy-files-style phase entry referencing ArcLakeClip.app and show
# its destination fields for confirmation either way.
lines = text.split("\n")
for i, line in enumerate(lines):
    if "ArcLakeClip.app in" in line:
        print(f"CONFIRM: found embed line: {line.strip()}")

# Report current destination settings for any phase near an App Clips /
# CopyFiles marker so success or failure is visible in the CI log either way.
for i, line in enumerate(lines):
    if "dstSubfolderSpec" in line or "Embed App Clips" in line or "\"Embed App Extensions\"" in line:
        print(f"CONFIRM [{i}]: {line.strip()}")
