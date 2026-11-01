# Knowl's Mattermost: the server and webapp build.sh compiled, on a small Ubuntu base.
# docs/guides/agent-workspace-design.md, The pieces.
FROM ubuntu:noble
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y ca-certificates tzdata media-types mailcap \
  && rm -rf /var/lib/apt/lists/* \
  && groupadd --gid 2000 mattermost \
  && useradd --uid 2000 --gid 2000 --comment "" --home-dir /mattermost mattermost
COPY --chown=2000:2000 . /mattermost
RUN rm /mattermost/Dockerfile
ENV PATH="/mattermost/bin:${PATH}" MM_SERVICESETTINGS_ENABLELOCALMODE="true" MM_INSTALL_TYPE="docker"
USER mattermost
WORKDIR /mattermost
EXPOSE 8065
HEALTHCHECK --interval=30s --timeout=10s CMD ["/mattermost/bin/mmctl", "system", "status", "--local"]
CMD ["/mattermost/bin/mattermost"]
