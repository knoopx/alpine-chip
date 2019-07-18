FROM ubuntu:bionic
RUN apt-get update && apt-get install --no-install-recommends -y \
  build-essential ca-certificates wget curl unzip git \
  qemu-user-static binfmt-support \
  img2simg u-boot-tools sunxi-tools

RUN apt-get install --no-install-recommends -y \
  build-essential zlib1g-dev liblzo2-dev uuid-dev libacl1-dev  && \
  git clone -b by/1.5.2/next-mlc-debian https://github.com/ntc-chip-revived/CHIP-mtd-utils.git && \
  cd CHIP-mtd-utils && make && make install
