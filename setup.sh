#!/bin/bash
set -e

# Replace with your GitHub username after forking the repositories
GITHUB_USER="lara-portilho"

clone_or_pull() {
  local repo=$1
  local dir=$2
  if [ -d "$dir/.git" ]; then
    echo "  [pull] $dir"
    git -C "$dir" pull --ff-only
  else
    echo "  [clone] $repo -> $dir"
    rm -rf "$dir"
    git clone "$repo" "$dir"
  fi
}

echo "==> Cloning microservices from forks..."
clone_or_pull "https://github.com/${GITHUB_USER}/FIAP-DevOps-auth-service"        services/auth-service
clone_or_pull "https://github.com/${GITHUB_USER}/FIAP-DevOps-flag-service"         services/flag-service
clone_or_pull "https://github.com/${GITHUB_USER}/FIAP-DevOps-targeting-service"    services/targeting-service
clone_or_pull "https://github.com/${GITHUB_USER}/FIAP-DevOps-evaluation-service"   services/evaluation-service
clone_or_pull "https://github.com/${GITHUB_USER}/FIAP-DevOps-analytics-service"    services/analytics-service

echo ""
echo "Done! Run: docker compose up --build"
