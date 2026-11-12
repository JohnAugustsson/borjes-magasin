#!/usr/bin/env python3
"""Build an installable addon ZIP and CurseForge metadata; never upload anything."""

import argparse
import json
from pathlib import Path
import re
import zipfile


ADDON = "borjes-magasin"
ROOT = Path(__file__).resolve().parents[1]


def build(root, output, tag=None):
    addon = root / ADDON
    toc = (addon / f"{ADDON}.toc").read_text(encoding="utf-8")
    fields = dict(re.findall(r"^## ([\w-]+):\s*(.+)$", toc, re.MULTILINE))
    version = fields["Version"].strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+(?:-(?:alpha|beta|rc)\.\d+)?", version):
        raise ValueError("Expected a numeric addon version, optionally -alpha.N/-beta.N/-rc.N")
    data = (addon / "Data.lua").read_text(encoding="utf-8")
    runtime_version = re.search(r'BM\.VERSION\s*=\s*"([^"]+)"', data)
    if not runtime_version or runtime_version[1] != version:
        raise ValueError("TOC and Data.lua versions must match")
    if tag is not None and tag != f"v{version}":
        raise ValueError(f"Release tag must be v{version}, got {tag}")
    if fields["Interface"].strip() != "16001":
        raise ValueError("Update the CurseForge game version mapping for the new Interface")
    if fields["X-Curse-Project-ID"].strip() != "1796534":
        raise ValueError("Unexpected CurseForge project ID")

    changelog = (root / "CHANGELOG.md").read_text(encoding="utf-8")
    section = re.search(
        rf"^## {re.escape(version)}(?:[ \t]+[^\n]*)?\n(.*?)(?=^## |\Z)",
        changelog, re.MULTILINE | re.DOTALL,
    )
    if not section or not section[1].strip():
        raise ValueError(f"Missing changelog section for {version}")

    # Package only TOC-listed runtime files, the icon and these two documents.
    # Never recursively copy the checkout or include local SavedVariables.
    paths = [f"{ADDON}.toc", "Textures/MinimapIcon.tga"]
    paths += [line.strip().replace("\\", "/") for line in toc.splitlines()
              if line.strip() and not line.lstrip().startswith("#")]
    entries = {}
    for name in paths:
        source = addon / name
        if source.is_symlink() or not source.resolve().is_relative_to(addon.resolve()):
            raise ValueError(f"Runtime file must stay inside the addon: {name}")
        entries[f"{ADDON}/{name}"] = source.read_bytes()
    for name in ("README.md", "CHANGELOG.md"):
        entries[f"{ADDON}/{name}"] = (root / name).read_bytes()

    output.mkdir(parents=True, exist_ok=True)
    archive = output / f"{ADDON}-{version}.zip"
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as package:
        for name, data in sorted(entries.items()):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            package.writestr(info, data)

    metadata = {
        "displayName": archive.name,
        "changelog": section[1].strip(),
        "changelogType": "markdown",
        "gameVersionNames": ["1.60.1"],
        # Keep the existing project's Beta release classification.
        "releaseType": "alpha" if "-alpha." in version else "beta",
        "isMarkedForManualRelease": False,
    }
    (output / "metadata.json").write_text(
        json.dumps(metadata, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    return archive


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "dist" / "ci")
    parser.add_argument("--tag", help="Require this release tag to match the addon version")
    args = parser.parse_args()
    try:
        archive = build(ROOT, args.output, args.tag)
    except (ValueError, OSError, KeyError) as error:
        parser.exit(1, f"Packaging failed: {error}\n")
    print(f"Built {archive} ({archive.stat().st_size} bytes); nothing uploaded")
