# lago\_ecosystem

## What is LAGO Ecosystem?

Lago Ecosystem is a build system for quick prototyping and working with the Zynq SoCs.

## Quickstart with the [Red Pitaya](http://redpitaya.com)

### 1. Requirements for Ubuntu 20.04 Focal Fossa

#### 1.1. Download and install [`Vitis Core Development Kit 2020.2`](https://www.xilinx.com/products/design-tools/vitis.html).

<!--#### 1.2 Run

```bash
$ sudo apt-get install curl
$ cd ~/Downloads
$ curl https://raw.githubusercontent.com/lagoprojectrp/lago_ecosystem/master/scripts/install_vivado.sh | sudo /bin/bash /dev/stdin
$ sudo ln -s make /usr/bin/gmake # tells Vivado to use make instead of gmake
```
-->
#### 1.2. Install requirements

```bash
$ sudo apt-get update

$ sudo apt-get --no-install-recommends install \
    build-essential git curl ca-certificates sudo \
    libxrender1 libxtst6 libxi6 lib32ncurses5 \
    crossbuild-essential-armhf \
    bc u-boot-tools device-tree-compiler libncurses5-dev \
    libssl-dev qemu-user-static binfmt-support \
    dosfstools parted debootstrap

$ git clone https://github.com/lagoprojectrp/lago_ecosystem
$ cd lago_ecosystem
```

### 2. Install LAGO Linux for Red Pitaya ([Download SD card image](https://mega.nz/file/1x500SzQ#I-k3LtOxLmN-VBHQXgzCrJ10x1OFs9E7NEM5Rpq72pM))

### 3. Build and run the minimal instrument

```bash
$ source settings.sh
$ make NAME=led_blinker
```

