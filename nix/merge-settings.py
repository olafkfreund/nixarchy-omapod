"""Merge declarative settings without overwriting changes made in omaPOD."""

import json
import sys

from omapod.config import _atomic_write, instance_lock, paths


MISSING = object()


def read_object(path):
    try:
        with open(path, encoding="utf-8") as handle:
            value = json.load(handle)
    except (OSError, ValueError):
        return MISSING
    return value if isinstance(value, dict) else MISSING


def write_object(path, value):
    _atomic_write(path, json.dumps(value, indent=2, sort_keys=True) + "\n")


def main():
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <declared.json>", file=sys.stderr)
        return 2
    declared = read_object(sys.argv[1])
    if declared is MISSING:
        print("omaPOD: declared settings are unreadable or not an object", file=sys.stderr)
        return 1

    lock = instance_lock("nix-settings")
    if lock is None:
        print("omaPOD is running; settings apply at next login or rebuild")
        return 0
    with lock:
        settings_path = paths.settings_file
        sidecar_path = paths.config / ".nix-settings.json"
        original = read_object(settings_path)
        if original is MISSING and settings_path.exists():
            print("omaPOD: settings.json is unreadable or not an object; leaving it alone", file=sys.stderr)
            return 0
        if original is MISSING:
            original = {}
        prior = read_object(sidecar_path)
        has_sidecar = prior is not MISSING
        recorded = dict(prior) if has_sidecar else {}
        settings = dict(original)

        for key, value in declared.items():
            current = settings.get(key, MISSING)
            previous = recorded.get(key, MISSING)
            if current is MISSING or (has_sidecar and current == previous):
                settings[key] = value
                recorded[key] = value
            elif has_sidecar and current == value:
                recorded[key] = value

        for key, previous in list(recorded.items()):
            if key not in declared:
                if settings.get(key, MISSING) == previous:
                    settings.pop(key, None)
                del recorded[key]

        if settings != original:
            write_object(settings_path, settings)
        if prior is MISSING or recorded != prior:
            write_object(sidecar_path, recorded)
    return 0


if __name__ == "__main__":
    sys.exit(main())
