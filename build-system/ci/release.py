#!/usr/bin/env python3
"""Publish one explicitly approved IPA from a successful master build."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import zipfile


def command(args):
    return subprocess.check_output(args, text=True).strip()


def api(path):
    return json.loads(command(['gh', 'api', path]))


def filename_parts(filename):
    match = re.fullmatch(r'Regram-(\d+(?:\.\d+){1,3})-b([1-9]\d*)\.ipa', filename)
    if not match:
        raise ValueError('Use the exact Regram-version-bbuild.ipa filename')
    return match.groups()


def prepare(repository, run_id, filename, request_path):
    version, build = filename_parts(filename)
    if not re.fullmatch(r'[1-9]\d*', run_id):
        raise ValueError('The build run ID must be a positive integer')
    run = api(f'repos/{repository}/actions/runs/{run_id}')
    if (run['status'], run['conclusion'], run['head_branch'], run['path']) != (
            'completed', 'success', 'master', '.github/workflows/build.yml'):
        raise ValueError('Select a successful master run of Build Regram')
    if run['event'] not in ('push', 'workflow_dispatch') or run['head_repository']['full_name'] != repository:
        raise ValueError('Release artifacts must come from this repository master')
    sha = run['head_sha']
    if not re.fullmatch(r'[0-9a-f]{40}', sha):
        raise ValueError('Unexpected source commit')
    artifacts = api(f'repos/{repository}/actions/runs/{run_id}/artifacts?per_page=100')['artifacts']
    matches = [item for item in artifacts if item['name'] == filename and not item['expired']]
    if len(matches) != 1:
        raise ValueError('The exact approved IPA artifact is unavailable')
    artifact = matches[0]
    digest = artifact.get('digest', '')
    if not re.fullmatch(r'sha256:[0-9a-f]{64}', digest):
        raise ValueError('The IPA artifact must have a SHA-256 digest')
    request = {'repository': repository, 'filename': filename, 'version': version, 'build': build,
               'source_commit': sha, 'run_id': run_id, 'run_url': run['html_url'],
               'artifact_id': artifact['id'], 'sha256': digest.removeprefix('sha256:')}
    request_path.parent.mkdir(parents=True, exist_ok=True)
    request_path.write_text(json.dumps(request, indent=2) + '\n')
    if output := os.environ.get('GITHUB_OUTPUT'):
        with open(output, 'a') as stream:
            stream.write(f"artifact_id={artifact['id']}\n")
    print(f"Selected {filename} from {sha}")
    return request


def verify_ipa(path, request):
    version, build = filename_parts(path.name)
    if (path.name, version, build) != (request['filename'], request['version'], request['build']):
        raise ValueError('Downloaded IPA filename differs from the approved selection')
    with path.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    if digest != request['sha256']:
        raise ValueError('Downloaded IPA differs from the approved artifact digest')
    with zipfile.ZipFile(path) as archive:
        if archive.testzip() is not None:
            raise ValueError('IPA is corrupt')
        main_plists = [name for name in archive.namelist() if re.fullmatch(r'Payload/[^/]+\.app/Info\.plist', name)]
        if len(main_plists) != 1:
            raise ValueError('IPA must contain one main app')
        info = plistlib.loads(archive.read(main_plists[0]))
        if str(info['CFBundleShortVersionString']) != version or str(info['CFBundleVersion']) != build:
            raise ValueError('IPA version/build do not match its approved filename')
    return digest


def publish(request_path, directory, confirmed):
    if not confirmed:
        raise ValueError('Explicit confirmation is required before creating a Release')
    request = json.loads(request_path.read_text())
    repository = request['repository']
    if repository != os.environ.get('GITHUB_REPOSITORY'):
        raise ValueError('Release request belongs to another repository')
    files = list(directory.rglob('*'))
    files = [path for path in files if path.is_file()]
    if len(files) != 1:
        raise ValueError('Only the approved IPA may be included')
    digest = verify_ipa(files[0], request)
    tag = f"v{request['version']}-b{request['build']}"
    refs = api(f'repos/{repository}/git/matching-refs/tags/{tag}')
    if any(ref['ref'] == f'refs/tags/{tag}' for ref in refs):
        raise ValueError('Refusing to replace an existing release tag')
    notes = request_path.parent / 'notes.md'
    notes.write_text(f"{request['filename']}\n\nBuilt from `{request['source_commit']}`.\n\n"
                     f"[Build details]({request['run_url']})\n\nSHA-256: `{digest}`\n")
    command(['gh', 'release', 'create', tag, str(files[0]), '--repo', repository,
             '--target', request['source_commit'], '--title', f"Regram {request['version']} (b{request['build']})",
             '--notes-file', str(notes), '--draft'])
    release = json.loads(command(['gh', 'release', 'view', tag, '--repo', repository,
                                  '--json', 'isDraft,assets']))
    if not release['isDraft'] or [asset['name'] for asset in release['assets']] != [request['filename']]:
        raise ValueError('Release must contain exactly the approved IPA before publication')
    command(['gh', 'release', 'edit', tag, '--repo', repository, '--draft=false'])
    print(f"Published {tag}: {request['filename']}")


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest='action', required=True)
    selection = subparsers.add_parser('prepare')
    selection.add_argument('--run-id', required=True)
    selection.add_argument('--filename', required=True)
    selection.add_argument('--request', required=True, type=Path)
    publication = subparsers.add_parser('publish')
    publication.add_argument('--request', required=True, type=Path)
    publication.add_argument('--directory', required=True, type=Path)
    publication.add_argument('--confirmed', action='store_true')
    args = parser.parse_args()
    if args.action == 'prepare':
        prepare(os.environ['GITHUB_REPOSITORY'], args.run_id, args.filename, args.request)
    else:
        publish(args.request, args.directory, args.confirmed)
