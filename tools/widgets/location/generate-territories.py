"""Generate regional territory records using verified Blizzard client CSVs.

Only Python's standard library is needed. Inputs are local exports; the generator
does not fetch data, and neither Python nor the CSVs is a runtime dependency.
Version/interface/build metadata describes the source snapshots, not runtime eligibility.
"""
from __future__ import annotations

import argparse
import csv
from hashlib import sha256
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[3]
DEFAULT_OUTPUT = ROOT / "src" / "menubar-location" / "TerritoryData.lua"
VERIFIED_BUILDS = ("70938", "70959", "71037")
# These five English exports are byte-identical in all three verified snapshots.
SNAPSHOT_SHA256 = {
    "AreaTable": "9aac5960ef4b8f3c01d9f46f399628ce7bb633ff865709d59fb59d9ce4cb43df",
    "UiMap": "1f4aac70eaac015b1d2d0ea0faf6e3d7fb2cf7afdf45e5bb6772d9b80a72346b",
    "UiMapAssignment": "79267e8be8034e47daab14350411b3acc0b1f64e86efc9d821a217497254ca0a",
    "FactionGroup": "a1e2887c5ca36138be6b6439701a8a9229c97e8c67bebc23711b04ef87ce9dbc",
    "Map": "a4fa6474f5bba3dc815f0e78943b3a907840b8f44bba605d4ff0680048994908",
}


# Forever outdoor zone records explicitly marked Contested, keyed by AreaTable ID.
# https://kovarel.com/wow-forever/zones (outdoor territory and area IDs)
# The client exports below supply the canonical UiMap assignments. A zero faction
# mask alone is ambiguous in subzones, dungeons and unmapped areas.
CONTESTED_AREA_IDS = {
    # Eastern Kingdoms
    3,      # Badlands
    4,      # Blasted Lands
    8,      # Swamp of Sorrows
    10,     # Duskwood
    11,     # Wetlands
    28,     # Western Plaguelands
    33,     # Stranglethorn Vale
    36,     # Alterac Mountains
    41,     # Deadwind Pass
    44,     # Redridge Mountains
    45,     # Arathi Highlands
    46,     # Burning Steppes
    47,     # The Hinterlands
    51,     # Searing Gorge
    139,    # Eastern Plaguelands
    267,    # Hillsbrad Foothills
    16591,  # Riverglades
    # Kalimdor
    15,     # Dustwallow Marsh
    16,     # Azshara
    331,    # Ashenvale
    357,    # Feralas
    361,    # Felwood
    400,    # Thousand Needles
    405,    # Desolace
    406,    # Stonetalon Mountains
    440,    # Tanaris
    490,    # Un'Goro Crater
    493,    # Moonglade
    616,    # Mount Hyjal
    618,    # Winterspring
    1377,   # Silithus
    16651,  # Shen'dralas
}


def rows(path: Path, table: str) -> list[dict[str, str]]:
    data = path.read_bytes()
    if sha256(data).hexdigest() != SNAPSHOT_SHA256[table]:
        raise ValueError(f"{table}: input is not one of the verified English snapshots")
    with path.open(encoding="utf-8-sig", newline="") as source:
        return list(csv.DictReader(source))


def integer(row: dict[str, str], field: str) -> int:
    try:
        return int(row[field])
    except (KeyError, TypeError, ValueError) as error:
        raise ValueError(f"Invalid {field} in row {row.get('ID', '?')}") from error


def index(entries: list[dict[str, str]], table: str) -> dict[int, dict[str, str]]:
    result = {}
    for row in entries:
        key = integer(row, "ID")
        if key in result:
            raise ValueError(f"{table}: duplicate ID {key}")
        result[key] = row
    return result


