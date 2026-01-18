# Devel::Cover Docker Infrastructure

This directory contains the Docker infrastructure for running cpancover, the
service that generates code coverage reports for CPAN modules. The system uses
a layered Docker architecture to build and run coverage analysis in isolated
containers.

## Architecture Overview

The cpancover system uses a multi-layer Docker architecture:

```text
┌─────────────────────────────────────────────────────────────────┐
│                         Host System                             │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                    Controller Container                   │  │
│  │  (Orchestrates coverage runs, manages worker containers)  │  │
│  └─────────────┬─────────────────────────────────────────────┘  │
│                │                                                │
│                ▼                                                │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │               Worker Containers (per module)              │  │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐       │  │
│  │  │ Module  │  │ Module  │  │ Module  │  │ Module  │       │  │
│  │  │ Worker  │  │ Worker  │  │ Worker  │  │ Worker  │       │  │
│  │  └─────────┘  └─────────┘  └─────────┘  └─────────┘       │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  Results Directory: ~/cover/staging (mounted as /remote_staging)│
└─────────────────────────────────────────────────────────────────┘
```

## Docker Image Layers

The system builds Docker images in layers, each building upon the previous:

1. **perl-X.Y.Z** - Base Ubuntu with specific Perl version
2. **devel-cover-base** - Adds build tools, Docker, and CPAN dependencies
3. **devel-cover-dc** - Adds Devel::Cover source (git or local)
4. **cpancover** - Final image with Devel::Cover installed

### Image Details

#### perl-X.Y.Z (e.g., perl-5.42.0)

- Base: Ubuntu 24.04
- Installs specified Perl version from source
- Provides clean Perl environment

#### devel-cover-base

- Base: perl-X.Y.Z:latest
- Installs:
  - Development tools (git, libssl-dev, libz-dev)
  - Docker CE (for Docker-in-Docker capability)
  - Essential CPAN modules for cpancover operation
  - Compression tools (pigz)

#### devel-cover-dc (Development Cover)

- Base: devel-cover-base:latest
- Two variants:
  - **devel-cover-git**: Clones from GitHub repository
  - **devel-cover-local**: Copies from local source directory
- Contains Devel::Cover source code at /dc

#### cpancover

- Base: devel-cover-dc:latest
- Builds and installs Devel::Cover
- Sets up environment for coverage analysis
- Final production-ready image

## Build System

The `BUILD` script manages the entire build process:

```bash
# Basic build (uses main branch, pushes to Docker Hub)
./BUILD

# Development build (uses local source, no push)
./BUILD --env=dev

# Custom options
./BUILD --user=myuser --perl=5.40.2 --no-cache --nopush

# Build specific image
./BUILD --image=cpancover_dev --src=my_branch

# Access shell in specific container
./BUILD cpancover-shell
./BUILD devel-cover-dc-shell
```

### Build Options

- `--user`: Docker Hub username (default: pjcj)
- `--perl`: Perl version to use (default: 5.42.0)
- `--image`: Image name (cpancover or cpancover_dev)
- `--src`: Source branch/path (default: main)
- `--no-cache`: Force rebuild without cache
- `--nopush`: Skip pushing to Docker Hub
- `--env`: Environment (prod/dev)

## Running the System

### Local Development

For local development and testing:

```bash
# Set up environment
cd /path/to/Devel--Cover
. ./utils/setup

# Run coverage for specific modules
echo "Some::Module" | utils/dc cpancover

# Run with local changes
utils/dc --env=dev cpancover-build-module Some::Module
```

### Production Deployment

The production system runs on cpancover.com:

```bash
# Controller manages the overall process
utils/dc cpancover-controller-run

# Or run once for testing
utils/dc cpancover-controller-run-once
```

### Container Orchestration

The system uses two execution models:

#### 1. Direct Execution (Development)

```text
Host → cpancover binary → Docker containers (per module)
```

Commands that run orchestration **directly from the host**:

- `dc cpancover` - Runs cpancover binary on host
- `dc cpancover-build-module` - Builds single module from host
- `dc cpancover-run-once` - Full cycle from host
- `dc cpancover-generate-html` - Generates HTML from host

#### 2. Controller-based Execution (Production)

```text
Host → Controller container → Worker containers (per module)
```

Commands that run orchestration **through a controller container**:

- `dc cpancover-controller-run` - Continuous runs via controller
- `dc cpancover-controller-run-once` - Single run via controller
- `dc cpancover-controller-shell` - Access controller shell

The controller container:

- Has access to Docker socket for managing worker containers
- Mounts the results directory as `/remote_staging`
- Runs the cpancover orchestration logic inside the container
- Manages worker lifecycle (creation, monitoring, cleanup)
- Isolates the orchestration process from the host

## Module Coverage Workflow

1. **Module Selection**

   - Latest CPAN releases are fetched
   - Modules are queued for processing

2. **Container Creation**

   - Each module gets its own container
   - Container name: `{image}-{module}-{timestamp}`
   - Memory limited to 1GB
   - Timeout of 2 hours (configurable)

3. **Coverage Analysis**

   - Module is installed via CPAN
   - Tests are run with Devel::Cover enabled
   - Coverage database is generated

