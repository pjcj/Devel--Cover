# hadolint ignore=DL3007
FROM pjcj/devel-cover-base:latest
ARG BRANCH=main
ARG REPO=https://github.com/pjcj/Devel--Cover
WORKDIR /dc
RUN git clone "$REPO" /dc --depth 1 -b "$BRANCH"
