# Vikunja on Kubernetes (Helm + kind)

This repository demonstrates a deployment of the Vikunja ToDo List application on Kubernetes using Helm.

The setup is designed to be fully self-contained and runnable locally, while following production-oriented best practices where possible.
### Prerequisites
- Docker
- kind
- kubectl
- Helm

## Architecture
- Kubernetes: kind (local)
- Ingress: ingress-nginx
- Application: Vikunja
- Database: PostgreSQL
- IAM: Keycloak (OpenID Connect)
- Templating: Helm values files per component
- monitoring and visualization: Prometheus and Grafana

## Why Helm?
Helm was chosen as the deployment templating tool due to its strong ecosystem, native Kubernetes support, and ability to separate templates from environment-specific configuration. Each component (Vikunja backend, frontend, database, Keycloak, monitoring) is deployed with its own values file, allowing independent configuration and easier promotion to staging or production environments.

## Database Strategy
PostgreSQL is deployed as a self-hosted database using the Bitnami Helm chart.
This choice was made to keep the solution fully self-contained and runnable in a local Kubernetes environment (kind), which aligns with the constraints of a machine test.
In a production environment, a managed database service (e.g., AWS RDS or Cloud SQL) would be preferred to offload operational responsibilities such as backups, patching, and high availability.

## Networking & Ingress Optimization
ingress-nginx is used as the Ingress controller to provide HTTP routing and load balancing.
Services communicate internally using ClusterIP and Kubernetes DNS for low-latency service discovery.
External access is handled via Ingress resources with path-based routing, minimizing unnecessary network hops and ensuring efficient traffic flow.

## Authentication & IAM
Keycloak is integrated as an OpenID Connect (OIDC) provider to enable centralized authentication.
Vikunja is configured to trust Keycloak as its identity provider, allowing user authentication to be delegated while keeping authorization logic within the application.
This setup mirrors a production-grade IAM architecture where authentication and application logic are decoupled

## High Availability & Resilience
The Vikunja backend is deployed as a Kubernetes Deployment with readiness and liveness probes to ensure traffic is only routed to healthy pods.
Horizontal Pod Autoscaling (HPA) is enabled based on CPU utilization to automatically scale the backend under load.
Resource requests and limits are defined to prevent noisy-neighbor issues and ensure predictable scheduling.

## Monitoring & Observability
Prometheus is used to collect metrics from the Kubernetes cluster and the Vikunja backend, while Grafana provides visualization dashboards for service health, latency, error rates, and resource usage.
This setup enables quick diagnosis of performance issues, validation of autoscaling behavior, and basic capacity planning.

## Autoscaling
Horizontal Pod Autoscaling (HPA) is configured for the Vikunja backend using CPU utilization metrics provided by metrics-server.
Scale-up and scale-down behavior is explicitly tuned to avoid flapping while still responding quickly to load changes.
Autoscaling behavior can be validated using synthetic CPU or HTTP load as described below.

## Trade-offs & Future Improvements
For simplicity, static Prometheus scrape configurations and local storage are used.
In a production environment, improvements would include:
* Managed database services
* Kubernetes-native service discovery for monitoring
* Persistent Grafana storage
* Alerting rules based on SLOs
* External secrets management (e.g., Vault, AWS Secrets Manager)

## Bitnami Image Compatibility Note
Some Bitnami Helm charts reference container images that have been moved to
`docker.io/bitnamilegacy`. To ensure deterministic deployments, all affected images (Keycloak and PostgreSQL) are explicitly overridden in values.yaml files.

This avoids image pull failures without modifying upstream Helm charts.

## Steps to deploy whole setup in local mac/linux machine
### clone this repo and run "chmod +x deploy.sh", then run this bash script
./deploy.sh

#To test hpa
kubectl run loadgen -n vikunja --rm -it --image=busybox -- sh

#then from inside the loadgen pod run below command:
while true; do
  wget -q -O- http://vikunja-backend:3456/api/v1/info
done
kubectl exec -n vikunja deploy/vikunja-backend -- sh -c "while true; do :; done"