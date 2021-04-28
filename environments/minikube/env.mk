NAMESPACE = foo
CLUSTER_TYPE = minikube
KUBECTL_CONTEXT = minikube

connect-cluster:
	minikube status -p minikube > /dev/null || minikube start
	kubectl config use-context $(KUBECTL_CONTEXT)

release-cluster: connect-cluster
	docker save $(IMAGE_REPOSITORY):$(APP_VERSION) \
	| (eval $$(minikube docker-env) && docker load)

	helm upgrade --install $(APP_NAME) \
		-f $(ENV_PATH)/values.yaml \
		--create-namespace \
		--namespace $(NAMESPACE) \
		$(CHART_DIR)/$(APP_NAME)-$(APP_VERSION).tgz

test-cluster:
	helm test --namespace $(NAMESPACE) $(APP_NAME)

status-cluster: connect-cluster
	eval $$(minikube docker-env) && \
	docker images && \
	minikube service --namespace $(NAMESPACE) --url $(APP_NAME)

clean-cluster: connect-cluster
	helm uninstall --namespace $(NAMESPACE) $(APP_NAME)
