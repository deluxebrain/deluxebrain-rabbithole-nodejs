APP_NAME							:= foo
DOCKER_REGISTRY				:= deluxebrain
IMAGE_REPOSITORY			:= $(DOCKER_REGISTRY)/$(APP_NAME)
DOCKERFILE_PATH				?= Dockerfile
DOCKER_BUILD_CONTEXT	?= .
COMMIT = $(shell git rev-parse --short HEAD)
NOW	= $(shell date +'%Y-%m-%d %H:%M:%S')
APP_VERSION = $(shell node -p "require ('./package.json').version")
CHART_DIR = ./chart/$(APP_NAME)/
ENV_PATH = ./environments/$(CLUSTER)/

ifdef CLUSTER
include $(ENV_PATH)/env.mk
endif

$(APP_NAME)-%.tgz:
	npm pack

build-image: $(APP_NAME)-$(APP_VERSION).tgz
	docker build \
		-t $(IMAGE_REPOSITORY):$(APP_VERSION) \
		-f $(DOCKERFILE_PATH) \
		--build-arg APP_NAME="$(APP_NAME)" \
		--build-arg VERSION="$(APP_VERSION)" \
		--build-arg REVISION="$(COMMIT)" \
		--build-arg NOW="$(NOW)" \
		$(DOCKER_BUILD_CONTEXT)

build-chart:
	helm package $(CHART_DIR) -d $(CHART_DIR)

ifneq ($(strip $(shell git status -s . | wc -l)),0)
publish:
	$(error There are outstanding changes!)
else
publish: version-app publish-image publish-chart tag-git
endif

publish-image: build-image audit-image tag-image
	@docker inspect $(IMAGE_REPOSITORY):$(APP_VERSION) --format '$(labels_formatter)'

publish-chart: version-chart build-chart

start:
	docker run -it --init --rm --name \
		$(APP_NAME) -p 3000:3000 $(IMAGE_REPOSITORY):$(APP_VERSION)

ifdef CLUSTER
test: test-cluster
else:
test:
endif

ifdef CLUSTER
status: status-cluster
else
status:
endif

ifdef CLUSTER
clean: clean-cluster
else
clean:
endif
	rm *.tgz || true
	docker system prune --force
	docker images --format '{{.Repository}}:{{.Tag}}' \
	| grep $(APP_NAME) \
	| xargs docker rmi

# k8s

ifndef CLUSTER
connect:
	$(error Cluster not specified!)
else
connect: connect-cluster
endif

ifndef CLUSTER
release:
	$(error Cluster not specified!)
else
release: audit-image release-cluster
endif

# Linting

audit-image: lint-dockle scan-trivy

lint-dockle:
ifdef RESOLVE_LATEST
	$(eval $(call latest_github_release,dockle_version,goodwithtech,dockle))
	$(eval dockle_version=v$(dockle_version))
else
	$(eval dockle_version=latest)
endif
	docker run --rm \
		-v /var/run/docker.sock:/var/run/docker.sock \
		goodwithtech/dockle:$(dockle_version) \
		--exit-code 1 \
		--exit-level warn \
		$(IMAGE_REPOSITORY):$(APP_VERSION)

scan-trivy:
ifdef RESOLVE_LATEST
	$(eval $(call latest_github_release,trivy_version,aquasecurity,trivy))
else
	$(eval trivy_version=latest)
endif
ifdef XDG_CONFIG_HOME
	docker run --rm \
		-v /var/run/docker.sock:/var/run/docker.sock \
		-v $(XDG_CONFIG_HOME):/root/.cache/ \
		aquasec/trivy:$(trivy_version) \
		--exit-code 1 \
		--severity MEDIUM,HIGH,CRITICAL \
		$(IMAGE_REPOSITORY):$(APP_VERSION)
else
	docker run --rm \
		-v /var/run/docker.sock:/var/run/docker.sock \
		aquasec/trivy:$(trivy_version) \
		--exit-code 1 \
		--severity MEDIUM,HIGH,CRITICAL \
		$(IMAGE_REPOSITORY):$(APP_VERSION)
endif

# Versioning

ifdef VERSION
version-app: VERSION_SPECIFIER=$(VERSION)
else
version-app: VERSION_SPECIFIER=patch
endif
version-app:
	$(eval APP_VERSION = $(shell npm version $(VERSION_SPECIFIER) \
		--no-git-tag-version \
		| sed 's/v//'))
	$(info Version bumped to: $(APP_VERSION))

version-chart: CHART_PATH = $(CHART_DIR)/Chart.yaml
version-chart:
	@sed \
		-e '/version/s/:.*/: $(APP_VERSION)/' \
		-e '/appVersion/s/:.*/: "$(APP_VERSION)"/' \
		$(CHART_PATH) > $(CHART_PATH).bak && \
	mv $(CHART_PATH).bak $(CHART_PATH)

tag-git: TAG=v$(APP_VERSION)
tag-git:
	git add -A .
	git commit -m "Release $(TAG)"
	git tag -a $(TAG) -m "Release $(TAG)"
	# git push $(TAG)

tag-image: tag-image-latest tag-image-commit

tag-image-latest: TAG=$(DOCKER_REGISTRY)/$(APP_NAME):latest
tag-image-latest:
	docker tag $(IMAGE_REPOSITORY):$(APP_VERSION) $(TAG)

tag-image-commit: TAG=$(DOCKER_REGISTRY)/$(APP_NAME):$(COMMIT)
tag-image-commit:
	docker tag $(IMAGE_REPOSITORY):$(APP_VERSION) $(TAG)

# Helpers

define labels_formatter =
{{ range $$k, $$v := .Config.Labels -}} \
{{ $$k }} = {{ $$v }}{{ println }} \
{{- end }}
endef

define latest_github_release =
 $(1) = $(shell \
 	curl --silent https://api.github.com/repos/$(2)/$(3)/releases/latest | \
 	grep '"tag_name":' | \
	sed -E 's/.*v([^"]+).*/\1/')
endef
