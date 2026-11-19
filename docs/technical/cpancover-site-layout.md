# cpancover site layout

Three things decide which results a URL of cpancover.com shows. The environment
of a controller chooses the results tree it writes. A link in the web root gives
a tree its URL. The Caddy configuration names the web root and redirects the
bare site to one of the links.

## Overview

```text
  browser                          MetaCPAN
     |                                |
     | https://cpancover.com/...      | /latest/cpancover.json
     v                                v
+--------------------------------------------------------------------------+
| Caddy, /etc/caddy/Caddyfile                                              |
|   root * /data/cover/www                                                 |
|   redir / /latest/ 301                                                   |
+--------------------------------------------------------------------------+
     |
     v
/data/cover/www/
  latest -> ../staging ---------+
  dev    -> ../staging_dev --+  |
                             |  |
     +-----------------------+  +--------------------+
     |                                               |
     v                                               v
/data/cover/staging_dev/                 /data/cover/staging/
  index.html                               index.html
  cpancover.json                           cpancover.json
  <distdir>/index.html                     <distdir>/index.html
  <log_name>.out                           <log_name>.out
     ^                                               ^
     | mounted at /remote_staging                    | mounted at
     |                                               | /remote_staging
dev controller                           prod controller
  dc -e dev cpancover-controller-run       dc cpancover-controller-run
  image pjcj/cpancover_dev                 image pjcj/cpancover
  label cpancover.env=dev                  label cpancover.env=prod
```

The diagram shows a site that runs both environments. cpancover.com runs the
prod environment alone. A dev tree and its `dev` link exist only while a dev
controller is in use.

Read the diagram downwards for a request and upwards for the results of a build.
No part of the configuration ties a URL to an environment, so any tree can have
any URL.

## Results trees

A results tree is the directory that the `--results_dir` option of `utils/dc`
names. The `--env` option sets the default tree and the docker image, and labels
each container `cpancover.env=<env>`.

| `--env` | Results tree          | Image                |
| ------- | --------------------- | -------------------- |
| `prod`  | `~/cover/staging`     | `pjcj/cpancover`     |
| `dev`   | `~/cover/staging_dev` | `pjcj/cpancover_dev` |

`prod` is the default. The `--results_dir` and `--image` options override the
tree and the image, but `utils/dc` reads its options in order and each `--env`
sets both. So an `--env` that follows `--results_dir` or `--image` undoes them.
`--image` sets the image only of a container that the called recipe starts
itself, such as the controller. `cpancover` runs
`dc --env <env> cpancover-docker-module` for each release it builds, and that
`--env` sets the image again. So the build and render containers that a
controller starts use the image of the environment, not the one that `--image`
names. The `docker-build` recipe also reads the environment to choose which
image to build, what to build it from and whether to push it. The
`cpancover-serve` recipe reads it to name its web root. No file in a tree
records the environment that wrote it.

A controller is a container that a `cpancover-controller-*` recipe starts. It
mounts the results tree at `/remote_staging` and the docker socket of the host.
Each recipe that runs `dc` in the controller passes it `--env`, and inside a
container `--env` sets the results tree to `/remote_staging`. The controller
starts a container for each build and for each render through the socket. These
containers run `dc` without `--env` and mount no tree, so their results tree is
the default `~/cover/staging` inside the container. The controller copies the
result of each out with `docker cp` and moves the rendered report into the tree.

A tree holds these entries:

- `index.html`, `about.html`, `dist/<letter>.html`, `collection.css` and
  `collection.js` are the collection pages, which `cpancover --generate_html`
  writes.
- `cpancover.json` holds the coverage figures of every report, for other sites
  to fetch.
- `search.json` lists the distdirs that have report pages, for the search box of
  the collection pages to fetch.
- `<distdir>/` holds the report of one release. Its `index.html` is the summary
  page and its `cover.json` holds the figures.
- `<distdir>.tar.xz` is the archived report of a release that newer releases
  have replaced.
- `<log_name>.out` is the log of one build.
- `__failed__/`, `__rebuilt__/` and `.cpancover_status` hold the state of the
  build loop, which [cpancover rebuild mode](cpancover-rebuild.md) describes.

