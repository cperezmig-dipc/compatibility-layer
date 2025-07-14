#!/usr/bin/env bash

# Exit on error
set -e

# Default values
ARCH="x86_64"
REPOSITORY="repo.dipc.org"
VERSION="2023.06"
USERNAME="hpc-admin"
STRATUM0="stratum0.dipc.org"

# Help message
usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  -a, --arch ARCH           Set architecture (default: $ARCH)"
  echo "  -r, --repository REPO     Set repository name (default: $REPOSITORY)"
  echo "  -v, --version VERSION     Set version tag (default: $VERSION)"
  echo "  -u, --username USER       Set SSH username (default: $USERNAME)"
  echo "  -s, --stratum0 HOST       Set Stratum0 host (default: $STRATUM0)"
  echo "  -h, --help                Show this help message and exit"
  exit 0
}

# Parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    -a|--arch)
      ARCH="$2"
      shift 2
      ;;
    -r|--repository)
      REPOSITORY="$2"
      shift 2
      ;;
    -v|--version)
      VERSION="$2"
      shift 2
      ;;
    -u|--username)
      USERNAME="$2"
      shift 2
      ;;
    -s|--stratum0)
      STRATUM0="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

# Debug info (optional)
echo "ARCH: $ARCH"
echo "REPOSITORY: $REPOSITORY"
echo "VERSION: $VERSION"
echo "USERNAME: $USERNAME"
echo "STRATUM0: $STRATUM0"

cat << EOF > cfg/job.cfg
[site_config]
http_proxy=''
https_proxy=''
local_tmp=$HOME/tmp
load_modules=Apptainer

[architecture]
software_subdir=$ARCH/software

[repository]
repo_name=$REPOSITORY
repo_version=$VERSION
EOF

bot/build.sh 2>&1 | tee output.log
filename_tgz=$(cat output.log | tail -n 1 | cut -d ' ' -f1)
gunzip $filename_tgz
filename=$(basename $filename_tgz .gz)
metadata=$filename.json
jq -n \
    --arg un $(whoami) \
    --arg ip $(curl -s https://checkip.amazonaws.com) \
    --arg hn "$(hostname -f)" \
    --arg fn "$(basename ${filename})" \
    --arg sz "$(du -b "${filename}" | awk '{print $1}')" \
    --arg ct "$(date -r "${filename}")" \
    --arg sha256 "$(sha256sum "${filename}" | awk '{print $1}')" \
    --arg repo ${{ inputs.repository }} \
    --arg path "versions" \
    '{
    uploader: {username: $un, ip: $ip, hostname: $hn},
    payload: {filename: $fn, size: $sz, ctime: $ct, sha256sum: $sha256},
    target: {repository: $repo, path: $path},
    }' > "${metadata}"

scp $metadata $USERNAME@$STRATUM0:staging/metadata
scp $filename $USERNAME@$STRATUM0:staging/tarballs
