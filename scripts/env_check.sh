#!/bin/bash
# env_check.sh — Ascend 910B 推理环境自检（部署前 / 报数前跑一遍）
#
# 用法:
#   bash env_check.sh                # 用默认容器名 fnx、端口 8000
#   bash env_check.sh -c mycont -p 8018
#
# 输出：逐项 PASS / WARN / FAIL，末尾给结论；有 FAIL 时退出码非 0。
# 只读操作，不启动/停止任何服务。
set -u

CONTAINER=fnx
PORT=8000
while getopts "c:p:h" opt; do
  case "$opt" in
  c) CONTAINER=$OPTARG ;;
  p) PORT=$OPTARG ;;
  h) sed -n '2,10p' "$0"; exit 0 ;;
  *) ;;
  esac
done

PASS=0; WARN=0; FAIL=0
RESULTS=()

ok()   { PASS=$((PASS+1)); RESULTS+=("PASS|$1|$2"); }
warn() { WARN=$((WARN+1)); RESULTS+=("WARN|$1|$2"); }
bad()  { FAIL=$((FAIL+1)); RESULTS+=("FAIL|$1|$2"); }
row()  { RESULTS+=("-|$1|$2"); }

have() { command -v "$1" >/dev/null 2>&1; }
cexe() { docker exec "$CONTAINER" bash -lc "$1" 2>/dev/null; }

echo "==================== Ascend 910B 环境自检 ===================="
echo "时间: $(date '+%F %T')   容器: $CONTAINER   端口: $PORT"
echo

# ---------- 1. 系统 ----------
if [ "$(uname -m)" = "aarch64" ]; then ok "架构" "aarch64"; else bad "架构" "$(uname -m)（本项目只在 aarch64 上验证过）"; fi
if [ -f /etc/os-release ]; then
  osname=$(. /etc/os-release; echo "$PRETTY_NAME")
  case "$osname" in
  *openEuler*|*Kylin*|*Ubuntu*|*Euler*) ok "发行版" "$osname" ;;
  *) warn "发行版" "$osname（未验证，需自备 NPU 驱动）" ;;
  esac
else
  warn "发行版" "无法识别 /etc/os-release"
fi
row "内核" "$(uname -r)"
row "CPU" "$(awk -F: '/model name/{gsub(/^ +/,'',$2);print $2;exit}' /proc/cpuinfo 2>/dev/null || lscpu 2>/dev/null | sed -n 's/^型号名称： *//p' | head -1)  /  $(nproc) 核"
mem_gb=$(awk '/MemTotal/{printf "%d", $2/1048576}' /proc/meminfo 2>/dev/null)
if [ "${mem_gb:-0}" -ge 128 ]; then ok "内存" "${mem_gb} GB"; else warn "内存" "${mem_gb} GB（<128 GB，长上下文可能吃紧）"; fi
nofile=$(ulimit -n)
if [ "${nofile:-0}" -ge 8192 ]; then ok "ulimit -n" "$nofile"; else warn "ulimit -n" "$nofile（偏低，建议 65535）"; fi

# ---------- 2. NPU / 驱动 ----------
if ! have npu-smi; then
  bad "npu-smi" "未安装（驱动缺失？）"
else
  smi_ver=$(npu-smi info 2>/dev/null | sed -n 's/.*npu-smi \([0-9.]*\).*/\1/p' | head -1)
  cards=$(npu-smi info 2>/dev/null | grep -cE "^\| [0-9]+ +910")
  names=$(npu-smi info 2>/dev/null | grep -oE "910[A-Za-z0-9-]+" | sort -u | tr '\n' ' ')
  hbm=$(npu-smi info 2>/dev/null | grep -oE "[0-9]+/ +65536" | head -1 | tr -s ' ')
  if [ "${cards:-0}" -ge 1 ]; then ok "NPU 卡数" "$cards 张  ($names)"; else bad "NPU 卡数" "未发现 9xx 卡"; fi
  row "npu-smi" "${smi_ver:-未知}"
  [ -n "${hbm:-}" ] && row "HBM(已用/总)" "${hbm} MB"
  ids=$(npu-smi info 2>/dev/null | grep -E "^\| [0-9]+ +910" | awk '{print $2}' | tr '\n' ' ')
  row "NPU 逻辑 ID" "${ids:-未知}  ⚠️ 新机器务必确认（不一定是 0/1）"
