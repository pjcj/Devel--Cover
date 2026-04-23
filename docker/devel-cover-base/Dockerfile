# hadolint ignore=DL3007
FROM pjcj/perl-5.42.2:latest

WORKDIR /usr/local/src

# hadolint ignore=DL3008
RUN apt-get update                                                          && \
    apt-get -y --no-install-recommends install                                 \
      ca-certificates curl git libssl-dev libz-dev pigz xz-utils            && \
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

# hadolint ignore=SC2016
RUN mkdir -p /root/.cpan/CPAN                                               && \
    printf '%s\n'                                                              \
      '$CPAN::Config = {'                                                      \
      '  urllist => ['                                                         \
      '    q(https://cpan.metacpan.org/),'                                     \
      '    q(https://www.cpan.org/),'                                          \
      '  ],'                                                                   \
      '}; 1;'                                                                  \
      > /root/.cpan/CPAN/MyConfig.pm                                        && \
    cpan -Ti                                                                   \
      App::cpanminus                                                           \
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
