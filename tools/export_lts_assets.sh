#!/usr/bin/env bash
# Regenerate the Godot-ready GLB copies of the Libre-TrainSim Blender library.
# Requires blender on PATH. Outputs are intentionally git-ignored; keep them
# local and treat the procedural fallbacks as the portable path.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lts="$root/Libre-TrainSim-master/src/Resources/Blender"
out="$root/godot/assets/models/lts"
blender="${BLENDER:-blender}"

if [[ ! -d "$lts" ]]; then
	echo "missing $lts" >&2
	exit 1
fi

mkdir -p "$out"

export_one() {
	local name="$1" file="$2" select="${3:-}" tints="${4:-}"
	echo "== $name"
	LTS_OUT="$out/$name.glb" LTS_SELECT="$select" LTS_TINTS="$tints" timeout 600 \
		"$blender" -b "$lts/$file" -P "$root/tools/export_lts_assets.py" |
		grep -E "LTS EXPORT|Error" || true
}

export_one wagon_passenger "Wagon_1.blend" "Wagon"
export_one wagon_locomotive "Wagon_1_WithDriverStand.blend" \
	"Wagon_half,Dooor,Scheibenwischer,Cube.001,Cube.002,Cube.003"
# Upstream tree .blend files reference missing leaf textures; tools/build_trees.py
# generates the self-contained foliage instead.
export_one platform "Platform.blend" "" "Pflasterstein=0.40,0.40,0.38;Stripe=0.92,0.78,0.12;Side=0.32,0.32,0.30;Metal=0.55,0.56,0.58"
export_one platform_double "Platform_double.blend"
export_one house "House1.blend"
export_one office "Office1.blend"
export_one signal_hp "Hp-Sig.blend"
export_one signal_hl "Hl-Sig.blend"
export_one pole "Pole1.blend"
export_one pole_double "Pole1_double.blend"
export_one rail_bridge "RailBridge.blend"
export_one road_bridge "Subway_Bridge_WithEdges.blend"
export_one tunnel "Tunnel_1.blend"
export_one bench "Bench.blend" "" "Wood=0.45,0.30,0.16;Beton=0.45,0.45,0.43;Metal=0.35,0.36,0.38;Human=0.62,0.48,0.36"
export_one garbage "Garbage.blend" "" "OrangeMetal=0.85,0.35,0.05;Material=0.18,0.19,0.20"
export_one speed_sign "Speed_Sign.blend"

ls -lh "$out" | tail -n +2