fi
if [ -f /usr/local/Ascend/driver/version.info ]; then
  drv=$(sed -n 's/^Version=//p' /usr/local/Ascend/driver/version.info | head -1)
  hal=$(sed -n 's/^ascendhal_version=//p' /usr/local/Ascend/driver/version.info | head -1)
  ok "驱动版本" "Version=$drv  ascendhal=$hal"
else
  bad "驱动版本" "读不到 /usr/local/Ascend/driver/version.info"
fi

# ---------- 3. CANN ----------
cann_info=$(ls /usr/local/Ascend/*/aarch64-linux/ascend_toolkit_install.info 2>/dev/null | head -1)
if [ -n "$cann_info" ]; then
  cann_ver=$(sed -n 's/^version=//p' "$cann_info")
  cann_inner=$(sed -n 's/^innerversion=//p' "$cann_info")
  case "$cann_ver" in
  9.1.*) ok "CANN" "$cann_ver ($cann_inner)" ;;
  *) warn "CANN" "$cann_ver —— 本项目依赖 9.1 的 per-group W4A16 aclnn 接口" ;;
  esac
else
  bad "CANN" "找不到 ascend_toolkit_install.info（未装 CANN？）"
fi

# ---------- 4. Docker / 容器 ----------
if ! have docker; then
  bad "docker" "未安装"
else
  ok "docker" "$(docker --version | sed 's/Docker version //;s/, build.*//')"
  if docker inspect "$CONTAINER" >/dev/null 2>&1; then
    img=$(docker inspect "$CONTAINER" --format '{{.Config.Image}}')
    ok "容器 $CONTAINER" "运行中=$([ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER")" = true ] && echo 是 || echo 否)  镜像=$img"
    # 必需挂载
    for m in /models /root/ascend-dev /usr/local/Ascend/driver /usr/local/dcmi; do
      if docker inspect "$CONTAINER" --format '{{range .Mounts}}{{.Destination}} {{end}}' | grep -q "$m"; then
        have_mount=1
      else
        have_mount=0
      fi
      if [ "$have_mount" = 1 ]; then ok "挂载 $m" "已挂载"; else bad "挂载 $m" "缺失（容器内看不到）"; fi
    done
  else
    bad "容器 $CONTAINER" "不存在（docker ps -a 查看）"
  fi
fi

# ---------- 5. 容器内框架 ----------
if docker inspect "$CONTAINER" >/dev/null 2>&1 && docker inspect -f '{{.State.Running}}' "$CONTAINER" >/dev/null 2>&1; then
  py=$(cexe "python3 -V" | awk '{print $2}')
  row "容器 Python" "${py:-未知}"
  fw=$(cexe "python3 -c \"import torch,torch_npu;print(torch.__version__, torch_npu.__version__, torch.npu.is_available(), torch.npu.device_count())\"")
  if [ -n "$fw" ]; then
    t_v=$(echo "$fw" | awk '{print $1}')
    tn_v=$(echo "$fw" | awk '{print $2}')
    avail=$(echo "$fw" | awk '{print $3}')
    cnt=$(echo "$fw" | awk '{print $4}')
    if [ "$avail" = "True" ] && [ "${cnt:-0}" -ge 1 ]; then
      ok "torch / torch_npu" "torch=$t_v torch_npu=$tn_v 可用卡数=$cnt"
    else
      bad "torch / torch_npu" "torch=$t_v torch_npu=$tn_v npu_available=$avail 卡数=$cnt"
    fi
  else
    bad "torch / torch_npu" "容器内 import 失败"
  fi
  vllm=$(cexe "vllm --version 2>/dev/null | tail -1")
  [ -n "$vllm" ] && row "vLLM" "$vllm"
  tf=$(cexe "python3 -c \"import transformers;print(transformers.__version__)\"")
  [ -n "$tf" ] && row "transformers" "$tf"
  # NPU 计算冒烟（不占显存、1 秒内完成）
  smoke=$(cexe "python3 - <<'PY'
import torch, torch_npu
x = torch.randn(128, 128, device='npu:0'); y = torch.randn(128, 128, device='npu:0')
z = (x @ y).sum().item()
print('ok' if abs(z) == abs(z) else 'nan')
PY")
  case "$smoke" in
  ok) ok "NPU 计算冒烟" "128x128 matmul 正常" ;;
  *) bad "NPU 计算冒烟" "${smoke:-失败}" ;;
  esac
