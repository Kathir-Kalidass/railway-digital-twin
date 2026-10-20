# Credits

Educational simulation only; not certified railway equipment.

## Core runtime
- Rail/train/camera runtime ported from **Libre-TrainSim** (https://libretrainsim.de),
  v0.9.beta1. Licensed **GPL v3** (see `LICENSE`). See `docs/porting/lts-port.md`
  for the port log.

## MQTT
- **goatchurchprime/godot-mqtt** (MIT). See `addons/godot-mqtt/LICENSE` and
  `addons/godot-mqtt/PINNED.txt`.

## Assets
| Asset | Kind | Source | License |
|---|---|---|---|
| (procedural terrain) | world | n/a | procedural fallback |
| (procedural trees/rocks) | scenery | n/a | procedural fallback |
| (procedural deer) | animal | n/a | procedural fallback |
| (procedural elephant) | animal | n/a | procedural fallback |

Replace `procedural fallback` rows with source URL + author + license (CC0/CC-BY)
when curated assets are added.

## Optional local runtime assets (not redistributed)

| Asset | Kind | Source | License |
|---|---|---|---|
| JFR1 locomotive (`Trains/JFR1/JFR1_Red.tscn`) | train | Libre-TrainSim v0.9.beta1 | GPL v3 (local only) |
| JFR1 wagon (`Trains/JFR1/JFR1_Grey.tscn`) | train | Libre-TrainSim v0.9.beta1 | GPL v3 (local only) |
| Street/highway bridges (`Resources/Objects/*.obj`) | scenery | Libre-TrainSim v0.9.beta1 | GPL v3 (local only) |

The runtime falls back to procedural geometry when these files are absent.
