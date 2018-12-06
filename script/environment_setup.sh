#!/bin/bash -x

set -euxo pipefail

if [[ -n "$1" && -n "$2" ]]; then
	HOST_NAME=$1
	ROOT_PASSWD=$2
	echo "set sudo password to $ROOT_PASSWD and your username is $HOST_NAME"
else
        echo "you have to input your username and sudo password!"
        echo "    for example:./environment_setup.sh username password"
	exit
fi

basedir=$PWD
echo "Begin Environment Setup"

system_ver=`cat /etc/lsb-release | grep -i "DISTRIB_RELEASE" | cut -d "=" -f2`

#Get Config Parameters
CLEAN=`cat modules.conf | grep 'clean'`
CLEAN=${CLEAN##*=}
echo "Set CLEAN to $CLEAN"

ROS_DEBIAN=`cat modules.conf | grep 'ros_debian'`
ROS_DEBIAN=${ROS_DEBIAN##*=}
echo "Set ROS_DEBIAN to $ROS_DEBIAN"

OPENCV=`cat modules.conf | grep 'opencv'`
OPENCV=${OPENCV##*=}
echo "Set OPENCV to $OPENCV"

OPENCL=`cat modules.conf | grep 'opencl'`
OPENCL=${OPENCL##*=}
echo "Set OPENCL to $OPENCL"

DLDT=`cat modules.conf | grep 'dldt'`
DLDT=${DLDT##*=}
echo "Set DLDT to $DLDT"

MODEL_ZOO=`cat modules.conf | grep 'model_zoo'`
MODEL_ZOO=${MODEL_ZOO##*=}
echo "Set MODEL_ZOO to $MODEL_ZOO"

LIBREALSENSE=`cat modules.conf | grep 'librealsense'`
LIBREALSENSE=${LIBREALSENSE##*=}
echo "Set LIBREALSENSE to $LIBREALSENSE"

OTHER_DEPENDENCY=`cat modules.conf | grep 'other_dependency'`
OTHER_DEPENDENCY=${OTHER_DEPENDENCY##*=}
echo "Set OTHER_DEPENDENCY to $OTHER_DEPENDENCY"


# Clean Existing Directories
if [ "$CLEAN" == "1" ]; then
  echo "===================Cleaning...===================================="
  rm -rf ~/code
  #echo $ROOT_PASSWD | sudo -S apt-get purge -y ros-kinetic-*
  echo $ROOT_PASSWD | sudo -S rm -rf /opt/openvino_toolkit
  if [[ $system_ver = "16.04" && -L "/usr/lib/x86_64-linux-gnu/libboost_python3.so" ]]; then
    echo $ROOT_PASSWD | sudo -S rm /usr/lib/x86_64-linux-gnu/libboost_python3.so
  fi
fi

# Setup ROS from Debian
if [ "$ROS_DEBIAN" == "1" ]; then
  echo "===================Installing ROS from Debian Package...======================="
  echo $ROOT_PASSWD | sudo -S sh -c 'echo "deb http://packages.ros.org/ros/ubuntu $(lsb_release -sc) main" > /etc/apt/sources.list.d/ros-latest.list'
  echo $ROOT_PASSWD | sudo -S apt-key adv --keyserver hkp://ha.pool.sks-keyservers.net:80 --recv-key 421C365BD9FF1F717815A3895523BAEEB01FA116

  echo $ROOT_PASSWD | sudo -S apt-get update
  echo $ROOT_PASSWD | sudo -S apt-get install -y ros-kinetic-desktop-full

  if [ ! -f "/etc/ros/rosdep/sources.list.d/20-default.list" ]; then
    echo $ROOT_PASSWD | sudo -S rosdep init
  else
    echo "file already exists, skip..."
  fi

  set +o errexit
  rosdep update
  until [ $? == 0 ]
  do
    rosdep update
  done
  tail ~/.bashrc | grep "/opt/ros/kinetic/setup.bash"
  set -o errexit

  if [ "$?" == "1" ]; then
    echo "source /opt/ros/kinetic/setup.bash" >> ~/.bashrc
  else
    echo "ros kinetic already set, skip..."
  fi
  source ~/.bashrc
  echo $ROOT_PASSWD | sudo -S apt-get install -y python-rosinstall python-rosinstall-generator python-wstool build-essential
fi

# Setup OpenCV
if [ "$OPENCV" == "1" ]; then
  echo "===================Installing OpenCV3 from Source...======================="
  echo $ROOT_PASSWD | sudo -S apt-get install -y build-essential
  echo $ROOT_PASSWD | sudo -S apt-get install -y cmake git libgtk2.0-dev pkg-config libavcodec-dev libavformat-dev libswscale-dev
  echo $ROOT_PASSWD | sudo -S apt-get install -y python-dev python-numpy libtbb2 libtbb-dev libpng-dev libtiff-dev libjasper-dev libdc1394-22-dev

  if [ $system_ver = "18.04" ]; then
    echo $ROOT_PASSWD | sudo -S add-apt-repository "deb http://security.ubuntu.com/ubuntu xenial-security main"
    echo $ROOT_PASSWD | sudo apt update
    echo $ROOT_PASSWD | sudo apt install libjasper1 libjasper-dev
  else
    echo $ROOT_PASSWD | sudo -S apt-get install libjasper-dev
  fi

  mkdir -p ~/code && cd ~/code
  echo "begin clone opencv"
  git clone https://github.com/opencv/opencv.git
  git clone https://github.com/opencv/opencv_contrib.git
  echo "finish clone opencv"

  cd ~/code/opencv
  git checkout 3.4.0
  cd ~/code/opencv_contrib
  git checkout 3.4.0

  cd ~/code/opencv
  mkdir build && cd build
  cmake -DOPENCV_EXTRA_MODULES_PATH=/home/$HOST_NAME/code/opencv_contrib/modules -DCMAKE_INSTALL_PREFIX=/usr/local -DBUILD_opencv_cnn_3dobj=OFF ..
  make -j4
  echo $ROOT_PASSWD | sudo -S make install
  echo $ROOT_PASSWD | sudo -S ldconfig
  echo "==== END install OpenCV ===="
fi

# Setup OpenCL
if [ "$OPENCL" == "1" ]; then
  echo "===================Installing OpenCL Driver for GPU...======================="

  mkdir -p ~/code && cd ~/code
  wget http://registrationcenter-download.intel.com/akdlm/irc_nas/11396/SRB5.0_linux64.zip
  unzip SRB5.0_linux64.zip -d SRB5.0_linux64
  cd SRB5.0_linux64
  echo $ROOT_PASSWD | sudo -S apt-get install xz-utils
  mkdir intel-opencl
  tar -C intel-opencl -Jxf intel-opencl-r5.0-63503.x86_64.tar.xz
  tar -C intel-opencl -Jxf intel-opencl-devel-r5.0-63503.x86_64.tar.xz
  tar -C intel-opencl -Jxf intel-opencl-cpu-r5.0-63503.x86_64.tar.xz
  echo $ROOT_PASSWD | sudo -S cp -R intel-opencl/* /
  echo $ROOT_PASSWD | sudo -S ldconfig
  echo "==== END install OpenCL ===="
fi

# Setup DLDT
if [ "$DLDT" == "1" ]; then
  echo "===================Installing Deep Learning Deployment Toolkit...======================="

  if [[ -f /etc/lsb-release ]]; then
    sudo -E apt update
    sudo -E apt-get install -y \
            build-essential \
            cmake \
            curl \
            wget \
            libssl-dev \
            ca-certificates \
            git \
            libboost-regex-dev \
            gcc-multilib \
            g++-multilib \
            libgtk2.0-dev \
            pkg-config \
            unzip \
            automake \
            libtool \
            autoconf \
            libcairo2-dev \
            libpango1.0-dev \
            libglib2.0-dev \
            libgtk2.0-dev \
            libswscale-dev \
            libavcodec-dev \
            libavformat-dev \
            libgstreamer1.0-0 \
            gstreamer1.0-plugins-base \
            libusb-1.0-0-dev \
            libopenblas-dev
    if [ $system_ver = "18.04" ]; then
            sudo -E apt-get install -y libpng-dev
    else
            sudo -E apt-get install -y libpng12-dev
    fi
  fi
  mkdir -p  ~/code && cd ~/code
  git clone https://github.com/opencv/dldt.git
  cd dldt/inference-engine/
  git checkout 2018_R3
  #git submodule init
  #git submodule update --recursive
  mkdir build && cd build
  cmake -DCMAKE_BUILD_TYPE=Release ..
  make -j8
  echo $ROOT_PASSWD | sudo -S mkdir -p /opt/openvino_toolkit
  echo $ROOT_PASSWD | sudo -S ln -s ~/code/dldt /opt/openvino_toolkit/dldt
  echo "==== END install DLDT ===="
fi

# Setup open_model_zoo
if [ "$MODEL_ZOO" == "1" ]; then
  echo "===================Installing Open Model Zoo...======================="
  mkdir -p ~/code && cd ~/code
  git clone https://github.com/opencv/open_model_zoo.git
  cd open_model_zoo/demos/
  git checkout e238a1ac6bfacf133be223dd9debade7bfcf7dc5
  mkdir build && cd build
  cmake -DCMAKE_BUILD_TYPE=Release /opt/openvino_toolkit/dldt/inference-engine
  make -j8
  echo $ROOT_PASSWD | sudo -S mkdir -p /opt/openvino_toolkit
  echo $ROOT_PASSWD | sudo -S ln -s ~/code/open_model_zoo /opt/openvino_toolkit/open_model_zoo
  echo "==== END install open_model_zoo ===="
fi

# Setup LIBREALSENSE
if [ "$LIBREALSENSE" == "1" ]; then
  echo "===================Setting Up LibRealSense...======================="
  echo $ROOT_PASSWD | sudo -S apt-get install -y libssl-dev libusb-1.0-0-dev pkg-config libgtk-3-dev
  echo $ROOT_PASSWD | sudo -S apt-get install -y libglfw3-dev libgl1-mesa-dev libglu1-mesa-dev
  mkdir -p ~/code && cd ~/code
  git clone https://github.com/IntelRealSense/librealsense
  cd ~/code/librealsense
  git checkout v2.14.1
  mkdir build && cd build
  cmake ../ -DBUILD_EXAMPLES=true
  echo $ROOT_PASSWD | sudo -S make uninstall
  make clean
  make
  echo $ROOT_PASSWD | sudo -S make install

  cd ..
  echo $ROOT_PASSWD | sudo -S cp config/99-realsense-libusb.rules /etc/udev/rules.d/
  echo $ROOT_PASSWD | sudo -S udevadm control --reload-rules
  udevadm trigger
  echo "==== END install librealsense ===="
fi

# Setup other dependencies
if [ "$OTHER_DEPENDENCY" == "1" ]; then
  echo "===================Setting UP OTHER_DEPENDENCY DEPENDENCY...======================="
  pip3 install numpy
  echo $ROOT_PASSWD | sudo -S apt-get install python3-yaml
  if [ $system_ver = "16.04" ]; then
     echo $ROOT_PASSWD | sudo -S apt-get install -y --no-install-recommends libboost-all-dev
     cd /usr/lib/x86_64-linux-gnu
     sudo ln -s libboost_python-py35.so libboost_python3.so
  elif [ $system_ver = "18.04" ]; then
     echo $ROOT_PASSWD | sudo -S apt-get install -y --no-install-recommends libboost-all-dev
     sudo apt install libboost-python1.62.0
   fi
   echo "==== END install other dependencies ===="
fi

echo "Environment setup successfully"
