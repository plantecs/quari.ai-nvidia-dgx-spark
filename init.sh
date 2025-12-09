#!/usr/bin/env bash
set -euo pipefail

# Purpose: bootstrap a fresh DGX/Spark box with the latest TensorRT + AnythingLLM stack
# from https://github.com/plantecs/quari.ai-nvidia-dgx-spark.git and run the setup script.
#
# The script will:
#   1) Ask for the fully-qualified hostname to use for TLS and services
#   2) Set the system hostname (persistent when hostnamectl is available)
#   3) Clone or update the repo
#   4) Execute the latest TensorRT setup script
#
# Tunables via env vars (defaults shown):
#   WORKDIR=/opt/quari.ai-nvidia-dgx-spark
#   REPO_SSH=git@github.com:plantecs/quari.ai-nvidia-dgx-spark.git
#   REPO_HTTPS=https://github.com/plantecs/quari.ai-nvidia-dgx-spark.git
#   BRANCH=main
#   TARGET_SCRIPT=tensorrt_gpt-oss:120b_anythingllm_nginx.sh   # falls back to setup_llm.sh if missing

WORKDIR=${WORKDIR:-/opt/quari.ai-nvidia-dgx-spark}
REPO_SSH=${REPO_SSH:-git@github.com:plantecs/quari.ai-nvidia-dgx-spark.git}
REPO_HTTPS=${REPO_HTTPS:-https://github.com/plantecs/quari.ai-nvidia-dgx-spark.git}
BRANCH=${BRANCH:-main}
TARGET_SCRIPT=${TARGET_SCRIPT:-tensorrt_gpt-oss:120b_anythingllm_nginx.sh}

read -rp "Enter the fully-qualified hostname for this server (e.g., llm.example.com): " HOST_FQDN
if [[ -z "${HOST_FQDN}" ]]; then
  echo "Hostname is required. Exiting." >&2
  exit 1
fi

echo "Setting hostname to ${HOST_FQDN} ..."
if command -v hostnamectl >/dev/null 2>&1; then
  sudo hostnamectl set-hostname "${HOST_FQDN}" || hostname "${HOST_FQDN}"
else
  hostname "${HOST_FQDN}"
fi

echo "Working directory: ${WORKDIR}"
mkdir -p "${WORKDIR}"

clone_or_update() {
  if [[ -d "${WORKDIR}/.git" ]]; then
    echo "Updating existing repo..."
    git -C "${WORKDIR}" fetch --all --prune
    git -C "${WORKDIR}" checkout "${BRANCH}"
    git -C "${WORKDIR}" pull --ff-only
  else
    echo "Cloning repo via SSH (${REPO_SSH})..."
    if git clone "${REPO_SSH}" "${WORKDIR}"; then
      git -C "${WORKDIR}" checkout "${BRANCH}" || true
      return
    fi
    echo "SSH clone failed; falling back to HTTPS (${REPO_HTTPS})..."
    rm -rf "${WORKDIR}"
    git clone "${REPO_HTTPS}" "${WORKDIR}"
    git -C "${WORKDIR}" checkout "${BRANCH}" || true
  fi
}

clone_or_update

SCRIPT_PATH="${WORKDIR}/${TARGET_SCRIPT}"
if [[ ! -f "${SCRIPT_PATH}" ]]; then
  echo "${TARGET_SCRIPT} not found; trying setup_llm.sh" >&2
  SCRIPT_PATH="${WORKDIR}/setup_llm.sh"
fi

if [[ ! -f "${SCRIPT_PATH}" ]]; then
  echo "Setup script not found in repo. Aborting." >&2
  exit 1
fi

chmod +x "${SCRIPT_PATH}"
cd "${WORKDIR}"

# Export for scripts that consult hostname command; we already set it system-wide above.
export HOST_FQDN

echo "Running setup script with sudo: ${SCRIPT_PATH##*/}"
# Preserve HOST_FQDN for the setup run; prompt for password if needed.
sudo HOST_FQDN="${HOST_FQDN}" "${SCRIPT_PATH}"
