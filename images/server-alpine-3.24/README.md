# server-alpine-3.24

Alpine 3.24 as a server that is up and running. The SpliceFS apk packages are tested on it:
install, upgrade, remove, and the service running.

The image is the vendor image `alpine:3.24` plus two things, and nothing else:

- `openrc`, the service manager Alpine ships, which the vendor image leaves out. The image
  starts it from `/sbin/init`, process 1, the way a server that has booted runs it.
  OpenRC is told that it runs in a container (`rc_sys="docker"` in `/etc/rc.conf`),
  because a container cannot reach the hardware that its boot services expect.
- `ca-certificates`, which every server has.

`fuse3` is not in the image. The SpliceFS packages pull it in themselves when they are
installed, and a test of the install has to see that happen.

Boot it and ask the service manager. It needs no `docker run` flags (the flags of the
systemd images, listed under "Server images" in the top-level README, do no harm):

    docker run -d --name server ghcr.io/splicefs/server-alpine-3.24:v1
    docker exec server rc-status

`test.sh` checks the files of the image: the service manager, the certificates, and that
`fuse3` is absent. `server-setup-apk.sh` is the one step that makes the image from the
vendor image, and it is the same file in the folder of every apk server image.
