#!/bin/bash

set -Eeuo pipefail

printf "\n\t🐋 Build started 🐋\t\n"

# Remove '"' so it can be sourced by sh/bash
sed 's|"||g' -i "/etc/environment"

FROM_TAG="20.04"
ImageOS=ubuntu$(echo "${FROM_TAG}" | cut -d'.' -f 1)
AGENT_TOOLSDIRECTORY=/opt/hostedtoolcache
{
  echo "IMAGE_OS=$ImageOS"
  echo "ImageOS=$ImageOS"
  echo "LSB_RELEASE=${FROM_TAG}"
  echo "AGENT_TOOLSDIRECTORY=${AGENT_TOOLSDIRECTORY}"
  echo "RUN_TOOL_CACHE=${AGENT_TOOLSDIRECTORY}"
  echo "DEPLOYMENT_BASEPATH=/opt/runner"
  echo "USER=$(whoami)"
  echo "RUNNER_USER=$(whoami)"
} | tee -a "/etc/environment"

mkdir -m 0777 -p "${AGENT_TOOLSDIRECTORY}"
chown -R 1001:1000 "${AGENT_TOOLSDIRECTORY}"
#
#printf "\n\t🐋 Installing packages 🐋\t\n"
#packages=(
#  ssh
#  lsb-release
#  gawk
#  curl
#  git
#  jq
#  wget
#  sudo
#  gnupg-agent
#  ca-certificates
#  software-properties-common
#  apt-transport-https
#  libyaml-0-2
#  zstd
#  zip
#  unzip
#  xz-utils
#)
#
#apt-get -yq update
#apt-get -yq install --no-install-recommends --no-install-suggests "${packages[@]}"

ln -s "$(which python3)" "/usr/local/bin/python"

LSB_OS_VERSION=$(lsb_release -rs | sed 's|\.||g')
echo "LSB_OS_VERSION=${LSB_OS_VERSION}" | tee -a "/etc/environment"

#wget -qO "/imagegeneration/toolset.json" "https://raw.githubusercontent.com/actions/virtual-environments/main/images/linux/toolsets/toolset-${LSB_OS_VERSION}.json"
#wget -qO "/imagegeneration/LICENSE" "https://raw.githubusercontent.com/actions/virtual-environments/main/LICENSE"

ARCH=$(uname -m)
if [ "$ARCH" = x86_64 ]; then ARCH=x64; fi
if [ "$ARCH" = aarch64 ]; then ARCH=arm64; fi

if [[ "${FROM_TAG}" == "16.04" ]]; then
  printf 'git-lfs not available for Xenial'
else
  apt-get -yq install --no-install-recommends --no-install-suggests git-lfs
fi

printf "\n\t🐋 Updated apt lists and upgraded packages 🐋\t\n"

printf "\n\t🐋 Creating ~/.ssh and adding 'github.com' 🐋\t\n"
mkdir -m 0700 -p ~/.ssh
{
  ssh-keyscan -t rsa github.com
  ssh-keyscan -t rsa ssh.dev.azure.com
} >>/etc/ssh/ssh_known_hosts

printf "\n\t🐋 Installed base utils 🐋\t\n"

printf "\n\t🐋 Installing docker cli 🐋\t\n"
curl "https://packages.microsoft.com/config/ubuntu/${FROM_TAG}/prod.list" | tee /etc/apt/sources.list.d/microsoft-prod.list
wget -q https://packages.microsoft.com/keys/microsoft.asc
gpg --dearmor <microsoft.asc >/etc/apt/trusted.gpg.d/microsoft.gpg
apt-key add - <microsoft.asc
rm microsoft.asc
apt-get -yq update
apt-get -yq install --no-install-recommends --no-install-suggests moby-cli moby-buildx moby-compose

printf "\n\t🐋 Installed moby-cli 🐋\t\n"
docker -v

