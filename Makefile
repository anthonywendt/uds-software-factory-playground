# The version of Zarf to use. To keep this repo as portable as possible the Zarf binary will be downloaded and added to
# the build folder.
ZARF_VERSION := v0.27.1

SWF_VERSION := 0.1.0

OCI_REGISTRY := oci://ghcr.io/anthonywendt

# Figure out which Zarf binary we should use based on the operating system we are on
ZARF_BIN := zarf

.DEFAULT_GOAL := help

# Idiomatic way to force a target to always run, by having it depend on this dummy target
FORCE:

.PHONY: help
help: ## Show a list of all targets
	@grep -E '^\S*:.*##.*$$' $(MAKEFILE_LIST) \
	| sed -n 's/^\(.*\): \(.*\)##\(.*\)/\1:\3/p' \
	| column -t -s ":"

.PHONY: clean
clean: ## Clean up build files
	@rm -rf ./build zarf-sbom

default-build: ## All in one make target for the default di2me repo (only x86) - uses the current branch/tag of the repo
	make build
	make build/zarf
	make build/zarf-init.sha256

build:
	mkdir -p build

build/zarf: | build ## Download the Linux flavor of Zarf to the build dir
	echo "Downloading zarf"
	curl -sL https://github.com/defenseunicorns/zarf/releases/download/$(ZARF_VERSION)/zarf_$(ZARF_VERSION)_Linux_amd64 -o build/zarf
	chmod +x build/zarf

build/zarf-init.sha256: | build ## Download the init package and create a small file with the sha256sum of the package so the Makefile can check whether it needs to be updated
	echo "Downloading zarf-init-amd64-$(ZARF_VERSION).tar.zst"
	curl -sL https://github.com/defenseunicorns/zarf/releases/download/$(ZARF_VERSION)/zarf-init-amd64-$(ZARF_VERSION).tar.zst -o build/zarf-init-amd64-$(ZARF_VERSION).tar.zst
	echo "Creating shasum of the init package"
	shasum -a 256 build/zarf-init-amd64-$(ZARF_VERSION).tar.zst | awk '{print $$1}' > build/zarf-init.sha256

create-and-init-k3d-cluster:
	k3d cluster create mycluster --api-port 6443 --no-lb --k3s-arg '--disable=servicelb' --k3s-arg '--disable=traefik@server:0' -v /etc/machine-id:/etc/machine-id@server:*
	k3d kubeconfig merge mycluster -o /home/ubuntu/cluster-kubeconfig.yaml
	utils/metallb/install.sh
	echo "Running default build"
	make default-build
	echo "Running zarf init"
	cd build && ./zarf init --components git-server --confirm
	echo "Cluster is ready!"

destroy-k3d-cluster:
	k3d cluster delete mycluster

build/dubbd: | build
	cd dubbd-copy/defense-unicorns-distro && ../../build/zarf package create . --confirm --output-directory ../../build

build/dubbd-k3d: | build
	cd dubbd-copy/k3d && ../../build/zarf package create . --confirm --output-directory ../../build

build/gitlab: | build
	cd gitlab && ../build/zarf package create . --confirm --output-directory ../build

build/gitlab-runner: | build
	cd gitlab-runner && ../build/zarf package create . --confirm --output-directory ../build

build/sonarqube: | build
	cd sonarqube && ../build/zarf package create . --confirm --output-directory ../build

build/nexus: | build
	cd nexus && ../build/zarf package create . --confirm --output-directory ../build

build/software-factory: | build
	cd software-factory && ../build/zarf package create . --confirm --output-directory ../build

########################################################################
# Deploy Section
########################################################################

deploy/all: | deploy/software-factory

deploy/init:
	./build/zarf init --confirm --components=git-server

deploy/dubbd-k3d:
	./build/zarf package deploy $(OCI_REGISTRY)/dubbd-k3d:2.2.0-amd64 --confirm

deploy/software-factory:
	cd software-factory && ../build/zarf package deploy $(OCI_REGISTRY)/software-factory:$(SWF_VERSION)-amd64 --confirm

########################################################################
# Publish Section
########################################################################

publish/all: | publish/zarf-flux-app-base publish/k3d-dubbd publish/gitlab publish/gitlab-runner publish/software-factory

publish/zarf-flux-app-base-skeleton:
	./build/zarf package publish zarf-flux-app-base $(OCI_REGISTRY) --oci-concurrency 9

publish/gitlab:
	./build/zarf package publish build/zarf-package-gitlab-amd64-0.0.1.tar.zst $(OCI_REGISTRY) --oci-concurrency 9

publish/sonarqube:
	./build/zarf package publish build/zarf-package-sonarqube-amd64-0.0.1.tar.zst $(OCI_REGISTRY) --oci-concurrency 9

publish/nexus:
	./build/zarf package publish build/zarf-package-nexus-amd64-0.0.1.tar.zst $(OCI_REGISTRY) --oci-concurrency 9

publish/gitlab-runner:
	./build/zarf package publish build/zarf-package-gitlab-runner-amd64-0.0.1.tar.zst $(OCI_REGISTRY) --oci-concurrency 9

publish/dubbd-skeleton:
	./build/zarf package publish dubbd-copy/defense-unicorns-distro $(OCI_REGISTRY) --oci-concurrency 9

publish/dubbd:
	./build/zarf package publish build/zarf-package-dubbd-amd64-2.2.0.tar.zst $(OCI_REGISTRY) --oci-concurrency 9

publish/dubbd-k3d:
	./build/zarf package publish build/zarf-package-dubbd-k3d-amd64-2.2.0.tar.zst $(OCI_REGISTRY) --oci-concurrency 9

publish/software-factory:
	./build/zarf package publish build/zarf-package-software-factory-amd64-$(SWF_VERSION).tar.zst $(OCI_REGISTRY) --oci-concurrency 9

######
# Lazy
######
build-publish-deploy/all: | publish/zarf-flux-app-base-skeleton publish/dubbd-skeleton build/dubbd-k3d publish/dubbd-k3d build/gitlab publish/gitlab build/gitlab-runner publish/gitlab-runner build/sonarqube publish/sonarqube build/nexus publish/nexus build/software-factory publish/software-factory deploy/all