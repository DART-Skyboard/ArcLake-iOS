#!/usr/bin/env python3
"""
XcodeGen doesn't correctly generate the "Embed App Clips" copy-files
destination for an on-demand-install-capable target dependency — it embeds
it like a generic app extension (dstSubfolderSpec=13, empty dstPath, i.e.
PlugIns/) instead of the App-Clip-specific destination Apple actually
requires (dstSubfolderSpec=16, dstPath="$(CONTENTS_FOLDER_PATH)/AppClips").
That mismatch is what App Store Connect's validator was reporting as a
missing WKApplication key — it couldn't recognize the embedded bundle as a
proper App Clip. This patches the generated project.pbxproj directly, right
after `xcodegen generate`, targeting only the specific copy-files phase that
references ArcLakeClip.app so nothing else in the project is touched.
"""
import re
import sys

path = "ArcLake.xcodeproj/project.pbxproj"
with open(path) as f:
    text = f.read()

# Find the PBXCopyFilesBuildPhase block that embeds ArcLakeClip.app
pattern = re.compile(
    r'(\w+ /\* [^*]*Embed[^*]* \*/ = \{\s*isa = PBXCopyFilesBuildPhase;.*?files = \(\s*\w+ /\* ArcLakeClip\.app[^*]*\*/,.*?\};)',
    re.DOTALL
)

match = pattern.search(text)
if not match:
    print("WARNING: could not find the ArcLakeClip.app copy-files phase — nothing patched.")
    sys.exit(0)

block = match.group(1)
new_block = block
new_block = re.sub(r'dstPath = "[^"]*";', 'dstPath = "$(CONTENTS_FOLDER_PATH)/AppClips";', new_block)
new_block = re.sub(r'dstSubfolderSpec = \d+;', 'dstSubfolderSpec = 16;', new_block)

if new_block == block:
    print("WARNING: pattern matched but no substitution occurred — check the block format.")
else:
    text = text.replace(block, new_block)
    with open(path, "w") as f:
        f.write(text)
    print("Patched Embed App Clips destination: dstSubfolderSpec=16, dstPath=$(CONTENTS_FOLDER_PATH)/AppClips")
