
# Host requirements: gnu make 3.82+, docker, git, gnu awk, gnu grep, gnu xargs
# Container requirements (minimum): gnu make, gnu tar

# TODO assert required commands present
# TODO assert required make version
# TODO assert required docker version

# TODO default docker image?
DOCKER_IMAGE = amazonlinux:2016.09
BUILD_DIR = docker-build
RESULT_DIR = docker-result
IMAGE_NAME = $(if $(JOB_NAME),$(JOB_NAME)-docker-build,$(notdir $(CURDIR))-docker-build)

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

# 1. make flags
make_opts = $(strip $(patsubst %,-%,$(filter-out --%,$(1))) $(filter --%,$(1)))

# 1. make targets
# 2. make flags
make = $(ARCHIVE) | \
  docker run -i --rm \
  $(patsubst %,-e %,$(ENV_PASSTHROUGH)) \
  -v ~/.aws/credentials:/root/.aws/credentials:ro,Z \
  --volumes-from=$(BUILD) \
  -w /build \
  $(DOCKER_RUN_OPTS) \
  $(if $(IMAGE),$(IMAGE),$(DOCKER_IMAGE)) \
  sh -c "tar -x --warning=all && make $(call make_opts,$(2)) $(1)"

# 1. make targets
# 2. make flags
make_docker = $(call make,$(1),$(2)); \
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
	docker images --format='{{.Repository}}' $(IMAGE_NAME) | xargs -r docker rmi

_image:
ifneq ($(wildcard $(BUILD_DIR)),)
	$(info $(lastword $(MAKEFILE_LIST)): Building image...)
	$(eval IMAGE = $(shell docker build -q --rm -t $(IMAGE_NAME) $(BUILD_DIR)))
	$(if $(IMAGE),,$(error Could not build image))
else
	@printf '%s: Pulling image...\n' $(lastword $(MAKEFILE_LIST))
	docker pull $(DOCKER_IMAGE) > /dev/null
endif

_container: _image
	$(info $(lastword $(MAKEFILE_LIST)): Creating container...)
	$(eval BUILD = $(shell docker create -v /build $(if $(IMAGE),$(IMAGE),$(DOCKER_IMAGE)) /bin/true))
	$(if $(BUILD),,$(error Could not create container))

.PHONY: _all _clean _image _container
