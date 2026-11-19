# server-opensuse-leap-16.0

openSUSE Leap 16.0 as a server that is up and running. The SpliceFS rpm packages are tested
on it: install, upgrade, remove, and the service running.

The vendor image `opensuse/leap:16.0` is cut down far below a server: no service manager, no
network tools. This image brings it up to the pattern `base` ("Base System": "a basic
multiuser booting system"), with the pattern `minimal_base` that it requires and the
recommended packages, as the installer installs them. The pattern `minimal_base` alone is
already satisfied by the vendor image and has no service manager in it, so it is not enough.

- That is `systemd` (started as process 1, the way a server that has booted runs it),
  `NetworkManager`, `iproute2`, `wtmpdb`, `lastlog2`, `zypper` and the rest of the pattern.
- `ca-certificates`, which every server has.

`fuse3` is not in the image. The SpliceFS packages pull it in themselves when they are
installed, and a test of the install has to see that happen. The pattern `enhanced_base`
would bring `fuse`, which is why it is not used.

Two things of the vendor image are changed, because a container image differs from a server
in them: `/etc/machine-id` is empty, so that every container made from the image chooses its
own machine id when it boots (installing systemd fills it in), and the console and terminal login units `console-getty.service`, `getty@.service`,
`serial-getty@.service` and `getty.target` are masked, because a container has no console
or terminal for a login prompt to run on, and a getty started on a missing one dumps core
after the container restarts.
Nothing else is removed or replaced except where the set needs it, see below.

Boot it and ask the service manager (the flags are explained under "Server images" in the
top-level README):

    docker run -d --name server --privileged --cgroupns=host --tmpfs /run --tmpfs /run/lock --tmpfs /tmp ghcr.io/splicefs/server-opensuse-leap-16.0:v1
    docker exec server systemctl is-system-running

`test.sh` checks the image: the service manager, marker packages of the set, the
certificates, the empty machine id, and that `fuse3` is absent. `server-setup-rpm.sh` is the
one step that makes the image from the vendor image, and it is the same file in the folder
of every rpm server image.