else
  warn "容器内检查" "容器未运行，跳过框架与冒烟检查"
fi

# ---------- 6. 权重与磁盘 ----------
for d in /models; do
  if [ -d "$d" ]; then
    free_gb=$(df -BG "$d" 2>/dev/null | awk 'NR==2{gsub(/G/,"",$4);print $4}')
    if [ "${free_gb:-0}" -ge 600 ]; then ok "磁盘 $d" "可用 ${free_gb} GB"; else warn "磁盘 $d" "可用 ${free_gb:-0} GB（一套 Flash-Next artifact 约 600 GB）"; fi
  else
    bad "磁盘 $d" "目录不存在"
  fi
done
root_free=$(df -BG / 2>/dev/null | awk 'NR==2{gsub(/G/,"",$4);print $4}')
if [ "${root_free:-0}" -ge 30 ]; then ok "磁盘 /" "可用 ${root_free} GB"; else warn "磁盘 /" "可用 ${root_free:-0} GB（日志容易写满）"; fi

# 权重包检查（存在即提示，不存在只 WARN）
found=0
for p in /models/*LQP*; do [ -d "$p" ] && found=$((found+1)); done
need=0
for p in /models/*LQP /models/*LQP-w4a16; do [ -d "$p" ] && need=$((need+1)); done
if [ "$need" -ge 2 ]; then ok "权重目录" "LQP + LQP-w4a16 齐全（共 $found 个 LQP* 目录）"
else warn "权重目录" "缺少必需 artifact（需要 *LQP 与 *LQP-w4a16，现共 $found 个 LQP* 目录）"; fi

# ---------- 7. 端口与服务 ----------
if have ss; then
  if ss -ltn 2>/dev/null | grep -q ":${PORT} "; then
    ok "端口 $PORT" "已监听"
    code=$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://127.0.0.1:${PORT}/v1/models" || true)
    if [ "$code" = "200" ]; then
      mid=$(curl -s -m 5 "http://127.0.0.1:${PORT}/v1/models" | python3 -c 'import json,sys;print(",".join(m["id"] for m in json.load(sys.stdin).get("data",[])))' 2>/dev/null || true)
      ok "推理服务" "/v1/models 200，model=${mid:-?}"
    else
      warn "推理服务" "/v1/models 返回 ${code:-无响应}（可能正在加载/图编译）"
    fi
  else
    row "端口 $PORT" "未监听（服务未启动，正常）"
  fi
fi

# ---------- 汇总 ----------
echo
printf '%s\n' "${RESULTS[@]}" | python3 -c '
import sys, unicodedata
rows = [l.rstrip("\n").split("|", 2) for l in sys.stdin if l.strip()]
def w(s):
    return sum(2 if unicodedata.east_asian_width(c) in ("W", "F") else 1 for c in s)
def pad(s, n):
    return s + " " * max(0, n - w(s))
n1 = max([4] + [w(r[1]) for r in rows])
n0 = max([4] + [w(r[0]) for r in rows])
print(pad("结果", n0) + "  " + pad("检查项", n1) + "  说明")
print("-" * n0 + "  " + "-" * n1 + "  " + "-" * 40)
for st, name, detail in rows:
    print(pad(st, n0) + "  " + pad(name, n1) + "  " + detail)
'
echo
echo "==================== 结论: PASS=$PASS WARN=$WARN FAIL=$FAIL ===================="
if [ "$FAIL" -gt 0 ]; then
  echo "存在 FAIL 项，请先修复再部署。"
  exit 1
elif [ "$WARN" -gt 0 ]; then
  echo "可以部署，但有 WARN 项建议先评估。"
  exit 0
else
  echo "环境检查全部通过。"
  exit 0
fi