4. **Results Collection**

   - Coverage data copied from container
   - HTML reports generated
   - Results stored in staging directory

5. **Cleanup**

   - Container is stopped and removed
   - Temporary files cleaned up

## Results Management

Coverage results are organized as:

```text
~/cover/staging/
├── module-name-version/
│   ├── cover_db/         # Coverage database
│   ├── coverage.html     # HTML reports
│   └── coverage.json     # JSON summary
├── cpancover.json        # Overall summary
└── index.html            # Main index page
```

The system includes:

- Automatic compression of old results
- Generation of summary HTML/JSON
- Cleanup of temporary files

## Alternative: Minion Queue System

An experimental queue-based system using Mojolicious::Minion is available:

```bash
# Start minion worker
utils/dc cpancover-start-queue

# Start web interface
utils/dc cpancover-start-minion

# Add module to queue
utils/dc cpancover-add Some::Module
```

This provides:

- Web-based monitoring at <http://localhost:30000>
- SQLite-backed job queue
- Parallel job processing
- Integration with CPAN Testers infrastructure

## Troubleshooting

### Common Issues

1. **Docker permission errors**

   - Ensure user is in docker group: `sudo usermod -aG docker $USER`
   - Logout and login again for changes to take effect

2. **Build failures**

   - Check Perl version compatibility
   - Ensure all base images exist
   - Use `--no-cache` to force clean rebuild

3. **Container cleanup**

   ```bash
   # View running cpancover containers
   utils/dc cpancover-docker-ps

   # Kill stuck containers
   utils/dc cpancover-docker-kill

   # Remove all cpancover containers
   utils/dc cpancover-docker-rm
   ```

4. **Disk space issues**

   - Regular cleanup: `docker system prune`
   - Compress old results: `utils/dc cpancover-compress`
   - Remove old versions: `utils/dc cpancover-compress-old-versions`

### Debugging

- Add `--verbose` flag for detailed output
- Check container logs: `docker logs <container-name>`
- Access container shell: `./BUILD cpancover-shell`
- Review staging directory for partial results

## Environment Variables

- `CPANCOVER_RESULTS_DIR`: Override default results directory
- `COVER_DEBUG`: Enable debug output in queue system

## Security Considerations

- Containers run with limited memory (1GB)
- Automatic timeout prevents runaway processes
- Each module runs in isolation
- No persistent state between runs
- Docker socket access limited to controller container

## Development Guide

### Understanding Command Execution Modes

It's important to understand which commands run directly on the host vs through
a controller container:

**Direct Host Execution** (cpancover binary runs on host):

- `dc cpancover` - Main orchestration
- `dc cpancover-build-module` - Single module builds
- `dc cpancover-run-once` - One coverage cycle
- `dc cpancover-generate-html` - HTML generation
- `dc cpancover-compress*` - All compression commands
- Faster for development and single modules
- Requires Devel::Cover installed on host

**Controller Container Execution** (cpancover runs inside controller):

- `dc cpancover-controller-run` - Production continuous runs
- `dc cpancover-controller-run-once` - Single cycle via controller
- Better isolation from host system
- Used in production for reliability
- Controller manages all worker containers

### Quick Development Workflow

The typical development cycle for testing changes:

```bash
# 1. Build and test Devel::Cover locally
perl Makefile.PL && make test

# 2. Clean previous staging results (zsh syntax)
rm -rf ~/cover/staging*(N)

# 3. Build development Docker images with local changes
docker/BUILD -e dev

# 4. Run a single coverage cycle in dev environment (via controller container)
dc -e dev cpancover-controller-run-once

# 5. Examine results
dt ~/cover/staging*
```

**Alternative**: For faster iteration without controller container:

```bash
# Run directly from host (faster for single modules)
dc -e dev cpancover-build-module Some::Module
```

### Development vs Production Environments

The system supports two environments configured via `--env`:

#### Development Environment (`--env=dev`)

- Uses local source code from working directory
- Staging directory: `~/cover/staging_dev`
- Docker image: `pjcj/cpancover_dev`
- No automatic pushing to Docker Hub
- Builds using `docker/devel-cover-local`

#### Production Environment (`--env=prod`)

- Clones from GitHub repository
- Staging directory: `~/cover/staging`
- Docker image: `pjcj/cpancover`
- Can push to Docker Hub
- Builds using `docker/devel-cover-git`

### Running Specific Modules

**Note**: These commands run orchestration directly from the host, not through a
controller container.

```bash
# Test a single module in development (direct execution)
dc -e dev cpancover-build-module Some::Module

# Test multiple specific modules (direct execution)
echo -e "Module::One\nModule::Two" | dc -e dev cpancover

# Test with verbose output (direct execution)
dc -v -e dev cpancover-build-module Some::Module

# Force rebuild even if already covered (direct execution)
dc -f -e dev cpancover-build-module Some::Module

# To run through controller container instead:
dc -e dev cpancover-controller-run-once
```

### Advanced Docker Operations

#### Building Images

