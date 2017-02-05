
# Host requirements: gnu make 3.82+, docker, git, gnu awk, gnu grep
# Container requirements: gnu make, gnu tar, (tini)

# TODO assert required commands present
# TODO assert required make version
# TODO assert required docker version

BUILD_DIR = docker-build
RESULT_DIR = docker-result
BUILD_IMAGE = $(if $(JOB_NAME),$(JOB_NAME)-docker-build,$(notdir $(CURDIR))-docker-build)

DOCKER_MAKEFLAGS = $(strip \
  $(subst n,,$(filter-out --%,$(MAKEFLAGS))) \
  $(filter-out --just-print --dry-run --recon,$(filter --%,$(MAKEFLAGS))))

export GIT_COMMIT ?= $(shell git rev-parse HEAD)
export GIT_BRANCH ?= $(shell git rev-parse --abbrev-ref HEAD)

GIT_PASSTHROUGH = GIT_COMMIT GIT_BRANCH
AWS_PASSTHROUGH = AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_PROFILE
ANSIBLE_PASSTHROUGH = ANSIBLE_FORCE_COLOR ANSIBLE_VAULT_PASSWORD_FILE

ENV_PASSTHROUGH = $(GIT_PASSTHROUGH) $(AWS_PASSTHROUGH) $(ANSIBLE_PASSTHROUGH)

#ARCHIVE="tar -c --exclude docker-result ."
#ARCHIVE="git ls-files HEAD | tar -c -T -"
ARCHIVE ?= git archive HEAD

STDERR_TTY = $(shell test -t 2 && printf tty)

# http://unix.stackexchange.com/a/102206
# http://serverfault.com/a/63708
# 1. cmd and args
define stderr_red
sh -c '{ \
  { \
    { \
      { \
        $(1) 3>&1 1>&4 2>&3; printf "%s" \$$? 1>&5; \
      } | { \
        while read; do printf "\""%b%s%b\n"\"" "\""\e[31m"\"" "\""\$$REPLY"\"" "\""\e[0m"\""; done; \
      } 1>&2; \
    } 5>&1; \
  } | (read; exit \$$REPLY) \
} 4>&1'
endef

# 1. cmd and args
docker_run = $(ARCHIVE) | \
  docker run -i --rm \
  $(patsubst %,-e %,$(ENV_PASSTHROUGH)) \
  -v ~/.aws/credentials:/root/.aws/credentials:ro,Z \
  --volumes-from=$(BUILD) \
  -w /build \
  $(DOCKER_RUN_OPTS) \
  $(if $(DOCKER_IMAGE),$(DOCKER_IMAGE),$(BUILD_IMAGE)) \
  sh -c "tar -x --warning=all && if command -v tini >/dev/null; then exec tini -g -- $(strip $(1)); else exec $(strip $(1)); fi;"

# 1. make flags
make_opts = $(strip $(patsubst %,-%,$(filter-out --%,$(1))) $(filter --%,$(1)))

# 1. make targets
# 2. make flags
make_docker = $(call docker_run, \
  $(if $(STDERR_TTY), \
    $(call stderr_red,make $(call make_opts,$(2)) $(1)), \
    make $(call make_opts,$(2)) $(1))); \
  status=$$?; \
  docker cp $(BUILD):/build/. $(RESULT_DIR); \
  docker rm -f -v $(BUILD) > /dev/null; \
  exit $$status

MAKE_LIST_TARGETS = $(MAKE) -pRrq : 2>/dev/null | \
  awk -v RS= -F: '/^\# File/,/^\# Finished Make data base/ {if ($$1 !~ "^[\#.]") {print $$1} else if ($$1 ~ "^\# makefile") {print $$2}}' | \
  grep -v -E -e '^[^[:alnum:]]' -e '^$@$$'

TARGETS = $(shell $(MAKE_LIST_TARGETS))

_all: _container
	@$(call make_docker,,$(DOCKER_MAKEFLAGS))

$(TARGETS): _container
	@$(call make_docker,$@,$(DOCKER_MAKEFLAGS))

$(addsuffix .dry-run,$(TARGETS)): _container
	@$(call make_docker,$(basename $@),$(DOCKER_MAKEFLAGS) --dry-run)

_clean:
	rm -rf $(RESULT_DIR)
	rm -rf docker-build.log
	if docker inspect $(BUILD_IMAGE) >/dev/null 2>&1; then docker rmi $(BUILD_IMAGE); fi

_image:
ifneq ($(DOCKER_IMAGE),)
	@printf '%s: Pulling image...\n' $(lastword $(MAKEFILE_LIST))
	@docker pull $(DOCKER_IMAGE) > docker-build.log
else ifneq ($(wildcard $(BUILD_DIR)),)
	@printf '%s: Building image...\n' $(lastword $(MAKEFILE_LIST))
	@docker build --rm -t $(BUILD_IMAGE) $(BUILD_DIR) > docker-build.log
else
	$(error Could not prepare image; docker-build dir not found, or DOCKER_IMAGE not given)
endif

_container: _image
	$(info $(lastword $(MAKEFILE_LIST)): Creating container...)
	$(eval BUILD = $(shell docker create -v /build $(if $(DOCKER_IMAGE),$(DOCKER_IMAGE),$(BUILD_IMAGE)) /bin/true))
	$(if $(BUILD),,$(error Could not create container))

.PHONY: _all _clean _image _container
