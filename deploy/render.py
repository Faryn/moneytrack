#!/usr/bin/env python3
"""Render private host configuration outside tracked source."""
import argparse
import ipaddress
import json
import pathlib
import re

HERE = pathlib.Path(__file__).resolve().parent


def render(config, output):
    required = {"PUBLIC_HOST", "APP_SSH", "PROXY_SSH", "APP_IP", "PROXY_IP", "PROXY_IPV6", "PROXY_PUBLIC_IPV4"}
    if set(config) != required or not all(isinstance(v, str) and v for v in config.values()):
        raise ValueError("Supply all private host settings shown in local.example.json")
    if not re.fullmatch(r"[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?", config["PUBLIC_HOST"]):
        raise ValueError("PUBLIC_HOST must be a DNS hostname")
    for key in ["APP_SSH", "PROXY_SSH"]:
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", config[key]):
            raise ValueError("SSH settings must be plain SSH aliases or hostnames")
    for key in ["APP_IP", "PROXY_IP", "PROXY_PUBLIC_IPV4"]:
        ipaddress.IPv4Address(config[key])
    ipaddress.IPv6Address(config["PROXY_IPV6"])
    output = pathlib.Path(output).resolve()
    repository = HERE.parent
    if output.is_relative_to(repository) and not output.is_relative_to(HERE / "local"):
        raise ValueError("Use ignored deploy/local or a directory outside the repository")
    output.mkdir(parents=True, exist_ok=True, mode=0o700)
    for template in sorted((HERE / "templates").glob("*.in")):
        text = template.read_text()
        for key, value in config.items():
            text = text.replace("@@" + key + "@@", value)
        if re.search(r"@@[A-Z_]+@@", text):
            raise ValueError("Unresolved deployment setting")
        destination = output / template.name.removesuffix(".in")
        destination.write_text(text)
        destination.chmod(0o600)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("config", nargs="?", type=pathlib.Path, default=HERE / "local.json")
    parser.add_argument("output", nargs="?", type=pathlib.Path, default=HERE / "local")
    args = parser.parse_args()
    render(json.loads(args.config.read_text()), args.output)
    print("Private deployment files rendered. No host values printed.")
