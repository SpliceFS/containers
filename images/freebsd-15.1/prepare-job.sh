#!/bin/sh
# Runs inside FreeBSD as root, once, at the end of the first boot of the official disk (the
# first-boot script of the job folder starts it, and powers the machine off afterwards). It
# leaves the disk in the state every later boot starts from: the package tool is set up, a
# hook runs the job on every boot, and nothing of the first boot repeats.
set -eu

# On a release whose base system is not managed by pkg, the base system ships only a stub
# that fetches the real pkg on first use, and pkg -N fails until pkg bootstrap ran. This is
# the same check the job scripts make, so that the disk and the jobs agree.
pkg -N >/dev/null 2>&1 || env ASSUME_ALWAYS_YES=yes pkg bootstrap -y
pkg update

# The first boot can leave downloads in the package cache (on a release whose base system
# is managed by pkg, these are base system updates). They are not needed again, and they
# would make the disk several hundred megabytes larger.
pkg clean -a -y

# FreeBSD runs /etc/rc.local at the end of every boot. The first-boot script of the job
# folder is only started by nuageinit at the first boot of a disk, so this hook starts it
# instead. The file is copied off the job disk first, because user-data mounts that disk
# itself. The quotes on EOF keep the shell from expanding anything while the file is written.
cat > /etc/rc.local <<'EOF'
#!/bin/sh
# Runs the job of the disk labelled cidata, if there is one, and does nothing otherwise.
if [ -e /dev/msdosfs/cidata ]; then
    job_mount="$(mktemp -d)"
    mount -t msdosfs -o ro /dev/msdosfs/cidata "$job_mount"
    cp "$job_mount/user-data" /tmp/user-data
    umount "$job_mount"
    rmdir "$job_mount"
    sh /tmp/user-data
fi
EOF
chmod 755 /etc/rc.local

# The first-boot scripts of FreeBSD run only while /firstboot exists. FreeBSD removes the
# file at the very end of the first boot, and this machine powers off before that point.
rm -f /firstboot

echo "--- state left for the later boots"
freebsd-version -kru
ls -la /firstboot /etc/rc.local 2>&1 || true
ls -la /var/cache/nuageinit 2>&1 || true
grep -H 'KEYWORD' /etc/rc.d/nuageinit /etc/rc.d/growfs 2>&1 || true
grep -n 'rc.local' /etc/rc /etc/rc.d/* 2>&1 || true
pkg -N
# Only a report. What it lists depends on the release, and a failure of the report must not
# fail the job.
pkg upgrade -n || true
df -h /