Every link between these pages is relative, so a tree works under any URL.

`dc cpancover-seed <src> <dest>` starts a new tree from an existing one. It
hard-links the distdirs and the build logs of the source tree and leaves out the
collection pages, `cpancover.json` and the archives.

## Web root

On cpancover.com `~/cover` is a link to `/cover`, which is a link to
`/data/cover`. That directory holds the tree and the web root of the prod
environment:

```text
/data/cover/
  staging/                 results tree of the prod environment
  www/                     web root
    latest -> ../staging
```

A dev environment adds its own tree and a link to it:

```text
/data/cover/
  staging_dev/             results tree of the dev environment
  www/
    dev    -> ../staging_dev
```

Each entry of `www` is a relative link to a results tree, and the name of the
link is the first part of the URL path. Caddy follows the links. A new link
gives a tree a new URL with no change to the Caddy configuration.

## Caddy

Caddy runs on the host as a systemd service and reads `/etc/caddy/Caddyfile`.
`cpancover_caddyfile` in `utils/dc` generates that file:

```text
cpancover.com, www.cpancover.com {
  root * /data/cover/www
  redir / /latest/ 301
  encode zstd gzip
  @logs path *.out
  header @logs Content-Type "text/plain; charset=utf-8"
  file_server {
    precompressed gzip
  }
  tls <address>
  log {
    output file /var/log/caddy/cpancover.com.log
    format console
  }
}
```

- `root` names the web root. The recipe resolves `$results_dir/../www` to its
  real path.
- `redir` sends a request for `/` to `/latest/`, so the bare site shows the tree
  that the `latest` link names. It is the only line that names a link.
- `encode` compresses a response when the client accepts that.
- The two `@logs` lines send a build log as plain text, so that a browser shows
  it and does not download it.
- `precompressed gzip` answers a request for `X` from `X.gz` when that file
  exists. With `CPANCOVER_COMPRESS` set, the build loop replaces each file `X`
  at the top of a report directory with `X.gz` and leaves an empty file named
  `X` beside it. It does not compress `.log_ref`, any JSON file such as
  `cover.json`, or any file in a subdirectory such as `assets/`. Without this
  directive Caddy would send the empty file.
- `log` names the access log, which needs `sudo` to read.

`dc cpancover-check-caddy` validates the generated file and shows how it differs
from the installed one. `dc cpancover-configure-caddy` installs the generated
file and reloads Caddy, which needs `sudo`.

## URLs

| URL                      | File under `/data/cover`       |
| ------------------------ | ------------------------------ |
| `/`                      | A redirect to `/latest/`       |
| `/latest/`               | `staging/index.html`           |
| `/latest/<distdir>/`     | `staging/<distdir>/index.html` |
| `/latest/cpancover.json` | `staging/cpancover.json`       |
| `/latest/<log_name>.out` | `staging/<log_name>.out`       |
| `/dev/`                  | `staging_dev/index.html`       |
| `/dev/<path>`            | `staging_dev/<path>`           |

The two `/dev/` rows apply only while the `dev` link exists.

MetaCPAN fetches `http://cpancover.com/latest/cpancover.json` for the coverage
figures it shows for a release. So the tree that `latest` names supplies both
the public site and MetaCPAN. The test mode of MetaCPAN fetches
`/latest/cpancover_dev.json`, which nothing in this repository writes.

## Changing the tree behind a URL

Make the new link under another name and rename it over the old one. The rename
replaces the link in one step, so no request finds the name missing.

```sh
cd ~/cover/www
ln -s ../staging_dev latest.new
mv -T latest.new latest
```

Moving a link does not change the tree that a controller writes. To change that,
stop the controller and start one with another `--env` or `--results_dir`.

## Serving a tree locally

`dc cpancover-serve [port]` serves the results tree of the chosen environment
with a temporary Caddy configuration, on port 8080 unless you give a port. It
makes the link `$results_dir/../www_<env>/latest` to the tree if that link does
not exist, so the pages appear at `http://localhost:8080/latest/` as they do on
the site.
