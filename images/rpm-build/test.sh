#!/bin/sh
# Checks that every tool of the image is installed and starts, that the image does not run
# as root unless the run asks for it, that the folders the tools write to are writable, and
# that a package can be built, signed with a key made here, checked, and put into a
# repository. The build workflow runs this inside the image, so that a broken image is not
# published.
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

# The folders that the base image makes writable by every user, as every Linux system
# does. The image must not open any other folder to every user. find fails on the folders
# that this user may not read, such as /root, and no other user but root can reach those
# either, so only what it prints counts.
folders_open_to_all() {
    find / -xdev \( -path /tmp -o -path /var/tmp -o -path /run/lock \) -prune \
        -o -type d -perm -0002 -print 2>/dev/null || true
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

# A spec like the ones of the SpliceFS repositories: no %defattr, so the owner of the file in
# the package comes from the user that builds it.
write_spec() {
    cat >"${work}/hello.spec" <<'EOF'
Name:           hello
Version:        1
Release:        1
Summary:        A package for the test of the image
License:        MIT
BuildArch:      noarch

%description
One file and nothing else.

%install
install -D -m 644 /dev/null %{buildroot}/usr/share/hello/hello.txt

%files
/usr/share/hello/hello.txt
EOF
}

build_package() {
    rpmbuild -bb --quiet --define "_topdir ${work}/top" "${work}/hello.spec"
}

# A key without a passphrase, in a folder of its own, so that nothing of the test reaches
# the key ring of the user.
make_key() {
    mkdir "${work}/gnupg" || return 1
    chmod 700 "${work}/gnupg" || return 1
    gpg --batch --pinentry-mode loopback --passphrase "" \
        --quick-generate-key "Image test <test@example.invalid>" rsa2048 sign never
}

# The fingerprint of the one key in the key ring.
fingerprint() {
    gpg --list-secret-keys --with-colons 2>/dev/null | awk -F: '$1=="fpr"{print $10; exit}'
}

# Signed the way the repository script signs: the key is named on the command line and the
# input is closed, so that a missing passphrase fails and does not wait for a terminal.
sign_package() {
    rpmsign --addsign --define "_gpg_name $1" --define "_gpg_path ${GNUPGHOME}" \
        "${work}/top/RPMS/noarch/hello-1-1.noarch.rpm" </dev/null
}

# rpm checks a signature against the keys in its database, so the public key goes into a
# database of the test, not into the one of the image. A package without a signature passes
# the digest check, so the answer must say that the signature was checked too.
signature_is_good() {
    gpg --armor --export "$1" >"${work}/key.asc" || return 1
    rpmkeys --dbpath "${work}/rpmdb" --import "${work}/key.asc" || return 1
    rpmkeys --dbpath "${work}/rpmdb" --checksig \
        "${work}/top/RPMS/noarch/hello-1-1.noarch.rpm" >"${work}/checksig.out" || return 1
    grep -q 'signatures OK' "${work}/checksig.out"
}

# The index of a repository, signed in a file next to it, as the repository script does.
repository_is_signed() {
    mkdir -p "${work}/repo" || return 1
    cp "${work}/top/RPMS/noarch/hello-1-1.noarch.rpm" "${work}/repo/" || return 1
    createrepo_c --quiet --update "${work}/repo" || return 1
    gpg --batch --yes --pinentry-mode loopback --passphrase "" --default-key "$1" \
        --armor --detach-sign -o "${work}/repo/repodata/repomd.xml.asc" \
        "${work}/repo/repodata/repomd.xml" || return 1
    gpg --verify "${work}/repo/repodata/repomd.xml.asc" "${work}/repo/repodata/repomd.xml"
}

check "rpmbuild" rpmbuild --version
check "rpm" rpm --version
check "rpmsign" rpmsign --version
check "createrepo_c" createrepo_c --version
check "gpg" gpg --version

# Without a request for root, the default user is under test, and that user is not root.
uid="$(id -u)"
if [ "${EXPECT_ROOT:-}" = 1 ]; then
    check "the run is root, as asked" test "${uid}" -eq 0
else
    check "the default user is not root" test "${uid}" -ne 0
fi

check "HOME is writable" writable "${HOME}"
open="$(folders_open_to_all)"
if [ -n "${open}" ]; then
    echo "writable by every user: ${open}" >&2
fi
check "no folder but the temporary ones is writable by every user" test -z "${open}"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
export GNUPGHOME="${work}/gnupg"
write_spec
check "rpmbuild builds a package" step build_package
check "gpg makes a key" step make_key
fpr="$(fingerprint)"
check "gpg lists the key" test -n "${fpr}"
check "rpmsign signs the package" step sign_package "${fpr}"
check "rpm accepts the signature" step signature_is_good "${fpr}"
check "createrepo_c indexes it and gpg signs the index" step repository_is_signed "${fpr}"
