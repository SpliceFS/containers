# server-opensuse-leap-16.0

openSUSE Leap 16.0 as a server that is up and running. The SpliceFS rpm packages are tested on
it: install, upgrade, remove, and the service running.

The image is the vendor image `opensuse/leap:16.0` plus two things, and nothing else:

- `systemd`, the service manager the vendor ships, installed when the vendor image lacks
  it. The image starts it as process 1, the way a server that has booted runs it.
- `ca-certificates`, which every server has, installed when the vendor image lacks it.

`fuse3` is not in the image. The SpliceFS packages pull it in themselves when they are
installed, and a test of the install has to see that happen.

Boot it and ask the service manager (the flags are explained under "Server images" in the
top-level README):

    docker run -d --name server --privileged --cgroupns=host --tmpfs /run --tmpfs /run/lock --tmpfs /tmp ghcr.io/splicefs/server-opensuse-leap-16.0:v1
    docker exec server systemctl is-system-running

`test.sh` checks the files of the image: the service manager, the certificates, and that
`fuse3` is absent. `server-setup-rpm.sh` is the one step that makes the image from the
vendor image, and it is the same file in the folder of every rpm server image.
