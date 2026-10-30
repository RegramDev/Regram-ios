#!/usr/bin/env python3
"""Private signing inputs and App Store Connect TestFlight publication."""
import argparse
import base64
import datetime
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

from prepare import PROFILE_SUFFIXES, validate_configuration

API = "https://api.appstoreconnect.apple.com"


def private_write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    path.write_bytes(content if isinstance(content, bytes) else content.encode())
    path.chmod(0o600)


def mask(value):
    if value and os.environ.get("GITHUB_ACTIONS") == "true":
        escaped = str(value).replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
        print("::add-mask::" + escaped, flush=True)


class Connect:
    def __init__(self):
        self.key_id = os.environ["ASC_KEY_ID"]
        self.issuer = os.environ["ASC_ISSUER_ID"]
        self.key_path = Path(os.environ["ASC_KEY_PATH"])

    def token(self):
        from cryptography.hazmat.primitives.asymmetric.ec import ECDSA
        from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
        from cryptography.hazmat.primitives.hashes import SHA256
        from cryptography.hazmat.primitives.serialization import load_pem_private_key

        def encode(value):
            return base64.urlsafe_b64encode(value).rstrip(b"=")

        now = int(time.time())
        header = encode(json.dumps({"alg": "ES256", "kid": self.key_id, "typ": "JWT"}).encode())
        claims = encode(json.dumps({"iss": self.issuer, "iat": now, "exp": now + 600,
                                    "aud": "appstoreconnect-v1"}).encode())
        message = header + b"." + claims
        key = load_pem_private_key(self.key_path.read_bytes(), password=None)
        r, s = decode_dss_signature(key.sign(message, ECDSA(SHA256())))
        return (message + b"." + encode(r.to_bytes(32, "big") + s.to_bytes(32, "big"))).decode()

    def request(self, method, path, data=None):
        url = API + path if path.startswith("/") else path
        if urllib.parse.urlsplit(url).netloc != urllib.parse.urlsplit(API).netloc:
            raise ValueError("Unexpected App Store Connect pagination host")
        for attempt in range(5):
            request = urllib.request.Request(
                url, method=method, data=None if data is None else json.dumps(data).encode(),
                headers={"Authorization": "Bearer " + self.token(), "Content-Type": "application/json"},
            )
            try:
                with urllib.request.urlopen(request, timeout=60) as response:
                    body = response.read()
                    return json.loads(body) if body else {}
            except urllib.error.HTTPError as error:
                # Raw Apple errors can contain signing identities and account details.
                if method == "GET" and (error.code == 429 or error.code >= 500) and attempt < 4:
                    time.sleep(min(30, 2 ** attempt * 2))
                    continue
                raise RuntimeError(f"App Store Connect {method} failed (HTTP {error.code})") from None

    def all(self, path, **params):
        url = path + ("?" + urllib.parse.urlencode(params) if params else "")
        rows = []
        while url:
            response = self.request("GET", url)
            rows.extend(response["data"])
            url = response.get("links", {}).get("next")
        return rows


def resource(kind, identifier):
    return {"type": kind, "id": identifier}


def next_build(client, app_id, declared):
    candidates = [int(declared) - 1]
    for row in client.all("/v1/builds", **{"filter[app]": app_id, "limit": 200}):
        value = str(row["attributes"]["version"])
        if value.isdigit():
            candidates.append(int(value))
    # Uploads in processing may not have a builds resource yet.
    for row in client.all(f"/v1/apps/{app_id}/buildUploads", limit=200):
        value = str(row["attributes"]["cfBundleVersion"])
        if value.isdigit():
            candidates.append(int(value))
    return max(candidates) + 1


def signing_configuration(source, team, bundle, app):
    config = dict(validate_configuration(source))
    config.update(
        telegram_team_id=team, telegram_bundle_id=bundle, telegram_appstore_id=app,
        telegram_is_appstore_build="true", telegram_is_internal_build="false",
        telegram_aps_environment="production", telegram_enable_watch=False,
        telegram_use_xcode_managed_codesigning=False,
        # The newly registered app uses the capabilities provisioned for this workflow.
        telegram_enable_siri=False, telegram_enable_icloud=False,
    )
    return validate_configuration(config)


