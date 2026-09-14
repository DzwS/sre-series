#!/usr/bin/env bash
set -euo pipefail

SESSION_NAME="${1:-sre}"
WORKDIR="${2:-$HOME}"

# 如果 session 已存在，直接 attach
if tmux has-session -t "${SESSION_NAME}" 2>/dev/null; then
  tmux attach -t "${SESSION_NAME}"
  exit 0
fi

# 1) 创建会话和第一个窗口：ops
tmux new-session -d -s "${SESSION_NAME}" -n ops -c "${WORKDIR}"

# 2) 其余窗口
tmux new-window -t "${SESSION_NAME}":2 -n observe -c "${WORKDIR}"
tmux new-window -t "${SESSION_NAME}":3 -n logs -c "${WORKDIR}"
tmux new-window -t "${SESSION_NAME}":4 -n debug -c "${WORKDIR}"
tmux new-window -t "${SESSION_NAME}":5 -n deploy -c "${WORKDIR}"
tmux new-window -t "${SESSION_NAME}":6 -n incident -c "${WORKDIR}"

# 3) 给每个窗口放一个提示命令（可按需替换）
tmux send-keys -t "${SESSION_NAME}":ops      'echo "[ops] kubectl/helm/git 操作窗口"' C-m
tmux send-keys -t "${SESSION_NAME}":observe  'echo "[observe] 观测窗口：top/stern/jq"' C-m
tmux send-keys -t "${SESSION_NAME}":logs     'echo "[logs] 持续日志窗口：kubectl logs -f / stern"' C-m
tmux send-keys -t "${SESSION_NAME}":debug    'echo "[debug] 排障窗口：kubectl exec / 网络探测"' C-m
tmux send-keys -t "${SESSION_NAME}":deploy   'echo "[deploy] 发布窗口：helm upgrade / rollout"' C-m
tmux send-keys -t "${SESSION_NAME}":incident 'echo "[incident] 告警应急窗口"' C-m

# 4) 默认选中 ops 并 attach
tmux select-window -t "${SESSION_NAME}":ops
tmux attach -t "${SESSION_NAME}"