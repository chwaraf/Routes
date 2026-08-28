#!/usr/bin/env bash
# One-shot sanity check for a fresh checkout (no deps beyond python3).
# Usage: tools/verify.sh [addon-root]
#   * Verifies every non-Libs TOC entry and every XML <Include/Script> ref resolves.
#   * If node + luaparse are available, also syntax-checks the core Lua files.
# Run from the repo root; defaults to the repo root as the addon root.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADDON="${1:-$ROOT}"

python3 - "$ADDON" <<'PY'
import re, os, sys
addon = sys.argv[1]
errors = []
tocpath = os.path.join(addon, 'Routes.toc')
if not os.path.isfile(tocpath):
    print('VERIFY FAILED: Routes.toc not found in', addon)
    sys.exit(1)
toc = open(tocpath, encoding='utf-8-sig').read()
for raw in toc.splitlines():
    line = raw.strip()
    if not line or line.startswith('#'):
        continue
    p = os.path.join(addon, line.replace('\\', '/'))
    if not os.path.isfile(p):
        if line.replace('\\', '/').startswith('Libs/'):
            continue  # external; fetched by tools/build-zip.sh at build time
        errors.append('TOC missing: ' + line)
def check_xml(base, xml):
    path = os.path.join(base, xml)
    if not os.path.isfile(path):
        errors.append('XML missing: ' + path); return
    content = re.sub(r'<!--.*?-->', '', open(path, encoding='utf-8', errors='replace').read(), flags=re.S)
    for m in re.findall(r'<(?:Include|Script)\s+file="([^"]+)"', content):
        target = os.path.normpath(os.path.join(base, m.replace('\\', '/')))
        if not os.path.isfile(target):
            errors.append('XML ref missing: ' + target)
for base, _dirs, files in os.walk(addon):
    for f in files:
        if f.endswith('.xml'):
            check_xml(base, f)
if errors:
    print('VERIFY FAILED:')
    for e in errors: print('  -', e)
    sys.exit(1)
print('TOC/XML OK (%s)' % os.path.basename(os.path.abspath(addon)))
PY

# Optional Lua syntax check if node + luaparse are available.
if command -v node >/dev/null 2>&1; then
  if (cd "$ROOT" && node -e "require('luaparse')" >/dev/null 2>&1); then
    node "$ROOT/tools/luacheck.js" \
      "$ADDON/Routes.lua" "$ADDON/TSP.lua" "$ADDON/NodeSkill.lua" \
      "$ADDON"/Modules/*.lua "$ADDON"/Plugins/*.lua "$ADDON"/Locales/*.lua \
      || echo "NOTE: some files failed the Lua parse check"
  else
    echo "NOTE: luaparse not installed - run 'cd $ROOT && npm install --no-save luaparse' for Lua syntax checks"
  fi
fi
