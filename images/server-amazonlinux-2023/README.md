# server-amazonlinux-2023

Amazon Linux 2023 as a server that is up and running. The SpliceFS rpm packages are tested on
it: install, upgrade, remove, and the service running.

The vendor image `amazonlinux:2023` is cut down far below a server: no service manager, a
minimal curl and coreutils, no sshd. This image brings it up to Amazon's own minimal install,
the group `base-minimal` ("the basic minimal install of Amazon Linux"), without weak
dependencies, because the group lists everything it holds. With them the image would add
`systemd-networkd`, whose wait-online unit makes a container take two minutes to boot:

- That is `systemd` (started as process 1, the way a server that has booted runs it),
  `openssh-server`, `chrony`, `sudo`, `dnf`, `systemd-resolved` and the rest of the group.
  `coreutils` replaces `coreutils-single` of the vendor image, because the group asks for the
  full one. The group `core` is not used: it holds five packages that the vendor image
  already has.
- `ca-certificates`, which every server has.

`fuse3` is not in the image. The SpliceFS packages pull it in themselves when they are
installed, and a test of the install has to see that happen.

Three things of the vendor image are changed, because a container image differs from a server
in them: `/etc/machine-id` is empty, so that every container made from the image chooses its
own machine id when it boots (installing systemd fills it in), `update-motd.service` and
`update-motd.timer` are masked, because the service takes about 30 seconds at every boot and
keeps systemd in the state starting, and a container has no login that would show the message,
and the console and terminal login units `console-getty.service`, `getty@.service`,
`serial-getty@.service` and `getty.target` are masked, because a container has no console
or terminal for a login prompt to run on, and a getty started on a missing one dumps core
after the container restarts.
Nothing else is removed or replaced except where the set needs it, see below.

Boot it and ask the service manager (the flags are explained under "Server images" in the
top-level README):

    docker run -d --name server --privileged --cgroupns=host --tmpfs /run --tmpfs /run/lock --tmpfs /tmp ghcr.io/splicefs/server-amazonlinux-2023:v1
    docker exec server systemctl is-system-running

`test.sh` checks the image: the service manager, marker packages of the set, the
certificates, the empty machine id, and that `fuse3` is absent. `server-setup-rpm.sh` is the
one step that makes the image from the vendor image, and it is the same file in the folder
of every rpm server image.