def prepare_inputs(root):
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.serialization.pkcs12 import load_key_and_certificates
    from cryptography.x509.oid import NameOID

    names = ("REGRAM_BUILD_CONFIGURATION", "APPLE_TEAM_ID", "ASC_APP_ID", "ASC_KEY_ID",
             "ASC_ISSUER_ID", "ASC_KEY_P8_BASE64", "DIST_CERT_P12_BASE64", "DIST_CERT_PASSWORD")
    for name in names:
        if not os.environ.get(name):
            raise ValueError("Missing repository secret: " + name)
        mask(os.environ[name])
    config = signing_configuration(
        json.loads(os.environ["REGRAM_BUILD_CONFIGURATION"]), os.environ["APPLE_TEAM_ID"],
        os.environ["BUNDLE_ID"], os.environ["ASC_APP_ID"],
    )
    # Mask individual configuration values as well as the containing JSON secret.
    for value in config.values():
        if isinstance(value, str) and len(value) >= 8:
            mask(value)
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    private_write(root / "configuration.json", json.dumps(config))
    p12 = base64.b64decode(os.environ["DIST_CERT_P12_BASE64"], validate=True)
    private_write(root / "distribution.p12", p12)
    key, cert, _ = load_key_and_certificates(p12, os.environ["DIST_CERT_PASSWORD"].encode())
    if key is None or cert is None:
        raise ValueError("Distribution certificate must include its private key")
    teams = cert.subject.get_attributes_for_oid(NameOID.ORGANIZATIONAL_UNIT_NAME)
    if not teams or teams[0].value != config["telegram_team_id"]:
        raise ValueError("Distribution certificate belongs to a different signing team")
    for attribute in cert.subject:
        mask(attribute.value)
    fingerprint = cert.fingerprint(hashes.SHA1()).hex().upper()
    mask(fingerprint)
    private_write(root / "identity", fingerprint)
    private_write(root / "distribution.cer", cert.public_bytes(serialization.Encoding.DER))
    key_path = root / "private_keys" / f"AuthKey_{os.environ['ASC_KEY_ID']}.p8"
    private_write(key_path, base64.b64decode(os.environ["ASC_KEY_P8_BASE64"], validate=True))
    private_write(root / "api-key.json", json.dumps({
        "key_id": os.environ["ASC_KEY_ID"], "issuer_id": os.environ["ASC_ISSUER_ID"],
        "key": key_path.read_text(), "in_house": False,
    }))
    if os.environ.get("GITHUB_ENV"):
        with open(os.environ["GITHUB_ENV"], "a") as env:
            env.write(f"ASC_KEY_PATH={key_path.resolve()}\n")
    print("Prepared private TestFlight signing inputs")


def validate_profile(profile, config, suffix, certificate):
    entitlements = profile["Entitlements"]
    expected = config["telegram_team_id"] + "." + config["telegram_bundle_id"] + suffix
    if (entitlements.get("application-identifier") != expected
            or profile.get("TeamIdentifier") != [config["telegram_team_id"]]
            or certificate not in profile.get("DeveloperCertificates", [])
            or profile.get("ProvisionedDevices") or profile.get("ProvisionsAllDevices")
            or entitlements.get("get-task-allow", False)
            or entitlements.get("com.apple.security.application-groups") != ["group." + config["telegram_bundle_id"]]):
        raise ValueError("Provisioning profile does not match the App Store signing contract")
    if profile["ExpirationDate"].replace(tzinfo=datetime.timezone.utc) <= datetime.datetime.now(datetime.timezone.utc):
        raise ValueError("Provisioning profile has expired")
    if not suffix and (entitlements.get("aps-environment") != "production"
                       or not entitlements.get("com.apple.developer.usernotifications.communication")):
        raise ValueError("Main app profile is missing production notification capabilities")
    # Restricted capabilities are inherited only when Apple's profile grants them.
    # In particular, a new app cannot inherit another app's NSE filtering approval.


