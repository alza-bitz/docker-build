
# host requirements: gnu make 3.82?, docker, awk, grep, xargs
# TODO assert required make version
# TODO assert required commands present

# TODO default docker run args?
#DOCKER_RUN_ARGS="-v $PWD/../gnu-make-imin-lib:/usr/local/include:ro,Z"
# TODO default docker image?
DOCKER_IMAGE = amazonlinux:2016.09
BUILD_DIR = docker-build
RESULT_DIR = docker-result
IMAGE_NAME = $(if $(JOB_NAME),$(JOB_NAME)-docker-build,$(notdir $(CURDIR))-docker-build)

#ARCHIVE="tar -c --exclude docker-result ."
#ARCHIVE="git ls-files HEAD | tar -c -T -"
ARCHIVE ?= git archive HEAD

make = $(ARCHIVE) | \
  docker run -i --rm \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY \
  -v ~/.aws/credentials:/root/.aws/credentials:ro,Z \
  --volumes-from=$(BUILD) \
  -w /build \
  $(DOCKER_RUN_ARGS) \
  $(if $(IMAGE),$(IMAGE),$(DOCKER_IMAGE)) \
  sh -c "tar -x --warning=all && make $(1)"

.ONESHELL:

_all: _container
	@$(call make,)
	status=$$?
	docker cp $(BUILD):/build/. $(RESULT_DIR)
	docker rm -f -v $(BUILD) > /dev/null
	exit $$status

CMD = $(MAKE) -pRrq : 2>/dev/null | \
  awk -v RS= -F: '/^\# File/,/^\# Finished Make data base/ {if ($$1 !~ "^[\#.]") {print $$1}}' | \
  grep -v -E -e '^[^[:alnum:]]' -e '^$@$$' | \
  xargs

TARGETS = $(shell $(CMD))

$(TARGETS): _container
	@$(call make,$@)
	status=$$?
	docker cp $(BUILD):/build/. $(RESULT_DIR)
	docker rm -f -v $(BUILD) > /dev/null
	exit $$status

_clean:
	rm -rf $(RESULT_DIR)
	docker images -q $(IMAGE_NAME) | xargs -r docker rmi

_image:
ifneq ($(wildcard $(BUILD_DIR)),)
	$(info $(lastword $(MAKEFILE_LIST)): Building image...) \
	$(eval IMAGE = $(shell docker build -q --rm -t $(IMAGE_NAME) $(BUILD_DIR))) \
	$(if $(IMAGE),,$(error Could not build image))
else
	@printf '%s: Pulling image...\n' $(lastword $(MAKEFILE_LIST))
	docker pull $(DOCKER_IMAGE) > /dev/null
endif

_container: _image
	$(info $(lastword $(MAKEFILE_LIST)): Creating container...) \
	$(eval BUILD = $(shell docker create -v /build $(if $(IMAGE),$(IMAGE),$(DOCKER_IMAGE)) /bin/true)) \
	$(if $(BUILD),,$(error Could not create container))

.PHONY: _all _clean _image _container
