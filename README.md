# Knowl's Mattermost: source of our changes

Knowable Labs distributes a modified build of [Mattermost](https://github.com/mattermost/mattermost)
(open-source edition) as the container image `ghcr.io/knowablelabs/knowl-mattermost`. Mattermost's server is
licensed under the GNU AGPL v3 (admin tools and configuration under Apache 2.0); this
repository is the corresponding source of our changes.

- Upstream: https://github.com/mattermost/mattermost at tag `v11.11.2` (`VERSION`).
- `patches/`: our changes, applied in order with `git am`.
- `transform.mjs`: mechanical changes ("Channel" reads "Topic", fonts).
- `build.sh`: the exact build (webapp, Linux server, image); `Dockerfile`: the image.
- `fonts/`: Public Sans and JetBrains Mono, with their licenses.
- `server/enterprise` (Mattermost Source Available License) is deleted before building
  and is not part of the image.

Build it yourself with `./build.sh` (git, Go, Node and Docker).
