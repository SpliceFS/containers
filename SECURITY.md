# Security policy

This repository holds the definitions of the container images that the SpliceFS tests run
in, and the workflow that builds and publishes them to `ghcr.io/splicefs`. The images are
test tools. They are not meant to run SpliceFS for anyone. Problems here are still treated as
urgent, because a published image runs inside the test jobs of the other repositories.

## Reporting a vulnerability

Do not open a public issue for a security problem.

Report it privately through GitHub: open the repository's **Security** tab and choose
**Report a vulnerability**. Include what you ran, on which system, and what happened.

You can expect an acknowledgement within five working days. Once a fix is published, the
advisory is published and the reporter is credited unless they ask not to be.

## Scope

In scope: anything that puts code, a credential or a configuration into an image other than
what its Dockerfile names, lets a workflow publish an image that was not built from this
repository, or exposes the token a workflow uses to publish.

Problems in the programs themselves are reported in the
[server](https://github.com/SpliceFS/server) and
[client](https://github.com/SpliceFS/client) repositories. Problems in a base image or a
package that an image installs are reported to the project that ships it.