printf "\n\t🐋 Installed moby-buildx 🐋\t\n"
docker buildx version
IFS=' ' read -r -a NODE <<<"$NODE_VERSION"
for ver in "${NODE[@]}"; do
  printf "\n\t🐋 Installing Node.JS=%s 🐋\t\n" "${ver}"
  VER=$(curl https://nodejs.org/download/release/index.json | jq "[.[] | select(.version|test(\"^v${ver}\"))][0].version" -r)
  NODEPATH="$AGENT_TOOLSDIRECTORY/node/${VER:1}/$ARCH"
  mkdir -v -m 0777 -p "$NODEPATH"
  echo "https://nodejs.org/dist./latest-v${ver}.x/node-$VER-linux-$ARCH.tar.xz"
  curl -SsL "https://nodejs.org/dist./latest-v${ver}.x/node-$VER-linux-$ARCH.tar.xz" | tar -Jxf - --strip-components=1 -C "$NODEPATH"
  if [[ "${ver}" == "16" ]]; then
    sed "s|^PATH=|PATH=$NODEPATH/bin:|mg" -i /etc/environment
  fi
  export PATH="$NODEPATH/bin:$PATH"

  printf "\n\t🐋 Installed Node.JS 🐋\t\n"
  "${NODEPATH}"/bin/node -v

  printf "\n\t🐋 Installed NPM 🐋\t\n"
  "${NODEPATH}"/bin/npm -v
done

printf "\n\t🐋 Cleaning image 🐋\t\n"
apt-get clean
rm -rf /var/cache/* /var/log/* /var/lib/apt/lists/* /tmp/* || echo 'Failed to delete directories'

printf "\n\t🐋 Cleaned up image 🐋\t\n"

# shellcheck disable=SC1091
. /etc/environment

printf "\n\t🐋 Installing NVM tools 🐋\t\n"
VERSION=$(curl -s https://api.github.com/repos/nvm-sh/nvm/releases/latest | jq -r '.tag_name')
curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/$VERSION/install.sh" | bash
export NVM_DIR=$HOME/.nvm
echo "NVM_DIR=$HOME/.nvm" | tee -a /etc/environment

# Expressions don't expand in single quotes, use double quotes for that.shellcheck(SC2016)
# shellcheck disable=SC2016
echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm' | tee -a /etc/skel/.bash_profile

# Not following: ./nvm.sh was not specified as input (see shellcheck -x).shellcheck(SC1091)
# shellcheck disable=SC1091
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

printf "\n\t🐋 Installed NVM 🐋\t\n"
nvm --version

# node 12 and 16 are installed already in act-*
versions=("14")
JSON=$(wget -qO- https://nodejs.org/download/release/index.json | jq --compact-output)

for V in "${versions[@]}"; do
  printf "\n\t🐋 Installing NODE=%s 🐋\t\n" "${V}"
  VER=$(echo "${JSON}" | jq "[.[] | select(.version|test(\"^v${V}\"))][0].version" -r)
  NODEPATH="$AGENT_TOOLSDIRECTORY/node/${VER:1}/x64"

  # disable warning about 'mkdir -m -p'
  # shellcheck disable=SC2174
  mkdir -v -m 0777 -p "$NODEPATH"
  wget -qO- "https://nodejs.org/dist./latest-v${V}.x/node-$VER-linux-$ARCH.tar.xz" | tar -Jxf - --strip-components=1 -C "$NODEPATH"

  ENVVAR="${V//\./_}"
  echo "${ENVVAR}=${NODEPATH}" >>/etc/environment

  printf "\n\t🐋 Installed NODE 🐋\t\n"
  "$NODEPATH/bin/node" -v
done

printf "\n\t🐋 Installing JS tools 🐋\t\n"
npm install -g npm
npm install -g pnpm
npm install -g yarn
npm install -g grunt gulp n parcel-bundler typescript newman vercel webpack webpack-cli lerna
npm install -g --unsafe-perm netlify-cli

printf "\n\t🐋 Installed NPM 🐋\t\n"
npm -v

printf "\n\t🐋 Installed PNPM 🐋\t\n"
pnpm -v

printf "\n\t🐋 Installed YARN 🐋\t\n"
yarn -v

printf "\n\t🐋 Cleaning image 🐋\t\n"
apt-get clean
rm -rf /var/cache/* /var/log/* /var/lib/apt/lists/* /tmp/* || echo 'Failed to delete directories'
printf "\n\t🐋 Cleaned up image 🐋\t\n"