def provisioning(client, root):
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes

    config = json.loads((root / "configuration.json").read_text())
    app = client.request("GET", "/v1/apps/" + config["telegram_appstore_id"])["data"]
    if app["attributes"]["bundleId"] != config["telegram_bundle_id"]:
        raise ValueError("App Store Connect app and bundle identifier differ")
    fingerprint = (root / "identity").read_text()
    certificates = client.all("/v1/certificates", **{"filter[certificateType]": "DISTRIBUTION", "limit": 200})
    certificate = next((c for c in certificates if x509.load_der_x509_certificate(
        base64.b64decode(c["attributes"]["certificateContent"])
    ).fingerprint(hashes.SHA1()).hex().upper() == fingerprint), None)
    if not certificate:
        raise ValueError("Imported distribution certificate is not active in this account")
    certificate_data = base64.b64decode(certificate["attributes"]["certificateContent"])
    for name, suffix in PROFILE_SUFFIXES.items():
        identifier = config["telegram_bundle_id"] + suffix
        bundles = client.all("/v1/bundleIds", **{"filter[identifier]": identifier})
        bundle = next((b for b in bundles if b["attributes"]["identifier"] == identifier), None)
        if bundle is None:
            raise ValueError("Missing registered bundle for " + name)
        candidates = client.all(f"/v1/bundleIds/{bundle['id']}/profiles", limit=200)
        selected = None
        for row in candidates:
            attrs = row["attributes"]
            if attrs["profileType"] != "IOS_APP_STORE" or attrs["profileState"] != "ACTIVE":
                continue
            content = base64.b64decode(attrs["profileContent"])
            profile = decode_profile(content)
            try:
                validate_profile(profile, config, suffix, certificate_data)
            except ValueError:
                continue
            selected = (content, profile)
            break
        if selected is None:
            row = client.request("POST", "/v1/profiles", {"data": {
                "type": "profiles",
                "attributes": {"name": f"Regram TestFlight {name} {int(time.time())}",
                               "profileType": "IOS_APP_STORE"},
                "relationships": {
                    "bundleId": {"data": resource("bundleIds", bundle["id"])},
                    "certificates": {"data": [resource("certificates", certificate["id"])]},
                },
            }})["data"]
            content = base64.b64decode(row["attributes"]["profileContent"])
            selected = (content, decode_profile(content))
            validate_profile(selected[1], config, suffix, certificate_data)
        for key in ("Name", "UUID", "TeamName"):
            mask(selected[1].get(key))
        private_write(root / "profiles" / (name + ".mobileprovision"), selected[0])
    print("Verified App Store profiles for the app and all six extensions")


def decode_profile(content):
    result = subprocess.run(["openssl", "cms", "-verify", "-noverify", "-inform", "DER"],
                            input=content, capture_output=True)
    if result.returncode:
        raise ValueError("Could not decode provisioning profile")
    return plistlib.loads(result.stdout)


def build_configuration(root, destination, bazel):
    config = validate_configuration(json.loads((root / "configuration.json").read_text()))
    destination.mkdir(parents=True, exist_ok=True, mode=0o700)
    private_write(destination / "WORKSPACE", "")
    private_write(destination / "MODULE.bazel", 'module(name = "build_configuration")\n')
    private_write(destination / "BUILD", "")
    lines = ["telegram_bazel_path = " + json.dumps(str(bazel.resolve()))]
    for name, value in sorted(config.items()):
        lines.append(name + " = " + (repr(value) if isinstance(value, bool) else json.dumps(value)))
    private_write(destination / "variables.bzl", "\n".join(lines) + "\n")
    profiles = destination / "provisioning"
    profiles.mkdir(exist_ok=True)
    private_write(profiles / "BUILD", 'exports_files(glob(["*.mobileprovision"]))\n')
    for name in PROFILE_SUFFIXES:
        shutil.copyfile(root / "profiles" / (name + ".mobileprovision"), profiles / (name + ".mobileprovision"))


def release_notes(path):
    text = path.read_text().strip()
    if not text or len(text) > 4000:
        raise ValueError("What to Test notes must contain between 1 and 4000 characters")
    return text


