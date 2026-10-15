#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_EXECUTABLE="${GODOT_BIN:-godot}"

# Opcional: templates instalados fora da pasta padrão do usuário.
if [[ -n "${GODOT_TEMPLATE_DATA:-}" ]]; then
  export XDG_DATA_HOME="$GODOT_TEMPLATE_DATA"
elif [[ -d "$PROJECT_DIR/../.tools/share/godot/export_templates" ]]; then
  export XDG_DATA_HOME="$PROJECT_DIR/../.tools/share"
fi

mkdir -p "$PROJECT_DIR/build/web"
"$GODOT_EXECUTABLE" --headless --path "$PROJECT_DIR" --editor --import --quit
"$GODOT_EXECUTABLE" --headless --path "$PROJECT_DIR" --export-release "Web" "$PROJECT_DIR/build/web/index.html"
touch "$PROJECT_DIR/build/web/.nojekyll"
echo "Build pronto em $PROJECT_DIR/build/web/index.html"

