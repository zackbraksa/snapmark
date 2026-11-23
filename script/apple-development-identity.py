#!/usr/bin/env python3
"""Select an available Apple Development identity by its certificate Team ID."""

import argparse
import re
import subprocess
import sys


def select_identity(team, identities, certificates):
    available = set(re.findall(r'\b([A-Fa-f0-9]{40})\s+"(?:Apple Development|Mac Developer|iPhone Developer):', identities))
    for certificate in certificates:
        result = subprocess.run(
            ["openssl", "x509", "-noout", "-subject", "-nameopt", "RFC2253", "-fingerprint", "-sha1"],
            input=certificate, text=True, capture_output=True, check=True,
        ).stdout
        subject = next((line for line in result.splitlines() if line.startswith("subject=")), "")
        if not re.search(r"(?:^|,)OU=" + re.escape(team) + r"(?:,|$)", subject.removeprefix("subject=")):
            continue
        fingerprint = next((line.split("=", 1)[1].replace(":", "").upper()
                            for line in result.splitlines() if "Fingerprint=" in line), "")
        if fingerprint in {value.upper() for value in available}:
            return fingerprint
    raise RuntimeError(f"No usable Apple Development signing identity for team {team}. Create one in Xcode > Settings > Apple Accounts > Manage Certificates.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--team", required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Z0-9]{10}", args.team):
        parser.error("--team must be a 10-character Apple Team ID")
    identities = subprocess.run(["security", "find-identity", "-v", "-p", "codesigning"],
                                text=True, capture_output=True, check=True).stdout
    pem = subprocess.run(["security", "find-certificate", "-a", "-p"],
                         text=True, capture_output=True, check=True).stdout
    certificates = re.findall(r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----", pem, re.S)
    print(select_identity(args.team, identities, certificates))


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
