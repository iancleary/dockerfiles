# Claude Code image

Claude Code CLI layer on the OpenShell agent-cli image. The upstream project
is Claude Code and the binary is `claude` at `/usr/local/bin/claude`. The
published name is `ghcr.io/iancleary/openshell-claude`. A local
`just openshell::claude` tags `openshell-claude:phase1`.

The image has no provider credentials and does not log in. The consumer
mounts or uploads provider config when the sandbox starts.

```sh
just openshell::claude
```

A language-stack base uses the same `BASE_IMAGE` build-arg as the other
harness Dockerfiles. See the [family README](../README.md).
