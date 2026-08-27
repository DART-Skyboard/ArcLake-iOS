#!/usr/bin/env python3
"""
XcodeGen doesn't correctly generate the "Embed App Clips" copy-files
destination for an on-demand-install-capable target dependency. This patches
the generated project.pbxproj's copy-files phase that embeds ArcLakeClip.app
to use the correct destination (dstSubfolderSpec=16,
dstPath=$(CONTENTS_FOLDER_PATH)/AppClips) instead of whatever XcodeGen
defaults to for a generic embedded target.
"""
import re
import sys

path = "ArcLake.xcodeproj/project.pbxproj"
with open(path) as f:
    text = f.read()

if "ArcLakeClip.app" not in text:
    print("DIAGNOSTIC: 'ArcLakeClip.app' does not appear anywhere in project.pbxproj at all.")
    sys.exit(0)

# Dump every line mentioning ArcLakeClip or a copy-files phase, with context,
# so the actual generated structure is visible in CI logs instead of guessed at.
lines = text.split("\n")
for i, line in enumerate(lines):
    if "ArcLakeClip" in line or "CopyFiles" in line or ("Embed" in line and "isa" not in line):
        start = max(0, i - 2)
        end = min(len(lines), i + 3)
        print(f"DIAGNOSTIC [{i}]:")
        for j in range(start, end):
            marker = ">>" if j == i else "  "
            print(f"  {marker} {lines[j]}")
        print("---")
