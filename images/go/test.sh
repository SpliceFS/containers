#!/bin/sh
# Checks that every tool of the image is installed and starts, that the image does not run
# as root unless the run asks for it, that the folders that Go writes to are writable, that
# no other folder is writable by every user, and that the race detector finds a race. The build workflow runs this inside the image, so
# that a broken image is not published.
#
# The same file proves the other ways of running the image. Start the container with
# --user 501:20 (a user that is not in the image) and every check still passes. Start it
# with --user 0 -e EXPECT_ROOT=1 to prove the root mode: the run must then really be root.
# Mount a host folder at /tmp/go/pkg/mod, /tmp/go-cache or both to prove that a caller's
# cache folder works too.
set -eu

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

# Creates the folder the way Go does when it first writes to it, and then proves that this
# user can write there. A host folder that the caller mounts over it is there already.
made_writable() {
    mkdir -p "$1" || return 1
    writable "$1"
}

# The folders that the Ubuntu base image makes writable by every user: the ones that every
# Linux system has, and /var/lib/pebble/default. The image must not open any other folder
# to every user. find fails on the folders that this user may not read, such as /root, and
# no other user but root can reach those either, so only what it prints counts.
folders_open_to_all() {
    find / -xdev \( -path /tmp -o -path /var/tmp -o -path /run/lock \
        -o -path /var/lib/pebble/default \) -prune \
        -o -type d -perm -0002 -print 2>/dev/null || true
}

# Writes a package with a locked counter and an unlocked one into $1. The two tests give
# the race detector one case that must pass and one that must be reported, whichever order
# the goroutines run in: the detector follows the order of the synchronisation, not time.
write_race_package() {
    (
        cd "$1"
        go mod init racecheck
        cat >counter_test.go <<'EOF'
package racecheck

import (
	"sync"
	"testing"
)

func count(locked bool) int {
	var (
		wg      sync.WaitGroup
		mu      sync.Mutex
		counter int
	)
	for range 2 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if locked {
				mu.Lock()
				defer mu.Unlock()
			}
			counter++
		}()
	}
	wg.Wait()
	return counter
}

func TestLocked(t *testing.T) {
	if got := count(true); got != 2 {
		t.Fatalf("count = %d, want 2", got)
	}
}

func TestUnlocked(t *testing.T) {
	count(false)
}
EOF
    )
}

# The locked counter must pass under the race detector. The output is kept in a file,
# because check hides it, and is shown when the test fails.
locked_passes() {
    if go test -race -run '^TestLocked$' ./... >"${work}/race.out" 2>&1; then
        return 0
    fi
    cat "${work}/race.out" >&2
    return 1
}

# The unlocked counter must fail, and only a failure that names the race counts. A pass
# means that the detector is blind.
unlocked_is_reported() {
    if go test -race -run '^TestUnlocked$' ./... >"${work}/race.out" 2>&1; then
        return 1
    fi
    grep -q 'WARNING: DATA RACE' "${work}/race.out"
}

check "go" go version
cgo_enabled="$(go env CGO_ENABLED)"
check "go env CGO_ENABLED is 1" test "${cgo_enabled}" = 1
check "gcc" gcc --version
check "golangci-lint" golangci-lint --version
check "fusermount3" fusermount3 -V
check "curl" curl --version
check "xz" xz --version
check "zstd" zstd --version
check "apt-ftparchive" apt-ftparchive --help
check "dpkg-deb" dpkg-deb --version
check "tar" tar --version
check "gzip" gzip --version
check "gpg" gpg --version
check "openssl" openssl version
check "git" git --version
check "make" make --version
check "shellcheck" shellcheck --version

# Without a request for root, the default user is under test, and that user is not root.
uid="$(id -u)"
if [ "${EXPECT_ROOT:-}" = 1 ]; then
    check "the run is root, as asked" test "${uid}" -eq 0
else
    check "the default user is not root" test "${uid}" -ne 0
fi

check "HOME is writable" writable "${HOME}"
gocache="$(go env GOCACHE)"
gomodcache="$(go env GOMODCACHE)"
check "GOCACHE is writable" made_writable "${gocache}"
check "GOMODCACHE is writable" made_writable "${gomodcache}"
open="$(folders_open_to_all)"
if [ -n "${open}" ]; then
    echo "writable by every user: ${open}" >&2
fi
check "no folder but the temporary ones is writable by every user" test -z "${open}"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
write_race_package "${work}"
cd "${work}"
check "go test -race passes a locked counter" locked_passes
check "go test -race reports an unlocked counter" unlocked_is_reported