```bash
# Build with specific Perl version
docker/BUILD --perl=5.40.2

# Build from a specific branch
docker/BUILD --src=feature-branch

# Build without cache (clean build)
docker/BUILD --no-cache

# Build for a different Docker Hub user
docker/BUILD --user=myusername --nopush
```

#### Debugging Containers

```bash
# Access shell in final cpancover image
docker/BUILD cpancover-shell

# Access shell in intermediate images
docker/BUILD devel-cover-base-shell
docker/BUILD devel-cover-dc-shell

# Start a debug shell with staging mounted
dc -e dev cpancover-docker-shell

# Access controller container shell
dc -e dev cpancover-controller-shell

# Inspect running containers
dc cpancover-docker-ps

# View container logs
docker logs <container-name>

# Follow container logs in real-time
docker logs -f <container-name>
```

### Production Management

#### Initial Setup

```bash
# On production server (cpancover.com)
cd /cover/dc
. ./utils/setup

# Install cpancover-specific Perl
dc install-cpancover-perl 5.42.0
```

#### Running Production

```bash
# Start continuous coverage runs via controller (runs every 10 minutes)
# This creates a controller container that manages all worker containers
dc cpancover-controller-run

# Monitor production containers
dc cpancover-docker-ps

# Emergency cleanup (runs directly on host)
dc cpancover-docker-kill
dc cpancover-docker-rm
```

#### Production Image Updates

```bash
# 1. Build and test locally
docker/BUILD --env=dev
dc -e dev cpancover-controller-run-once

# 2. Build production image from main branch
docker/BUILD

# 3. On production server, pull new image
docker pull pjcj/cpancover:latest

# 4. Restart coverage runs
# (Stop existing controller first)
dc cpancover-controller-run
```

### Custom Module Lists

```bash
# Create a custom module list
cat > modules.txt << EOF
DBI
Mojolicious
Moose
EOF

# Run coverage on custom list (direct execution from host)
dc cpancover < modules.txt

# Or use module file option (direct execution from host)
dc cpancover --module_file=modules.txt

# To run custom list through controller container:
# First copy modules.txt to staging, then:
dc cpancover-controller-shell
# Inside container:
dc cpancover < /remote_staging/modules.txt
```

### Performance Tuning

```bash
# Adjust worker count (default: number of CPUs)
dc cpancover --workers=8

# Change timeout (default: 7200 seconds = 2 hours)
dc cpancover --timeout=3600

# Run with lower memory limit
docker run -it --memory=512m pjcj/cpancover dc cpancover-build-module \
  Some::Module
```

### Debugging Coverage Failures

When a module fails coverage analysis:

```bash
# 1. Check for __failed__ marker
ls ~/cover/staging/*/__failed__

# 2. Run module directly with verbose output
dc -v cpancover-build-module Failed::Module

# 3. Run in interactive container
docker run -it --rm pjcj/cpancover_dev /bin/bash
# Then inside container:
dc -v cpancover-build-module Failed::Module

# 4. Check CPAN installation issues
docker run -it --rm pjcj/cpancover_dev cpan -Ti Failed::Module
```

### Monitoring and Logs

```bash
# View cpancover logs
tail -f /tmp/dc.log

# Monitor Docker resource usage
docker stats

# Check disk usage
df -h ~/cover/staging
du -sh ~/cover/staging/*

# Find large uncompressed files
find ~/cover/staging -type f -size +10M -not -name "*.gz"
```

### Development Tips

1. **Local Testing Without Docker**

   ```bash
   # Run cpancover directly
   perl -Mblib bin/cpancover --local --workers=1 Some::Module
   ```

2. **Testing Image Builds**

   ```bash
   # Build only base images
   docker build -t test/perl docker/perl-5.42.0
   docker build -t test/base docker/devel-cover-base
   ```

3. **Debugging Perl Issues**

   ```bash
   # Check Perl configuration in container
   docker run --rm pjcj/cpancover perl -V

   # Test module installation
   docker run --rm pjcj/cpancover cpan -Ti Some::Module
   ```

4. **Using Alternative Results Directory**

   ```bash
   dc --results_dir=/tmp/coverage cpancover-build-module Some::Module
   ```

### Maintenance Tasks

**Note**: These maintenance commands run directly on the host, not through
containers.

```bash
# Compress all results (direct execution)
dc cpancover-compress

# Keep only latest 3 versions of each distribution (direct execution)
dc cpancover-compress-old-versions 3

# Generate fresh HTML index (direct execution)
dc cpancover-generate-html

# Full cleanup and restart (all direct execution)
dc cpancover-docker-kill
dc cpancover-docker-rm
docker system prune -af
rm -rf ~/cover/staging/*
```

### Integration with CI/CD

For automated testing in CI:

```bash
# Build specific module and check coverage
dc --env=dev cpancover-build-module Your::Module
if [[ -f ~/cover/staging_dev/Your-Module-*/coverage.json ]]; then
    coverage=$(jq .summary.Total ~/cover/staging_dev/My-Module-*/coverage.json)
    echo "Coverage: $coverage%"
fi
```

## Future Improvements

- Kubernetes deployment support
- Enhanced resource limits per module
- Distributed worker nodes
- Real-time progress monitoring
- Integration with CI/CD systems
