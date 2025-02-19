# Copyright (c) 2020 SAP SE or an SAP affiliate company. All rights reserved. This file is licensed under the Apache Software License, v. 2 except as noted otherwise in the LICENSE file
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

EXTENSION_PREFIX            := gardener-extension
NAME                        := runtime-gvisor
NAME_INSTALLATION           := runtime-gvisor-installation
CMD_DIRECTORY		        := ./cmd/$(EXTENSION_PREFIX)-$(NAME)
REGISTRY                    := eu.gcr.io/gardener-project/gardener
IMAGE_PREFIX                := $(REGISTRY)/extensions
REPO_ROOT                   := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
HACK_DIR                    := $(REPO_ROOT)/hack
VERSION                     := $(shell cat "$(REPO_ROOT)/VERSION")
LD_FLAGS_GENERATOR          := $(REPO_ROOT)/vendor/github.com/gardener/gardener/hack/get-build-ld-flags.sh
LD_FLAGS                    := $(shell $(LD_FLAGS_GENERATOR) k8s.io/component-base $(REPO_ROOT)/VERSION $(EXTENSION_PREFIX))

IGNORE_OPERATION_ANNOTATION := true

### GVisor versions
# - https://github.com/google/gvisor/releases (not all Github tags are available in the registry)
# - https://gvisor.dev/docs/user_guide/install/
# To update the runsc + shim binary:
#  1) Download latest: https://storage.googleapis.com/gvisor/releases/release/latest/x86_64/runsc
#  2) Execute runsc --version to find version
#  3) Check that specific specific release can be downloaded: https://storage.googleapis.com/gvisor/releases/release/20220425.0/x86_64/runsc
#  4) Update version below
GVISOR_VERSION				 	:= 20220425.0

#################################################################
# Rules related to binary build, Docker image build and release #
#################################################################

.PHONY: install
install:
	@LD_FLAGS="$(LD_FLAGS)" \
	$(REPO_ROOT)/vendor/github.com/gardener/gardener/hack/install.sh ./...

.PHONY: install-binaries
install-binaries:
	@bash $(HACK_DIR)/install-binaries.sh $(GVISOR_VERSION)

.PHONY: docker-login
docker-login:
	@gcloud auth activate-service-account --key-file .kube-secrets/gcr/gcr-readwrite.json

.PHONY: docker-images
docker-images:
	@docker build -t $(IMAGE_PREFIX)/$(NAME):$(VERSION) -t $(IMAGE_PREFIX)/$(NAME):latest -f Dockerfile -m 6g --target $(EXTENSION_PREFIX)-$(NAME) .
	@docker build -t $(IMAGE_PREFIX)/$(NAME_INSTALLATION):$(VERSION) -t $(IMAGE_PREFIX)/$(NAME_INSTALLATION):latest -f Dockerfile -m 200m --target $(EXTENSION_PREFIX)-$(NAME_INSTALLATION) .

#####################################################################
# Rules for verification, formatting, linting, testing and cleaning #
#####################################################################

.PHONY: install-requirements
install-requirements:
	@go install -mod=vendor $(REPO_ROOT)/vendor/github.com/ahmetb/gen-crd-api-reference-docs
	@go install -mod=vendor $(REPO_ROOT)/vendor/github.com/golang/mock/mockgen
	@go install -mod=vendor $(REPO_ROOT)/vendor/golang.org/x/tools/cmd/goimports
	@$(REPO_ROOT)/vendor/github.com/gardener/gardener/hack/install-requirements.sh

.PHONY: revendor
revendor:
	@GO111MODULE=on go mod vendor
	@GO111MODULE=on go mod tidy
	@chmod +x $(REPO_ROOT)/vendor/github.com/gardener/gardener/hack/*
	@chmod +x $(REPO_ROOT)/vendor/github.com/gardener/gardener/hack/.ci/*

.PHONY: clean
clean:
	@$(shell find ./example -type f -name "controller-registration.yaml" -exec rm '{}' \;)
	@$(REPO_ROOT)/vendor/github.com/gardener/gardener/hack/clean.sh ./cmd/... ./pkg/...

.PHONY: check-generate
check-generate:
	@$(REPO_ROOT)/vendor/github.com/gardener/gardener/hack/check-generate.sh $(REPO_ROOT)

.PHONY: check
check:
	@$(REPO_ROOT)/vendor/github.com/gardener/gardener/hack/check.sh --golangci-lint-config=./.golangci.yaml ./cmd/... ./pkg/...
	@$(REPO_ROOT)/vendor/github.com/gardener/gardener/hack/check-charts.sh ./charts

.PHONY: generate
generate:
	@$(REPO_ROOT)/vendor/github.com/gardener/gardener/hack/generate.sh ./charts/... ./cmd/... ./pkg/...

.PHONY: format
format:
	@$(REPO_ROOT)/vendor/github.com/gardener/gardener/hack/format.sh ./cmd ./pkg

.PHONY: test
test:
	@$(REPO_ROOT)/vendor/github.com/gardener/gardener/hack/test.sh ./cmd/... ./pkg/...

.PHONY: test-cov
test-cov:
	@$(REPO_ROOT)/vendor/github.com/gardener/gardener/hack/test-cover.sh ./cmd/... ./pkg/...

.PHONY: test-cov-clean
test-cov-clean:
	@$(REPO_ROOT)/vendor/github.com/gardener/gardener/hack/test-cover-clean.sh

.PHONY: verify
verify: check format test

.PHONY: verify-extended
verify-extended: install-requirements check-generate check format test-cov test-cov-clean

.PHONY: start
start:
	@./hack/start-gvisor-extension.sh -l "$(LD_FLAGS)" -d "$(CMD_DIRECTORY)" -i "$(IGNORE_OPERATION_ANNOTATION)" -r "$(REPO_ROOT)"
