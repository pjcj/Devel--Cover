FROM ubuntu:24.04

ENV TERM=xterm
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# hadolint ignore=DL3008
RUN apt-get update && apt-get -y --no-install-recommends   install wget build-essential   && rm -rf /var/lib/apt/lists/*

RUN wget --progress=dot:giga http://www.cpan.org/src/5.0/perl-5.40.2.tar.gz   -O - | tar xzvf - -C /usr/local/src
WORKDIR /usr/local/src/perl-5.40.2
RUN ./Configure -des && make install
WORKDIR /
RUN rm -rf /usr/local/src/perl-5.40.2
