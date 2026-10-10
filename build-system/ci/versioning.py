#!/usr/bin/env python3
"""Resolve the declared Regram build number, independent of Actions run counters."""
import argparse
import json
import os
from pathlib import Path

VERSIONS = Path(__file__).resolve().parents[2] / 'versions.json'


def build_number(versions=VERSIONS, expected=None):
    value = json.loads(versions.read_text()).get('build')
    if type(value) is not int or not 1 <= value <= 2147483647:
        raise ValueError('versions.json must define a positive integer build number')
    number = str(value)
    if expected is not None and expected != number:
        raise ValueError('REGRAM_BUILD_NUMBER must match the build number declared in versions.json')
    return number


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--github-env', type=Path)
    args = parser.parse_args()
    number = build_number(expected=os.environ.get('REGRAM_BUILD_NUMBER'))
    if args.github_env:
        with args.github_env.open('a') as stream:
            stream.write(f'REGRAM_BUILD_NUMBER={number}\n')
    print(number)


if __name__ == '__main__':
    main()
