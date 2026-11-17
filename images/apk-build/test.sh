#!/bin/sh
# Checks that every tool of the image is installed and starts, that the image does not run
# as root unless the run asks for it, that the folders the tools write to are writable, and
# that a package can be built and signed with a key made here, and put into a signed
# repository index that apk accepts. The build workflow runs this inside the image, so that
# a broken image is not published.
#
# The same file proves the other ways of running the image. Start the container with
# --user 501:20 (a user that is not in the image) and every check still passes. Start it
# with --user 0 -e EXPECT_ROOT=1 to prove the root mode: the run must then really be root.
set -eu

# Descriptor 3 is the real error output. check hides descriptors 1 and 2 of what it runs,
# and a failed step must still show why it failed.
exec 3>&2

# Runs a tool with output hidden, and stops the whole test at the first one that is
# missing or does not start.
check() {
    name="$1"
    shift
    if ! "$@" >/dev/null 2>&1; then
        echo "FAIL: ${name}" >&2
        exit 1
    fi
    echo "ok: ${name}"
}

# A file really is created and removed, because the mode bits of a folder do not say
# whether this user may write there.
writable() {
    probe="$(mktemp "$1/probe.XXXXXX")" || return 1
    rm -f "${probe}"
}

# Runs a step of the end-to-end check with its output kept in a file, and shows that output
# on descriptor 3 when the step fails. A function that runs as the condition of an if has
# set -e switched off inside it, so each function below stops itself with "|| return 1"
# after every command but the last, which gives its status.
step() {
    if "$@" >"${work}/step.out" 2>&1; then
        return 0
    fi
    cat "${work}/step.out" >&3
    return 1
}

# A recipe like the one of the SpliceFS repositories: it only wraps a file, and the CPU type
# comes from the build. The folder above the one with the recipe names the repository, so
# the package lands in repo/pkgs/<CPU type>.
write_recipe() {
    mkdir -p "${work}/pkgs/hello"
    cat >"${work}/pkgs/hello/APKBUILD" <<'EOF'
pkgname=hello
pkgver=1
pkgrel=0
pkgdesc="A package for the test of the image"
url="https://example.invalid/"
arch="all"
license="MIT"
options="!check !strip"

package() {
	install -D -m 644 /dev/null "$pkgdir/usr/share/hello/hello.txt"
}
EOF
}

# A key in a folder of the test, as the repository scripts keep theirs. PACKAGER gives the
# key a name that a person could read, because abuild-keygen takes it from the git or user
# name, which a user that is not in /etc/passwd does not have.
make_key() {
    ABUILD_USERDIR="${work}/abuild" PACKAGER="Image test <test@example.invalid>" \
        abuild-keygen -n -q -b 2048
}

# The first and only key that abuild-keygen wrote; the glob stands for its generated name.
private_key() {
    set -- "${work}"/abuild/*.rsa
    echo "$1"
}

# Built the way the package script builds: the key is named in the environment, the CPU type
# is given and nothing is compiled, and the user may be root, which -F allows. The package
# file must exist, because apk takes a missing file for one that has nothing wrong with it.
build_package() {
    (
        cd "${work}/pkgs/hello" || exit 1
        CARCH="${arch}" PACKAGER_PRIVKEY="$1" REPODEST="${work}/repo" abuild -F -q rootpkg
    ) || return 1
    test -f "${package}"
}

# apk finds the key of a package by the name that the package holds, so the keys folder
# must have the public key under its own name. An empty folder must refuse the package,
# or the check is blind.
signature_is_checked() {
    mkdir "${work}/keys" "${work}/nokeys" || return 1
    cp "$1.pub" "${work}/keys/" || return 1
    apk --keys-dir "${work}/keys" verify "${package}" || return 1
    ! apk --keys-dir "${work}/nokeys" verify "${package}"
}

# The index step of the repository script: the key goes into the folder that apk trusts
# on this machine, and the index is signed with the key under the name of the public key.
# apk looks for the index in a folder named after the CPU type of the machine that installs.
sign_index() {
    cp "$1.pub" /etc/apk/keys/ || return 1
    mkdir -p "${work}/index/${arch}" || return 1
    cp "${package}" "${work}/index/${arch}/" || return 1
    (
        cd "${work}/index/${arch}" || exit 1
        apk index -q --rewrite-arch "${arch}" -o APKINDEX.tar.gz ./*.apk || exit 1
        abuild-sign -q -k "$1" -p "$1.pub" APKINDEX.tar.gz
    )
}

# apk installs from the repository into a root of the test, and only an index with a good
# signature lets it do so.
index_is_installable() {
    apk --root "${work}/root" --keys-dir "${work}/keys" --no-cache \
        --repositories-file /dev/null -X "${work}/index" add --initdb hello || return 1
    test -f "${work}/root/usr/share/hello/hello.txt"
}

# The key in /etc/apk/keys is the only thing the test leaves outside its own folder.
cleanup() {
    rm -f "/etc/apk/keys/${key##*/}.pub" 2>/dev/null || true
    rm -rf "${work}"
}

check "abuild" abuild -h
check "abuild-sign" abuild-sign -h
check "abuild-keygen" abuild-keygen -h
check "apk" apk --version

# Without a request for root, the default user is under test, and that user is not root.
uid="$(id -u)"
if [ "${EXPECT_ROOT:-}" = 1 ]; then
    check "the run is root, as asked" test "${uid}" -eq 0
else
    check "the default user is not root" test "${uid}" -ne 0
fi

check "HOME is writable" writable "${HOME}"
check "the keys folder of apk is writable" writable /etc/apk/keys

arch="$(apk --print-arch)"
key=""
work="$(mktemp -d)"
package="${work}/repo/pkgs/${arch}/hello-1-r0.apk"
trap cleanup EXIT
write_recipe
check "abuild-keygen makes a key" step make_key
key="$(private_key)"
check "abuild builds and signs a package" step build_package "${key}"
check "apk checks the signature of the package" step signature_is_checked "${key}"
check "abuild-sign signs the index" step sign_index "${key}"
check "apk installs from the signed index" step index_is_installable
