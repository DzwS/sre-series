# PostgreSQL on kind (with monitoring)

## 目标

- 在本地 `kind` 集群部署 PostgreSQL
- 通过 `kube-prometheus-stack` 采集 PostgreSQL 指标
- 在 Grafana 中查看监控数据

## 前置条件

- 已安装：`kubectl`、`kind`、`helm`
- 已安装 `kube-prometheus-stack`（命名空间 `monitoring`）
- 推荐 kind 镜像：`kindest/node:v1.30.8`（与仓库根 `README` 保持一致）

> 注意：以下账号密码仅用于本地实验，请勿用于生产环境。

## 1) 创建 Kubernetes 集群

```bash
kind create cluster --name postgresql --image kindest/node:v1.30.8
kubectl get nodes
```

## 2) 准备 PostgreSQL 命名空间与密钥

```bash
kubectl create ns postgresql
kubectl -n postgresql create secret generic postgresql \
  --from-literal POSTGRES_USER="postgresadmin" \
  --from-literal POSTGRES_PASSWORD='admin123' \
  --from-literal POSTGRES_DB="postgresdb" \
  --from-literal REPLICATION_USER="replicationuser" \
  --from-literal REPLICATION_PASSWORD='replicationPassword'
```

## 3) 部署 PostgreSQL

```bash
kubectl -n postgresql apply -f storage/databases/postgresql/yaml/statefulset.yaml
kubectl -n postgresql get pods -o wide
kubectl -n postgresql logs postgres-0
```

## 4) 部署监控（exporter + ServiceMonitor）

```bash
kubectl apply -f storage/databases/postgresql/yaml/monitoring/postgres-exporter.yaml
kubectl apply -f storage/databases/postgresql/yaml/monitoring/postgres-servicemonitor.yaml
```

## 5) 验证监控是否生效

```bash
kubectl -n postgresql get pods -l app=postgres-exporter
kubectl -n postgresql get svc postgres-exporter
kubectl -n postgresql get servicemonitor postgres-exporter
```

在集群内快速检查指标端点：

```bash
kubectl -n postgresql run curl --image=curlimages/curl:8.10.1 -it --rm --restart=Never -- \
  curl -s http://postgres-exporter:9187/metrics | head
```

## 6) 在 Grafana 查看

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
```

打开 `http://localhost:3000`，检查：

- `Status -> Targets` 中存在 `postgres-exporter` 且状态为 `UP`
- 可查询到指标：`pg_up`、`pg_stat_database_numbackends`、`pg_database_size_bytes`

## PostgreSQL 10 个核心监控指标

> 以下 PromQL 适用于 `postgres-exporter` 常见指标；不同版本指标名可能略有差异，可在 Grafana Explore 中先搜索 `pg_` 前缀确认。

1. **实例存活（Availability）**
   - 指标：`pg_up`
   - 含义：数据库是否可连接（`1` 正常，`0` 异常）
   - PromQL：
     ```promql
     pg_up
     ```

2. **当前连接数（Connections）**
   - 指标：`pg_stat_activity_count`
   - 含义：按状态统计连接数，识别连接泄漏/连接池异常
   - PromQL：
     ```promql
     sum by (state) (pg_stat_activity_count)
     ```

3. **连接使用率（Connection Saturation）**
   - 指标：`pg_stat_activity_count` + `pg_settings_max_connections`
   - 含义：连接占用比例，提前发现 `too many connections`
   - PromQL：
     ```promql
     sum(pg_stat_activity_count) / max(pg_settings_max_connections)
     ```

4. **事务吞吐 TPS（Throughput）**
   - 指标：`pg_stat_database_xact_commit` + `pg_stat_database_xact_rollback`
   - 含义：每秒事务量，反映业务整体负载
   - PromQL：
     ```promql
     sum(rate(pg_stat_database_xact_commit[5m]) + rate(pg_stat_database_xact_rollback[5m]))
     ```

5. **事务回滚率（Rollback Ratio）**
   - 指标：`pg_stat_database_xact_rollback` / 总事务
   - 含义：失败事务占比，反映应用错误或冲突问题
   - PromQL：
     ```promql
     sum(rate(pg_stat_database_xact_rollback[5m]))
     /
     sum(rate(pg_stat_database_xact_commit[5m]) + rate(pg_stat_database_xact_rollback[5m]))
     ```

6. **缓存命中率（Buffer Cache Hit Ratio）**
   - 指标：`pg_stat_database_blks_hit` / (`hit` + `read`)
   - 含义：越高越好，低命中率通常意味着磁盘读压力上升
   - PromQL：
     ```promql
     sum(rate(pg_stat_database_blks_hit[5m]))
     /
     (sum(rate(pg_stat_database_blks_hit[5m])) + sum(rate(pg_stat_database_blks_read[5m])))
     ```

7. **磁盘读写耗时（I/O Time）**
   - 指标：`pg_stat_database_blk_read_time`、`pg_stat_database_blk_write_time`
   - 含义：观察 I/O 层性能瓶颈趋势
   - PromQL：
     ```promql
     sum(rate(pg_stat_database_blk_read_time[5m]))
     ```
     ```promql
     sum(rate(pg_stat_database_blk_write_time[5m]))
     ```

8. **数据库体量（Database Size）**
   - 指标：`pg_database_size_bytes`
   - 含义：容量基线与增长趋势，支撑磁盘规划
   - PromQL：
     ```promql
     pg_database_size_bytes
     ```

9. **死锁次数（Deadlocks）**
   - 指标：`pg_stat_database_deadlocks`
   - 含义：并发冲突的高价值信号
   - PromQL：
     ```promql
     sum(increase(pg_stat_database_deadlocks[5m]))
     ```

10. **复制延迟（Replication Lag，主从场景）**
    - 指标：`pg_replication_lag`（或 exporter 版本对应 lag 指标）
    - 含义：衡量主从同步健康状态
    - PromQL：
      ```promql
      pg_replication_lag
      ```

### 建议告警优先级（起步）

- P1：`pg_up == 0`（实例不可用）
- P1：连接使用率 > `0.9` 持续 5 分钟
- P2：死锁 5 分钟内持续增长
- P2：缓存命中率持续低于 `0.95`

## 7) 清理环境

```bash
kind delete cluster --name postgresql
kind get clusters
```

若输出中不包含 `postgresql`，说明集群删除成功。

## 常见问题

- `ServiceMonitor` 创建了但没抓到数据：
  - 检查 `storage/databases/postgresql/yaml/monitoring/postgres-servicemonitor.yaml` 中 `metadata.labels.release` 是否与 Helm release 名一致（默认是 `kube-prometheus-stack`）。
- exporter 启动失败：
  - 确认 `postgresql` Secret 已创建，且包含 `POSTGRES_USER` / `POSTGRES_PASSWORD`。
- Grafana 没图：
  - 先在 Prometheus 或 Grafana Explore 里查询 `pg_up`，确认时序数据已写入。
