# hadolint ignore=DL3007
FROM pjcj/perl-5.42.0:latest

WORKDIR /usr/local/src

# hadolint ignore=DL3008
RUN apt-get update                                                          && \
    apt-get -y --no-install-recommends install                                 \
      ca-certificates curl git libssl-dev libz-dev pigz                     && \
    update-ca-certificates                                                  && \
    install -m 0755 -d /etc/apt/keyrings                                    && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg                    \
      -o /etc/apt/keyrings/docker.asc                                       && \
    chmod a+r /etc/apt/keyrings/docker.asc                                  && \
    echo "deb [arch=$(dpkg --print-architecture)                               \
      signed-by=/etc/apt/keyrings/docker.asc]                                  \
      https://download.docker.com/linux/ubuntu                                 \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable"                 \
      > /etc/apt/sources.list.d/docker.list                                 && \
    apt-get update                                                          && \
    apt-get -y --no-install-recommends install docker-ce-cli                && \
    rm -rf /var/lib/apt/lists/*

RUN cpan -Ti                                                                   \
      CPAN::DistnameInfo                                                       \
      CPAN::Releases::Latest                                                   \
      Digest::MD5                                                              \
      JSON::MaybeXS                                                            \
      Parallel::Iterator                                                       \
      Pod::Coverage::CountParents                                              \
      Sereal                                                                   \
      Template                                                              && \
    rm -rf ~/.cpan/build ~/.cpan/sources/authors ~/.cpanm                      \
      ~/.local/share/.cpan/build ~/.local/share/.cpan/sources/authors
