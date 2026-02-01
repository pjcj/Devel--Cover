# hadolint ignore=DL3007
FROM pjcj/perl-5.42.0:latest

WORKDIR /usr/local/src

# # Add Docker's official GPG key:
# sudo apt-get update
# sudo apt-get install ca-certificates curl
# sudo install -m 0755 -d /etc/apt/keyrings
# sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
# sudo chmod a+r /etc/apt/keyrings/docker.asc

# # Add the repository to Apt sources:
# echo \
#   "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
#   $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
#   sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
# sudo apt-get update

# hadolint ignore=DL3008
RUN                                                                          \
  apt-get update &&                                                          \
  apt-get -y --no-install-recommends install git libssl-dev libz-dev         \
    ca-certificates curl pigz &&                                             \
  update-ca-certificates &&                                                  \
  install -m 0755 -d /etc/apt/keyrings &&                                    \
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o                 \
    /etc/apt/keyrings/docker.asc &&                                          \
  chmod a+r /etc/apt/keyrings/docker.asc &&                                  \
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list && \
  apt-get update &&                                                          \
  apt-get -y --no-install-recommends install docker-ce docker-ce-cli         \
    containerd.io docker-buildx-plugin docker-compose-plugin &&              \
  rm -rf /var/lib/apt/lists/*

RUN                                                                          \
  cpan -Ti \
    CPAN::DistnameInfo \
    CPAN::Releases::Latest \
    Digest::MD5 \
    JSON::MaybeXS \
    Parallel::Iterator \
    Pod::Coverage::CountParents \
    Sereal \
    Template \
  && rm -rf ~/.cpan/build ~/.cpan/sources/authors ~/.cpanm                      \
    ~/.local/share/.cpan/build ~/.local/share/.cpan/sources/authors
