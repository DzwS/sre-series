### Create a Kubernetes cluster

```
kind create cluster --name postgresql --image kindest/node:v1.28.0

kubectl get nodes
NAME                       STATUS   ROLES                  AGE   VERSION
postgresql-control-plane   Ready    control-plane,master   31s   v1.28.0
```


### settings up our postgresql env

Deploy a namespace to hold our resources:

```
kubectl create ns postgresql
```

Create our secret for our first PostgreSQL instance:

```
kubectl -n postgresql create secret generic postgresql \
  --from-literal POSTGRES_USER="postgresadmin" \
  --from-literal POSTGRES_PASSWORD='admin123' \
  --from-literal POSTGRES_DB="postgresdb" \
  --from-literal REPLICATION_USER="replicationuser" \
  --from-literal REPLICATION_PASSWORD='replicationPassword'
```

### Deploy our first PostgreSQL instance

Deploy our PostgreSQL instance:

```
kubectl -n postgresql apply -f storage/databases/postgresql/yaml/statefulset.yaml
```

Check our installation

```
kubectl -n postgresql get pods

# check the database logs
kubectl -n postgresql logs postgres-0

```

### Monitor PostgreSQL with kube-prometheus-stack

Apply exporter + ServiceMonitor:

```bash
kubectl apply -f storage/databases/postgresql/yaml/monitoring/postgres-exporter.yaml
kubectl apply -f storage/databases/postgresql/yaml/monitoring/postgres-servicemonitor.yaml
```

Verify resources:

```bash
kubectl -n postgresql get pods -l app=postgres-exporter
kubectl -n postgresql get svc postgres-exporter
kubectl -n postgresql get servicemonitor postgres-exporter -o yaml
```

Quick check metrics endpoint from inside cluster:

```bash
kubectl -n postgresql run curl --image=curlimages/curl:8.10.1 -it --rm --restart=Never -- \
  curl -s http://postgres-exporter:9187/metrics | head
```

Optional: port-forward Grafana and inspect dashboard/targets:

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
```

Then open Grafana and check:

- `Status -> Targets` contains `postgres-exporter` target in `UP` state
- PostgreSQL metrics like `pg_up`, `pg_stat_database_numbackends`, `pg_database_size_bytes`
