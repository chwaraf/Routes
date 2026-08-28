#!/usr/bin/env bash
# Build the installable Routes addon zip from the current repo state.
# Usage: tools/build-zip.sh
# Outputs:
#   /home/user/Routes.zip          (workspace copy, if the workspace root is writable)
#   <repo>/dist/Routes.zip         (committed + pushed, the GitHub access path)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
OUT_WS=/home/user/Routes.zip
A3MIRROR="https://github.com/aby-ui/repo-base.git"
HBD="https://github.com/Nevcairiel/HereBeDragons.git"

mkdir -p "$WORK/Routes/Libs"
cd "$WORK/Routes"

# --- addon files (no build metadata, no .git) ---
cp "$REPO/Routes.toc" "$REPO/Routes.lua" "$REPO/Routes.xml" "$REPO/TSP.lua" \
   "$REPO/NodeSkill.lua" "$REPO/Bindings.xml" "$REPO/line.tga" .
cp -r "$REPO/Locales" "$REPO/Modules" "$REPO/Plugins" .

# --- Libs: Ace3 (full copy) + HereBeDragons ---
if [ ! -d "/tmp/ace3full/!!!Libs/Ace3" ]; then
  rm -rf /tmp/ace3full
  git clone --quiet --depth 1 --filter=blob:none --sparse "$A3MIRROR" /tmp/ace3full
  (cd /tmp/ace3full && git sparse-checkout set --skip-checks "!!!Libs/Ace3")
fi
if [ ! -f /tmp/hbd/HereBeDragons-2.0.lua ]; then
  rm -rf /tmp/hbd
  git clone --quiet --depth 1 "$HBD" /tmp/hbd
fi

A3="/tmp/ace3full/!!!Libs/Ace3"
for lib in LibStub CallbackHandler-1.0 AceAddon-3.0 AceConfig-3.0 AceConsole-3.0 \
           AceDB-3.0 AceEvent-3.0 AceGUI-3.0 AceHook-3.0 AceLocale-3.0; do
  cp -r "$A3/$lib" Libs/
done
# .xml wrappers missing from the mirror (official trunk has them; one-line includes)
for pair in "CallbackHandler-1.0 CallbackHandler-1.0" "AceAddon-3.0 AceAddon-3.0" \
            "AceDB-3.0 AceDB-3.0" "AceEvent-3.0 AceEvent-3.0" "AceHook-3.0 AceHook-3.0" \
            "AceLocale-3.0 AceLocale-3.0" "AceConsole-3.0 AceConsole-3.0"; do
  set -- $pair
  if [ ! -f "Libs/$1/$2.xml" ]; then
    printf '<Ui xmlns="http://www.blizzard.com/wow/ui/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.blizzard.com/wow/ui/\n..\\FrameXML\\UI.xsd">\n\t<Script file="%s.lua"/>\n</Ui>\n' "$2" > "Libs/$1/$2.xml"
  fi
done
mkdir -p Libs/HereBeDragons
cp /tmp/hbd/HereBeDragons-2.0.lua /tmp/hbd/HereBeDragons-Migrate.lua Libs/HereBeDragons/

# --- verify: every TOC entry + every XML include/script must resolve ---
python3 - <<'EOF'
import re, os, sys
root = '.'
errors = []
toc = open(f'{root}/Routes.toc', encoding='utf-8-sig').read()
for raw in toc.splitlines():
    line = raw.strip()
    if not line or line.startswith('#') or line.startswith('##'):
        continue
    if not os.path.isfile(os.path.join(root, line.replace('\\', '/'))):
        errors.append(f'TOC missing: {line}')

def check_xml(base, xml):
    path = os.path.join(base, xml)
    if not os.path.isfile(path):
        errors.append(f'XML missing: {path}'); return
    content = re.sub(r'<!--.*?-->', '', open(path, encoding='utf-8', errors='replace').read(), flags=re.S)
    for m in re.findall(r'<(?:Include|Script)\s+file="([^"]+)"', content):
        if not os.path.isfile(os.path.normpath(os.path.join(base, m.replace('\\', '/')))):
            errors.append(f'XML ref missing: {os.path.join(base, m)}')

check_xml(root, 'Routes.xml')
for lib in os.listdir(f'{root}/Libs'):
    libdir = os.path.join(root, 'Libs', lib)
    for f in os.listdir(libdir):
        if f.endswith('.xml'):
            check_xml(libdir, f)

if errors:
    print('BUILD VERIFICATION FAILED:')
    [print(' -', e) for e in errors]
    sys.exit(1)
n = sum(len(fs) for _, _, fs in os.walk(root))
print(f'verified: {n} files, all TOC entries and XML refs resolve')
EOF

# --- zip (Routes/ at the root) ---
# -X: omit extra file attributes (e.g. Unix UT timestamps) for maximum
#     compatibility with picky Windows unzip tools
cd "$WORK"
rm -f dist_zip.zip
zip -rXq dist_zip.zip Routes
echo "sha256: $(sha256sum dist_zip.zip | cut -d' ' -f1)  ($(stat -c%s dist_zip.zip) bytes)"

# --- workspace copy (best effort) ---
if [ -w /home/user ]; then
  cp dist_zip.zip "$OUT_WS"
  echo "workspace: $OUT_WS ($(du -h "$OUT_WS" | cut -f1))"
fi

# --- commit + push the dist/ copy (the GitHub access path) ---
mkdir -p "$REPO/dist"
if ! cmp -s dist_zip.zip "$REPO/dist/Routes.zip"; then
  cp dist_zip.zip "$REPO/dist/Routes.zip"
  cd "$REPO"
  git add dist/Routes.zip
  if ! git diff --cached --quiet; then
    git -c user.name="Arena Agent" -c user.email="arena@localhost" commit -q -m "dist: update Routes.zip addon package"
  fi
  BRANCH="$(git rev-parse --abbrev-ref HEAD)"
  git push origin "$BRANCH" 2>&1 | tail -1
  echo "published: https://github.com/chwaraf/Routes/blob/$BRANCH/dist/Routes.zip"
else
  echo "dist/Routes.zip already up to date"
fi

rm -rf "$WORK"
