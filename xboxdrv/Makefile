PHONY: help

# build notebook lab test test-env push release

# Docker namespace, image name and version/tag
NS?= iancleary
IMAGE_NAME?= xboxdrv
VERSION?= latest

IMAGE=$(NS)/$(IMAGE_NAME)

#

USB_DEVICE_TEXT=$(shell )
USB_DEVICE_NUMBER="$(USB_DEVICE_NUMBER:6-8)"

# Shell that make should use
SHELL:=bash

# - to suppress if it doesn't exist
-include make.env

HELP_PADDING=10

help:
# http://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
# adds anything that has a double # comment to the phony help list
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ".:*?## "}; {printf "\033[36m%-$(HELP_PADDING)s\033[0m %s\n", $$1, $$2}'

build: DARGS?=
build: ## Make the latest build of the image
	docker build $(DARGS) --rm --force-rm -t $(NS)/$(IMAGE_NAME):$(VERSION) .

xbox: ARGS?=
xbox: DARGS?=
xbox: ## Run a container from a tagged image and start in the regular notebook view
	bash run.sh

.DEFAULT_GOAL := help
