#!/bin/sh
# Turns the container image of a Rocky Linux, Amazon Linux or openSUSE release into a server
# that is up and running: the vendor's own service manager, which most of the container
# images leave out, and ca-certificates, which every server has. Only what is missing is
# installed, and nothing else, no weak dependencies, because systemd runs without them. The
# same file is in the folder of every rpm server image, and scripts/same-files.sh checks
# that.
set -eu

# What the image already has is left as the vendor made it, not upgraded.
set --
for package in systemd ca-certificates; do
    if ! rpm -q "${package}" >/dev/null 2>&1; then
        set -- "$@" "${package}"
    fi
done
if [ "$#" -eq 0 ]; then
    exit 0
fi

# The package manager is told apart on the system itself, as the vendor's images differ:
# Rocky Linux and Amazon Linux use dnf, openSUSE uses zypper.
if command -v dnf >/dev/null 2>&1; then
    dnf install -y --setopt=install_weak_deps=False "$@"
    # The package caches stay out of the layer.
    dnf clean all
else
    zypper --non-interactive --gpg-auto-import-keys install --no-recommends "$@"
    zypper clean --all
fi
