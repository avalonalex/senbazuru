#!/usr/bin/env python3
"""Export the checked examples for the standard glTF preview, from repo root."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("destination", nargs="?", default="build/gltf-preview")
args = parser.parse_args()
destination = Path(args.destination)
destination.mkdir(parents=True, exist_ok=True)
dist = subprocess.check_output(["stack", "path", "--dist-dir"], text=True).strip()
executable = Path(dist) / "build" / "senbazuru" / "senbazuru"
if not executable.is_file():
    raise SystemExit("Run stack build first.")

models = []

def export(title, filename, source, *options):
    subprocess.run([str(executable), "export", source, *options,
                    "-o", str(destination / filename)], check=True)
    models.append({"title": title, "path": filename})

for name in ["book-base", "quarter-fold", "square-base", "waterbomb-base",
             "fish-base", "bird-base", "helmet-base", "organ-base", "frog-base",
             "boat-base", "pig-base", "diamond-base", "thirds-pinwheel", "crane"]:
    export(name.replace("-", " "), name + ".glb", "examples/" + name + ".fold", "--fold")
for state in range(1, 17):
    export(f"Bird checkpoint {state}", f"bird-{state}.glb",
           "examples/bird-base-sequence.fold", "--frame", str(state))

(destination / "models.json").write_text(json.dumps(models, indent=2) + "\n")
shutil.copyfile("study/gltf/viewer.html", destination / "index.html")
print(f"Wrote {len(models)} GLBs and index.html to {destination}")
