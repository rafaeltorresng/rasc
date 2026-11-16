#!/usr/bin/env python3
"""Verify Sparkle appcast lengths and Ed25519 signatures.

This intentionally uses OpenSSL instead of Sparkle so the proof does not depend
on the app launching. It also has an optional one-byte tamper check.

Examples:
    python3 Scripts/sparkle-proof/verify-appcast.py \
        --feed build/sparkle-proof/feed \
        --account rasc-sparkle \
        --tamper

    python3 Scripts/sparkle-proof/verify-appcast.py \
        --feed build/sparkle-proof/feed \
        --public-key public.pem \
        --tamper
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
NS = {"sparkle": SPARKLE_NS}


def run_openssl_verify(public_key: str, payload: str, signature: bytes) -> tuple[bool, str]:
    with tempfile.NamedTemporaryFile(delete=False) as handle:
        handle.write(signature)
        signature_path = handle.name
    try:
        result = subprocess.run(
            [
                "openssl",
                "pkeyutl",
                "-verify",
                "-pubin",
                "-inkey",
                public_key,
                "-rawin",
                "-in",
                payload,
                "-sigfile",
                signature_path,
            ],
            capture_output=True,
            text=True,
        )
        output = (result.stdout + result.stderr).strip()
        return result.returncode == 0, output
    finally:
        os.unlink(signature_path)


def sha256(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_feed(feed_dir: str, appcast_path: str, public_key: str) -> tuple[bool, list[tuple[str, str, bytes]]]:
    tree = ET.parse(appcast_path)
    root = tree.getroot()
    items = root.findall("./channel/item", NS)
    if not items:
        print(f"FAIL: no <item> elements in {appcast_path}")
        return False, []

    ok = True
    enclosures: list[tuple[str, str, bytes]] = []
    for item in items:
        version = item.findtext("sparkle:version", namespaces=NS) or "?"
        short_version = item.findtext("sparkle:shortVersionString", namespaces=NS) or "?"
        print(f"item version={version} shortVersion={short_version}")

        for enclosure in item.findall(".//enclosure"):
            url = enclosure.attrib.get("url", "")
            name = os.path.basename(url)
            payload = os.path.join(feed_dir, name)
            expected_length = enclosure.attrib.get("length")
            signature_b64 = enclosure.attrib.get(f"{{{SPARKLE_NS}}}edSignature")

            if not name:
                print("  FAIL: enclosure has no URL")
                ok = False
                continue
            if not os.path.exists(payload):
                print(f"  FAIL: missing {payload}")
                ok = False
                continue

            actual_length = os.path.getsize(payload)
            print(f"  {name}: length appcast={expected_length} actual={actual_length}")
            if expected_length is None or int(expected_length) != actual_length:
                print("  FAIL: length mismatch")
                ok = False

            if not signature_b64:
                print("  FAIL: missing sparkle:edSignature")
                ok = False
                continue

            try:
                signature = base64.b64decode(signature_b64, validate=True)
            except ValueError as error:
                print(f"  FAIL: invalid base64 signature: {error}")
                ok = False
                continue

            print(f"  signature bytes={len(signature)}")
            if len(signature) != 64:
                print("  FAIL: Ed25519 signature must be 64 bytes")
                ok = False
                continue

            verified, output = run_openssl_verify(public_key, payload, signature)
            print(f"  verify: {output or 'ok'}")
            if not verified:
                ok = False
            enclosures.append((name, payload, signature))

    return ok, enclosures


def tamper_check(enclosures: list[tuple[str, str, bytes]], public_key: str, output_dir: str) -> bool:
    if not enclosures:
        print("FAIL: no enclosure available for tamper check")
        return False

    # `generate_appcast` writes newest items first. Use the newest full DMG.
    dmg_enclosures = [entry for entry in enclosures if entry[0].endswith(".dmg")]
    if not dmg_enclosures:
        print("FAIL: no DMG enclosure available for tamper check")
        return False
    name, payload, signature = dmg_enclosures[0]
    os.makedirs(output_dir, exist_ok=True)
    tampered = os.path.join(output_dir, name.replace(".dmg", "-tampered.dmg"))
    shutil.copyfile(payload, tampered)

    with open(tampered, "r+b") as handle:
        handle.seek(1024)
        value = handle.read(1)
        handle.seek(1024)
        handle.write(bytes([value[0] ^ 0x01]))

    print("\nTamper check:")
    print(f"  original sha256: {sha256(payload)}")
    print(f"  tampered sha256: {sha256(tampered)}")
    verified, output = run_openssl_verify(public_key, tampered, signature)
    print(f"  verify: {output or 'ok'}")
    if verified:
        print("  FAIL: tampered payload was accepted")
        return False
    print("  PASS: tampered payload rejected")
    return True


def public_key_pem_from_account(account: str, sparkle_tools_path: str) -> str:
    """Derive a PEM public key from the login keychain via `generate_keys -p --account`."""
    generate_keys = os.path.join(sparkle_tools_path, "generate_keys")
    if not os.path.exists(generate_keys):
        raise RuntimeError(
            f"generate_keys not found at {generate_keys}; pass --sparkle-tools-path or use --public-key"
        )
    result = subprocess.run(
        [generate_keys, "-p", "--account", account],
        capture_output=True, text=True,
    )
    out = result.stdout.strip()
    if result.returncode != 0 or not out or "ERROR" in out or "No existing signing key" in out:
        raise RuntimeError(f"no signing key found for account {account!r} in the login keychain")
    raw = base64.b64decode(out, validate=True)
    der = bytes.fromhex("302a300506032b6570032100") + raw
    pem = (
        "-----BEGIN PUBLIC KEY-----\n"
        + base64.b64encode(der).decode()
        + "\n-----END PUBLIC KEY-----\n"
    )
    handle = tempfile.NamedTemporaryFile("w", delete=False, prefix="sparkle-public-", suffix=".pem")
    handle.write(pem)
    handle.flush()
    return handle.name


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--feed", required=True, help="Directory containing appcast.xml and payloads")
    parser.add_argument("--public-key", help="Ed25519 public key in PEM format (for raw verification)")
    parser.add_argument(
        "--account",
        help="Named keychain account to verify against (e.g. rasc-sparkle). Takes precedence over --public-key",
    )
    parser.add_argument(
        "--sparkle-tools-path",
        help="Directory containing generate_keys (defaults to <repo>/build/sparkle-tools/bin)",
    )
    parser.add_argument("--appcast", help="Defaults to <feed>/appcast.xml")
    parser.add_argument("--tamper", action="store_true", help="Verify that a one-byte change is rejected")
    parser.add_argument("--tamper-output", help="Defaults to <feed>/../evidence")
    args = parser.parse_args()

    feed_dir = os.path.abspath(args.feed)
    appcast_path = os.path.abspath(args.appcast or os.path.join(feed_dir, "appcast.xml"))
    output_dir = os.path.abspath(args.tamper_output or os.path.join(feed_dir, "..", "evidence"))

    tools_path = args.sparkle_tools_path or os.path.abspath(
        os.path.join(os.path.dirname(__file__), "..", "..", "build", "sparkle-tools", "bin")
    )

    public_key = None
    temp_pem = None
    if args.account is not None:
        try:
            public_key = public_key_pem_from_account(args.account, tools_path)
            temp_pem = public_key
        except RuntimeError as error:
            print(f"FAIL: {error}")
            return 1
    elif args.public_key:
        public_key = os.path.abspath(args.public_key)
        if not os.path.exists(public_key):
            print(f"FAIL: missing {public_key}")
            return 1
    else:
        parser.error("either --account or --public-key is required")

    if not os.path.exists(appcast_path):
        print(f"FAIL: missing {appcast_path}")
        return 1

    ok, enclosures = verify_feed(feed_dir, appcast_path, public_key)
    if args.tamper:
        ok = tamper_check(enclosures, public_key, output_dir) and ok
    if temp_pem is not None:
        try:
            os.unlink(temp_pem)
        except OSError:
            pass
    print(f"\nRESULT: {'PASS' if ok else 'FAIL'}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
