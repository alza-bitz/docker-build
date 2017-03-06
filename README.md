# docker-build

A tool that allows projects to be built in [Docker](https://www.docker.com) containers using [Gnu Make](https://www.gnu.org/software/make), either locally or in cloud environments, whilst avoiding vendor lock-in of any cloud CI/CD integrated Docker support.

This approach ensures that any CI tasks remain locally reproducible. In addition, it permits the use of official upstream Docker images from Docker hub as far as possible.

## Credits

the inspiration and rationale for the tool came from the following blog article: http://tech.blog.jyu.fi/2016/04/evolution-of-makefile-for-docker-based.html

## Dependencies

The number of dependencies for the Docker host is deliberately kept small, since naturally one of the goals for the tool is to delegate build dependency management to the Docker container.

### For the Docker Host
- gnu make 3.82+
- docker
- git
- gnu awk
- gnu grep
- gnu tar (optional, will be needed if building your project with local modifications present)

### For the Docker Host (if Downloading docker-build, instead of Installing)
- bash (for process substitution)
- curl

### For the Docker Container
- gnu make
- gnu tar
- [tini](https://github.com/krallin/tini) (optional, will be needed in order to interrupt Gnu Make builds with ctrl+c etc)

## Install

### Using Git
```
git clone https://github.com/alzadude/docker-build.git
```

## Configure

### Makefiles

In order to keep all Docker related commands separate from the actual project specific commands, two separate Makefiles are required.

The first is the Docker-specific `docker.mk` Makefile already provided by the tool itself. This Makefile will execute on the Docker host.

The second is a traditional, non-Docker-specific Makefile which you provide in order to build your project. This Makefile will execute in a Docker container, which can expect all the needed build tools and other dependencies to exist.

### Docker Container and Build Results

The tool will create a Docker container and invoke Gnu Make against your project-specific Makefile with the targets specified. When Make returns, the tool will make the build results available in the `docker-result` sub-directory.

### Docker Images

The tool will provide any project-specific build tools and dependencies by building a Docker image using a `Dockerfile` that you can create in a `docker-build` sub-directory of your project. If you don't need any specific build tools beyond those provided by an existing Docker image (such as an official image on Docker Hub), you can specify this image using the `DOCKER_IMAGE` environment variable.

### Bash Completion

If your host has Bash completion installed for Gnu Make, the tool is capable of parsing your project's Makefile and offering completion for the Make targets in your project.

### Dry Run Targets

The tool provides an additional `*.dry-run` target for each Make target in your project. This will ensure that the Docker container will invoke Gnu Make with the `--dry-run` argument.

### Interrupting Builds

If you want to interrupt a Gnu Make build running in a Docker container, [tini](https://github.com/krallin/tini) will need to be installed in the image used by the container and available on the `PATH`.

To install tini in a Docker image, just add the following lines to the `Dockerfile` in the `docker-build` sub-directory:

```
ADD https://github.com/krallin/tini/releases/download/v0.10.0/tini /usr/local/bin/tini
RUN chmod a+x /usr/local/bin/tini
```

## Usage

### With docker-build Installed
```
cd <your-project>
make -f <path-to-docker-build>/docker.mk <target>
```
### With docker-build Installed, and Local Modifications Present
```
cd <your-project>
ARCHIVE="tar -c --exclude docker-result ." make -f <path-to-docker-build>/docker.mk <target>
```
### With docker-build Downloaded instead of Installed
```
cd <your-project>
make -f <(curl -L https://raw.githubusercontent.com/alzadude/docker-build/master/docker.mk) <target>
```

## License

Copyright © 2017 Alex Coyle

Released under the MIT license.