def verify_ipa(root):
    config = json.loads((root / "configuration.json").read_text())
    versions = json.loads(Path("versions.json").read_text())
    with tempfile.TemporaryDirectory() as temporary:
        result = subprocess.run(
            ["unzip", "-q", "bazel-bin/Telegram/Regram.ipa", "-d", temporary], capture_output=True)
        if result.returncode:
            raise ValueError("Could not extract signed IPA")
        apps = list((Path(temporary) / "Payload").glob("*.app"))
        if len(apps) != 1:
            raise ValueError("Signed IPA must contain exactly one app")
        app = apps[0]
        bundles = [app] + list((app / "PlugIns").glob("*.appex"))
        expected = {config["telegram_bundle_id"] + suffix for suffix in PROFILE_SUFFIXES.values()}
        found = set()
        for bundle in bundles:
            info = plistlib.loads((bundle / "Info.plist").read_bytes())
            found.add(info["CFBundleIdentifier"])
            if (str(info["CFBundleVersion"]) != os.environ["BUILD_NUMBER"]
                    or info["CFBundleShortVersionString"] != versions["app"]):
                raise ValueError("Signed app and extension versions must match the selected release")
            profile = decode_profile((bundle / "embedded.mobileprovision").read_bytes())
            suffix = info["CFBundleIdentifier"][len(config["telegram_bundle_id"]):]
            validate_profile(profile, config, suffix, (root / "distribution.cer").read_bytes())
            result = subprocess.run(["codesign", "--verify", "--strict", str(bundle)], capture_output=True)
            if result.returncode:
                raise ValueError("App Store signature verification failed")
            signed = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(bundle)], capture_output=True)
            if signed.returncode:
                raise ValueError("Could not read signed entitlements")
            entitlements = plistlib.loads(signed.stdout)
            if (entitlements.get("com.apple.security.application-groups") != ["group." + config["telegram_bundle_id"]]
                    or entitlements.get("application-identifier") != config["telegram_team_id"] + "." + info["CFBundleIdentifier"]
                    or entitlements.get("get-task-allow", False)):
                raise ValueError("Signed entitlements do not match the distribution configuration")
            prefix = str(Path(temporary) / ("signer-" + bundle.name))
            result = subprocess.run(["codesign", "-d", "--extract-certificates=" + prefix, str(bundle)],
                                    capture_output=True)
            if result.returncode or Path(prefix + "0").read_bytes() != (root / "distribution.cer").read_bytes():
                raise ValueError("Signed bundle does not use the selected distribution certificate")
        if len(bundles) != 7 or found != expected:
            raise ValueError("Signed IPA must include the app and all six registered extensions")
    print("Verified signed IPA, App Store profiles, and versions for all seven bundles")


def wait_for_build(client, app, build, version, timeout=3600):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        rows = client.all("/v1/builds", **{
            "filter[app]": app, "filter[version]": str(build),
            "filter[preReleaseVersion.version]": version, "limit": 200,
        })
        if len(rows) > 1:
            raise ValueError("The selected build is ambiguous")
        if rows:
            row = rows[0]
            state = row["attributes"]["processingState"]
            if state == "VALID":
                return row
            if state in ("FAILED", "INVALID"):
                raise ValueError("Apple rejected build processing: " + state)
        print("Waiting for Apple to finish processing the selected build", flush=True)
        time.sleep(30)
    raise TimeoutError("Apple has not finished processing; retry distribute mode with this build number")


def distribute(client, app, group_name, build, version, notes):
    groups = client.all(f"/v1/apps/{app}/betaGroups", limit=200)
    groups = [g for g in groups if g["attributes"]["name"] == group_name
              and not g["attributes"]["isInternalGroup"]]
    if len(groups) != 1:
        raise ValueError("Configure exactly one matching external TestFlight group")
    row = wait_for_build(client, app, build, version)
    build_id = row["id"]
    localizations = client.all(f"/v1/builds/{build_id}/betaBuildLocalizations")
    existing = next((l for l in localizations if l["attributes"]["locale"] == "en-US"), None)
    if existing:
        client.request("PATCH", "/v1/betaBuildLocalizations/" + existing["id"], {"data": {
            **resource("betaBuildLocalizations", existing["id"]), "attributes": {"whatsNew": notes},
        }})
    else:
        client.request("POST", "/v1/betaBuildLocalizations", {"data": {
            "type": "betaBuildLocalizations", "attributes": {"locale": "en-US", "whatsNew": notes},
            "relationships": {"build": {"data": resource("builds", build_id)}},
        }})
    detail = client.request("GET", f"/v1/builds/{build_id}/buildBetaDetail")["data"]
    if not detail["attributes"].get("autoNotifyEnabled"):
        client.request("PATCH", "/v1/buildBetaDetails/" + detail["id"], {"data": {
            **resource("buildBetaDetails", detail["id"]), "attributes": {"autoNotifyEnabled": True},
        }})
    members = client.all(f"/v1/betaGroups/{groups[0]['id']}/builds", limit=200)
    if not any(member["id"] == build_id for member in members):
        client.request("POST", f"/v1/betaGroups/{groups[0]['id']}/relationships/builds",
                       {"data": [resource("builds", build_id)]})
    # VALID can precede Apple's application of the existing encryption declaration.
    for attempt in range(20):
        detail = client.request("GET", f"/v1/builds/{build_id}/buildBetaDetail")["data"]
        if detail["attributes"]["externalBuildState"] not in (
            "PROCESSING", "IN_EXPORT_COMPLIANCE_REVIEW", "MISSING_EXPORT_COMPLIANCE",
        ):
            break
        print("Waiting for the external beta state to settle", flush=True)
        time.sleep(15)
    state = detail["attributes"]["externalBuildState"]
    if state == "READY_FOR_BETA_SUBMISSION":
        client.request("POST", "/v1/betaAppReviewSubmissions", {"data": {
            "type": "betaAppReviewSubmissions",
            "relationships": {"build": {"data": resource("builds", build_id)}},
        }})
        print("Build submitted to Beta App Review; external availability awaits Apple approval")
    elif state in ("IN_BETA_TESTING", "BETA_APPROVED", "READY_FOR_BETA_TESTING"):
        print("Build is approved and attached to the external TestFlight group")
    elif state in ("WAITING_FOR_BETA_REVIEW", "IN_BETA_REVIEW"):
        print("Build is attached to the external group and awaiting Beta App Review")
    else:
        raise ValueError("External TestFlight needs attention: " + state)
    members = client.all(f"/v1/betaGroups/{groups[0]['id']}/builds", limit=200)
    if not any(member["id"] == build_id for member in members):
        raise ValueError("Apple did not retain the build's external group membership")
    print("Verified external TestFlight group membership")


