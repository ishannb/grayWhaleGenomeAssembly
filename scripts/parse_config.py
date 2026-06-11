#!/usr/bin/env python3
"""
parse_config.py — Reads config.yaml and prints shell-compatible exports.

Usage (from any bash script):
    eval $(python3 scripts/parse_config.py config/config.yaml)

This avoids duplicating YAML parsing logic across every bash script.
"""

import sys
import yaml
import os

def flatten(config, prefix=""):
    """Recursively flatten nested YAML into VARNAME=value pairs."""
    lines = []
    for key, val in config.items():
        varname = (prefix + "_" + key).upper().lstrip("_")
        if isinstance(val, dict):
            lines.extend(flatten(val, varname))
        elif isinstance(val, list):
            # Export lists as space-separated strings
            joined = " ".join(str(v) for v in val)
            lines.append(f'export {varname}="{joined}"')
        elif val is None or val == "":
            lines.append(f'export {varname}=""')
        else:
            lines.append(f'export {varname}="{val}"')
    return lines

def main():
    if len(sys.argv) < 2:
        print("Usage: parse_config.py <config.yaml>", file=sys.stderr)
        sys.exit(1)

    config_path = sys.argv[1]
    if not os.path.exists(config_path):
        print(f"ERROR: config file not found: {config_path}", file=sys.stderr)
        sys.exit(1)

    with open(config_path) as f:
        config = yaml.safe_load(f)

    for line in flatten(config):
        print(line)

if __name__ == "__main__":
    main()
