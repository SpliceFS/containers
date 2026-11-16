# apk-build

Alpine Linux 3.22 (`alpine:3.22`) plus `abuild`, the tool that builds and signs apk
packages and signs the index of an apk repository. The package also brings `abuild-sign`,
`abuild-keygen` and the `apk` tool.

Used by the package and repository steps for apk packages of the SpliceFS repositories.
It is not one of the systems that the packages are tested on: those tests start their own
systems.
Pull it with `docker pull ghcr.io/splicefs/apk-build:<version>`, where the version is the
one line of the file `version` in this folder. `test.sh` checks the tools inside the image.
