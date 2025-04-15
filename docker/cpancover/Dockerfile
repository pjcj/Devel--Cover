# hadolint ignore=DL3007
FROM pjcj/devel-cover-dc:latest
RUN perl Makefile.PL && make t && make install && make clean && \
  echo 6 > version.txt
ENV PATH=/dc/utils:$PATH
