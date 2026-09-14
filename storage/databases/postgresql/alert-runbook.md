# PostgreSQL Alert Runbook

> 适用范围：本仓库 `storage/databases/postgresql` 的 Kubernetes 部署方式（`StatefulSet + postgres-exporter + ServiceMonitor + kube-prometheus-stack`）
>
> 目标：告警触发后，先在 5 分钟内止血，再在 30 分钟内完成初步根因定位。

## 1. 值班处理总流程（SOP）

1. **确认告警有效性（1~2 分钟）**
   - 告警是否持续（避免瞬时抖动）
   - 是否多条相关告警同时触发（如 `pg_up=0` + exporter down）
2. **评估影响面（2~3 分钟）**
   - 影响环境（prod/staging）
   - 影响业务范围（写入失败、读延迟、完全不可用）
3. **先止血后定位**
   - 优先恢复可用性：重启、限流、扩容、切流
   - 再做根因分析：日志、指标、SQL、资源
4. **升级与协同**
   - 超过 10 分钟未恢复，升级 DBA / 应用 Oncall
5. **恢复验收与复盘**
   - 告警恢复、核心指标回归
   - 记录时间线、根因与长期修复项

---

## 2. 快速诊断命令（通用）

> 所有命令默认在仓库根目录执行。

```bash
kubectl -n postgresql get pods -o wide
kubectl -n postgresql describe pod postgres-0
kubectl -n postgresql logs postgres-0 --tail=200
kubectl -n postgresql get events --sort-by=.lastTimestamp | tail -n 30
```

```bash
kubectl -n postgresql get pods -l app=postgres-exporter -o wide
kubectl -n postgresql logs deploy/postgres-exporter --tail=200
kubectl -n postgresql get servicemonitor postgres-exporter -o yaml
```

```bash
kubectl -n monitoring get pods
kubectl -n monitoring get pods -l app.kubernetes.io/name=prometheus
```

---

## 3. 告警分级与处理

### P1：实例不可用（`pg_up == 0` 持续 2m）

**影响**
- 应用无法连接数据库，读写中断。

**5 分钟止血动作**
1. 确认 Pod 状态和重启次数。
2. 查看 `postgres-0` 最近日志（启动失败、权限、磁盘等）。
3. 必要时重启 Pod（本地/测试环境可直接删 Pod 触发重建）。

```bash
kubectl -n postgresql get pod postgres-0
kubectl -n postgresql logs postgres-0 --tail=200
kubectl -n postgresql delete pod postgres-0
```

**深入定位**
- PVC 是否绑定成功、存储是否可写
- Secret 是否存在且 key 正确
- 是否发生 OOMKill

**恢复验收**
- `pg_up == 1`
- `postgres-0` Ready
- 应用探活恢复

---

### P1/P2：连接使用率过高（> 90%，持续 5m）

**参考表达式**

```promql
sum(pg_stat_activity_count) / max(pg_settings_max_connections)
```

**影响**
- 新连接被拒绝，业务请求失败。

**5 分钟止血动作**
1. 识别连接暴涨来源（应用/批任务）。
2. 临时限流高峰流量。
3. 业务允许的前提下回收异常空闲连接。

**深入定位**
- 连接池参数是否过大（池上限、超时）
- 是否存在 `idle in transaction`
- 是否有慢 SQL 导致连接占用时间过长

**恢复验收**
- 连接使用率 < 80%
- 错误日志中不再出现 `too many connections`

---

### P2：事务回滚率升高（持续 10m）

**参考表达式**

```promql
sum(rate(pg_stat_database_xact_rollback[5m]))
/
sum(rate(pg_stat_database_xact_commit[5m]) + rate(pg_stat_database_xact_rollback[5m]))
```

**影响**
- 业务失败率提升，用户感知明显。

**5 分钟止血动作**
1. 检查最近发布或参数变更。
2. 若是新版本引入，优先回滚应用版本。

**深入定位**
- 锁冲突、唯一键冲突、语法错误、超时
- 对照应用日志按错误码聚类

**恢复验收**
- 回滚率回到基线
- 应用错误率下降

---

### P2：死锁增长（5m 内持续出现）

**参考表达式**

```promql
sum(increase(pg_stat_database_deadlocks[5m])) > 0
```

**影响**
- 部分事务失败、接口抖动。

**5 分钟止血动作**
1. 降低高并发写流量。
2. 终止明显异常长事务（谨慎）。

**深入定位**
- 排查更新顺序不一致的事务
- 分析热点表与高冲突 SQL

**恢复验收**
- 死锁增量归零或显著下降
- 接口失败率恢复基线

---

### P2：缓存命中率过低（< 95%，持续 15m）

**参考表达式**

```promql
sum(rate(pg_stat_database_blks_hit[5m]))
/
(sum(rate(pg_stat_database_blks_hit[5m])) + sum(rate(pg_stat_database_blks_read[5m])))
```

**影响**
- 磁盘读增大，查询时延上升。

**5 分钟止血动作**
1. 限制突发大查询。
2. 识别最慢 SQL 并优先优化热点语句。

**深入定位**
- 缺失索引 / 扫描策略不当
- 工作集超出内存导致频繁磁盘读取

**恢复验收**
- 命中率回升并稳定
- 查询时延回落

---

### P1/P2：复制延迟升高（主从场景）

**参考表达式（示例）**

```promql
pg_replication_lag > 30
```

**影响**
- 读写一致性变差，故障切换风险上升。

**5 分钟止血动作**
1. 降低写入洪峰（限流/批任务降速）。
2. 检查从库资源瓶颈（CPU/IO/网络）。

**深入定位**
- WAL 生成速度是否过快
- 从库回放是否受限

**恢复验收**
- 复制延迟回到可接受阈值

---

## 4. 告警升级策略（建议）

- **P1**：2 分钟内确认，10 分钟未恢复立即升级
- **P2**：5 分钟内确认，30 分钟未恢复升级
- **P3**：工作时间处理，纳入优化项

升级时同步信息：
- 告警名称 + 首次触发时间
- 影响范围（服务/租户/用户量）
- 已执行动作与结果
- 下一步计划与责任人

---

## 5. 恢复后复盘模板

1. 时间线（检测、确认、止血、恢复）
2. 根因（技术/流程/变更）
3. 为什么监控没更早发现（阈值/覆盖面/抑制规则）
4. 长期修复项（Owner + 截止日期）
5. Runbook 更新点

---

## 6. 推荐新增的告警（下一步）

- `pg_up == 0` 持续 2m（P1）
- 连接使用率 > 90% 持续 5m（P1）
- 死锁增量 > 0 持续 10m（P2）
- 缓存命中率 < 95% 持续 15m（P2）
- 复制延迟 > 30s 持续 5m（P1/P2，视业务而定）