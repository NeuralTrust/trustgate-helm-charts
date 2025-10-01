.PHONY: connect-dev connect-prod
connect-dev:
	@echo "connect to dev cluster..."
	gcloud container clusters get-credentials cluster-dev --region europe-west1 --project neuraltrust-app-dev

connect-prod:
	@echo "connect to prod cluster..."
	gcloud container clusters get-credentials neuraltrust --region europe-west1 --project neuraltrust-app-prod


# Deploy to development environment using Helm
deploy-dev:
	@echo "Deploying TrustScan to development environment..."
	gcloud container clusters get-credentials cluster-dev --region europe-west1 --project neuraltrust-app-dev
	helm upgrade --install trustgate ./helm-k8s \
		--namespace trustgate \
		--create-namespace \
		-f ./helm-k8s/values-dev.yaml
	@echo "Deployment to development environment completed successfully"