def territories(inputs: dict[str, Path]) -> dict[int, tuple[int, int, str, str]]:
    tables = {name: rows(path, name) for name, path in inputs.items()}
    areas = index(tables["AreaTable"], "AreaTable")
    ui_maps = index(tables["UiMap"], "UiMap")
    maps = index(tables["Map"], "Map")
    groups = index(tables["FactionGroup"], "FactionGroup")
    assignments = index(tables["UiMapAssignment"], "UiMapAssignment")
    factions = {}
    for group in groups.values():
        owner = group["InternalName"]
        if owner in ("Alliance", "Horde"):
            mask_id = integer(group, "MaskID")
            if not 0 <= mask_id <= 7:
                raise ValueError("Invalid faction mask index")
            mask = 1 << mask_id
            if mask in factions:
                raise ValueError("Duplicate faction mask")
            factions[mask] = owner
    if factions != {2: "Alliance", 4: "Horde"}:
        raise ValueError("Faction masks differ from the verified mapping")

    result = {}
    for assignment in assignments.values():
        area_id = integer(assignment, "AreaID")
        ui_map_id = integer(assignment, "UiMapID")
        world_map_id = integer(assignment, "MapID")
        area, ui_map, world_map = areas.get(area_id), ui_maps.get(ui_map_id), maps.get(world_map_id)
        if not area or not ui_map or not world_map:
            continue
        mask = integer(area, "FactionGroupMask")
        field, value = "owner", factions.get(mask)
        if mask == 0 and area_id in CONTESTED_AREA_IDS:
            field, value = "classification", "contested"
        if integer(area, "ParentAreaID") != 0 or value is None:
            continue
        if world_map_id not in (0, 1) or integer(world_map, "InstanceType") != 0:
            continue
        if integer(ui_map, "Type") != 3:
            continue
        if integer(area, "ContinentID") != world_map_id:
            raise ValueError(f"Area/map world mismatch for UiMap {ui_map_id}")
        if not area["AreaName_lang"] or area["AreaName_lang"] != ui_map["Name_lang"]:
            raise ValueError(f"Localized area/map names differ for UiMap {ui_map_id}")
        record = (area_id, world_map_id, field, value)
        if ui_map_id in result and result[ui_map_id] != record:
            raise ValueError(f"Conflicting assignments for UiMap {ui_map_id}")
        result[ui_map_id] = record
    contested = {area_id for area_id, _, _, value in result.values() if value == "contested"}
    if contested != CONTESTED_AREA_IDS:
        raise ValueError(f"Missing verified contested area assignments: {sorted(CONTESTED_AREA_IDS - contested)}")
    if len(result) != 17 + len(CONTESTED_AREA_IDS):
        raise ValueError(f"Unexpected number of verified regional maps: {len(result)}")
    return result


def render(entries: dict[int, tuple[int, int, str, str]]) -> bytes:
    lines = [
        "-- Generated by tools/widgets/location/generate-territories.py.",
        "-- Regional territory defaults. Live PvP classifications take precedence.",
        "-- The generator records source hashes, classifications and selection rules.",
        "_G.MenubarLocationTerritories = {",
        '    version = "1.60.1",',
        "    interface = 16001,",
        "    verifiedBuilds = {",
    ]
    lines.extend(f'        ["{build}"] = true,' for build in VERIFIED_BUILDS)
    lines.extend(("    },", "    maps = {"))
    for ui_map_id, (area_id, world_map_id, field, value) in sorted(entries.items()):
        lines.append(f'        [{ui_map_id}] = {{ areaID = {area_id}, worldMapID = {world_map_id}, {field} = "{value}" }},')
    lines.extend(("    },", "}", "", "return _G.MenubarLocationTerritories", ""))
    return "\n".join(lines).encode("utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--area-table", type=Path, required=True)
    parser.add_argument("--ui-map", type=Path, required=True)
    parser.add_argument("--assignments", type=Path, required=True)
    parser.add_argument("--faction-group", type=Path, required=True)
    parser.add_argument("--map", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--check", action="store_true", help="Verify the output without modifying it")
    args = parser.parse_args()
    inputs = {"AreaTable": args.area_table, "UiMap": args.ui_map, "UiMapAssignment": args.assignments,
              "FactionGroup": args.faction_group, "Map": args.map}
    try:
        entries = territories(inputs)
        output = render(entries)
        if args.check:
            if args.output.read_bytes() != output:
                raise ValueError("TerritoryData.lua differs from the verified generated output")
            print(f"Verified {len(entries)} territory records: {args.output}")
        else:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_bytes(output)
            print(f"Generated {len(entries)} territory records: {args.output}")
    except (OSError, KeyError, ValueError) as error:
        parser.error(str(error))
    return 0


if __name__ == "__main__":
    sys.exit(main())