def invite_internal_testers(client, app):
    # Apple keeps internal testers NOT_INVITED until the first installable build exists.
    invited = failed = 0
    for group in client.all(f"/v1/apps/{app}/betaGroups", limit=200):
        if not group["attributes"]["isInternalGroup"]:
            continue
        for tester in client.all(f"/v1/betaGroups/{group['id']}/betaTesters", limit=200):
            if tester["attributes"].get("state") != "NOT_INVITED":
                continue
            try:
                client.request("POST", "/v1/betaTesterInvitations", {"data": {
                    "type": "betaTesterInvitations", "relationships": {
                        "app": {"data": resource("apps", app)},
                        "betaTester": {"data": resource("betaTesters", tester["id"])},
                    },
                }})
                invited += 1
            except RuntimeError:
                failed += 1
    print(f"Invited {invited} pending internal tester(s)")
    if failed:
        print(f"::warning::{failed} internal invitation(s) were not accepted yet; rerun distribute later")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["prepare", "profiles", "configure", "next-build", "distribute", "notes", "verify"])
    parser.add_argument("--root", type=Path, default=Path("build-input/testflight"))
    parser.add_argument("--bazel", type=Path)
    parser.add_argument("--build")
    parser.add_argument("--notes", type=Path, default=Path("build-system/ci/testflight-notes.txt"))
    args = parser.parse_args()
    versions = json.loads(Path("versions.json").read_text())
    if args.command == "prepare":
        prepare_inputs(args.root)
    elif args.command == "configure":
        build_configuration(args.root, Path("build-input/configuration-repository"), args.bazel)
    elif args.command == "notes":
        release_notes(args.notes)
        print("What to Test notes validated")
    elif args.command == "verify":
        verify_ipa(args.root)
    elif args.command == "profiles":
        provisioning(Connect(), args.root)
    elif args.command == "next-build":
        number = next_build(Connect(), os.environ["ASC_APP_ID"], versions["build"])
        with open(os.environ["GITHUB_ENV"], "a") as env:
            env.write(f"BUILD_NUMBER={number}\n")
        print("Selected TestFlight build number:", number)
    elif args.command == "distribute":
        build = args.build or os.environ.get("BUILD_NUMBER", "")
        if not re.fullmatch(r"[0-9]+", build):
            raise ValueError("A numeric build number is required for distribution")
        distribute(Connect(), os.environ["ASC_APP_ID"], os.environ["TESTFLIGHT_GROUP"],
                   build, versions["app"], release_notes(args.notes))
        invite_internal_testers(Connect(), os.environ["ASC_APP_ID"])


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # Only deliberately constructed errors are safe to expose in a public workflow.
        if type(error) in (ValueError, RuntimeError, TimeoutError):
            print("TestFlight failed:", str(error), flush=True)
        else:
            print("TestFlight failed; verify private configuration and Apple account access", flush=True)
        raise SystemExit(1) from None
