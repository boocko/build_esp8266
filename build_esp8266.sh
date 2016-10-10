#!/bin/bash
#*********************************************************************************************
# ESP8266 MicroPython Firmware Build on RPi, by gojimmypi
#
#  version 0.07
#
#  GNU GENERAL PUBLIC LICENSE
#
# NOTE: you will need a lot of free disk space. This will likely not work on an 8GB RPi SD.
#
# 25SEP16 - added make mpy-cross
# 24MAY16 - implement execUntilSuccessful to allow repeat retries calling esptool.py
# 15APR16 - ensure python3 serial is installed
# 14APR16 - check device at startup using esptool.py --port /dev/ttyUSB0 flash_id
# 13ARP16 - support for use on Debian linux in addition to RPi Raspian
# 12APR16 - only update the path if ../xtensa-lx106-elf/.. not found in path
#         - remove hard coded path reference to /home/pi/ for general debian use
#
#*******************************************************************************************************
# For new RPi install, on a windows machine:
#
# download latest raspian
# https://downloads.raspberrypi.org/raspbian_latest
#
# for info see https://www.raspberrypi.org/downloads/raspbian/
#*******************************************************************************************************
# For windows client (used to write Pi image to new RPi)
#
# download win32diskimager
# https://sourceforge.net/projects/win32diskimager/files/Archive/Win32DiskImager-0.9.5-install.exe/download
#
# for info see https://sourceforge.net/projects/win32diskimager/
#*******************************************************************************************************
#
# See http://forum.micropython.org/viewtopic.php?f=16&t=1655    Portion reprinted here:
#
# Building the SDK
#
# Read all about setting up your ESP SDK directly on pfalcon/esp-open-sdk. The SDK gets updated every
# now and then, watch out for the crucial and major updates. See the Troubleshooting post section if
# you hit any issues.
#
# See README.md at  https://github.com/pfalcon/esp-open-sdk
#
# Building the Firmware
#
# For the latest instructions on how to build and upload your existing firmware see micropython/esp8266.
# The developers are working hard to get the existing alpha work merged into the main project. Do not
# be surprised if you see people talking about features that seemingly do not exist in the current
# repository, rest assured, they are on the way. The latest master branch changes fast, if you're
# interested in a stable version of micropython, please use one of the release tags.
#
# Flashing the Firmware
#
# It is important to note, if you are using a non-official ESP breakout board and using a form of USB
# to Serial adapter to flash your chip, you should be careful about how you're powering your module as
# this has caused problems for new users before. Please see "How to correctly power my module up?"
# section of the "Technical FAQ".
#
MYDEVICE="/dev/ttyUSB0"
MYBAUD="115200"  # could be as high as 460800
DEVICEFOUND=0

#*******************************************************************************************************
# startup: show help as needed
#*******************************************************************************************************
if [ "$1" == "" ] ||  [ "$1" == "HELP" ]; then
  echo "Usage:"
  echo "build_esp8266 [OPTION]"
  echo ""
  echo "OPTIONS"
  echo ""
  echo "  HELP"
  echo "    show this help. Source will be placed in ~/workspace/ directory."
  echo ""
  echo "  FULL"
  echo "     Update OS and installed apps, download latest esp-open-sdk and micropython, build everything, erase and upload new binary to $MYDEVICE"
  echo ""
  echo "  MAKE-ONLY"
  echo "     Download latest esp-open-sdk and micropython, build everything."
  echo ""
  echo "  MAKE-ONLY-ESP8266"
  echo "     Download latest micropython and build (skip esp-open-sdk)."
  echo ""
  echo "  RUN-TESTS"
  echo "     Run the esp8266 test script"
  echo ""
  echo "  FLASH-ONLY"
  echo "     Only writing existing flash to device. (no updates, no build)"
  exit 0
fi

if [ "$1" != "FULL" ] && [ "$1" != "MAKE-ONLY" ] &&  [ "$1" != "MAKE-ONLY-ESP8266" ] &&  [ "$1" != "FLASH-ONLY" ]  &&  [ "$1" != "RUN-TESTS" ]; then
  echo "$1  not a valid option. try ./build_esp8266.sh HELP "
  exit 0
fi

#*******************************************************************************************************
#  a function to wrap commands in a repeat-until-successful loop
#*******************************************************************************************************
function execUntilSuccessful() {
  echo "running command: " $1
  eval $1
  EXIT_STAT=$?
  while [ $EXIT_STAT -ne 0 ]; do
    echo ""
    echo "Error: a problem was found attempting to execute this step."
    echo ""
    echo "Try simply pressing reset on the ESP8266"
    read -n 1  -p "Press a key to try again (or Ctrl-C to abort)..."
    eval $1
    EXIT_STAT=$?
  done
}



#*******************************************************************************************************
# ensure we are not running as root
#  (try to peek in /root directory, assume non-root user does not have access)
#*******************************************************************************************************
ls /root > /dev/null 2>/dev/null
EXIT_STAT=$?
if [ $EXIT_STAT -ne 0 ];then
  echo "Confirmed we are not running as root. (but there may be sudo prompts!"
else
  echo "Aborted. Do not run with sudo (compile errors will occur)."
  exit 2
fi


echo ""
#*******************************************************************************************************
# now check if sudo is installed (some installs must run as root, but build must not)
#*******************************************************************************************************
sudo ls /root > /dev/null 2>/dev/null
EXIT_STAT=$?
if [ $EXIT_STAT -ne 0 ];then
  echo "sudo appears to not be installed. attempting to install with su."
  echo "You will need to enter root password several times."
  echo "Press Ctrl-C now if you want to install and configure sudo yourself."
  echo ""
  read -n 1  -p "Press a key to continue..."
  echo ""
  su --command 'apt-get install sudo  --assume-yes'
  echo "Adding $USER to /etc/sudoers..."
  THISUSER=$(whoami)
  su --command "echo '$THISUSER ALL=(ALL:ALL) ALL' >> /etc/sudoers"
  THISUSER=

  # test again
  sudo ls /root > /dev/null 2>/dev/null
  EXIT_STAT=$?
  if [ $EXIT_STAT -ne 0 ];then
    echo "Error: sudo appears to not be installed. please run as root:"
    echo "apt-get install sudo"
    echo ""
    echo "Then edit /etc/sudoers"
    echo "Add the line: $USER ALL=(ALL:ALL) ALL"
    exit 2
  else
    echo "It appears sudo install was successful and is working properly."
  fi
else
  echo "It appears sudo is installed and working properly."
fi

echo ""
if ! [[ -a ~/workspace ]]; then
  echo "Creating directory ~/workspace"
  mkdir ~/workspace
fi

#*******************************************************************************************************
# git the esptool
#*******************************************************************************************************
echo "*************************************************************************************************"
echo "*************************************************************************************************"
echo "*  Get latest esptool "
echo "*************************************************************************************************"
echo "*************************************************************************************************"
cd ~/workspace
if ! [[ -a ~/workspace/esptool ]]; then
  echo "git clone esptool..."
  git clone https://github.com/themadinventor/esptool/
fi

cd ~/workspace/esptool/
# TODO - are these git commands really all needed for updates?
git submodule update --init

git fetch origin
git pull

# the next git commmands are suggested on https://github.com/pfalcon/esp-open-sdk
git pull
git submodule sync
git submodule update

chmod +x ~/workspace/esptool/esptool.py

#*******************************************************************************************************
# check to see if a device is connected amd send the new firmware
#*******************************************************************************************************
echo ""
echo "Checking device at $MYDEVICE..."
if [ -c "$MYDEVICE" ]; then
  DEVICEFOUND=1
  echo "*************************************************************************************************"
  echo "*  Changing permissions on $MYDEVICE"
  echo "*************************************************************************************************"
  if [[ -a /home/pi/ ]]; then
    sudo chown pi:pi "$MYDEVICE"
  else
    sudo chmod 777 "$MYDEVICE"
    THISUSER=$(whoami)
    # old cmd: sudo adduser $THISUSER dialout # this is not immediately effective
    sudo gpasswd -a "$THISUSER" dialout
    # refresh group membership without logging out
    # echo $(newgrp dialout) # this starts a new shell
  fi
else
  echo "Device $MYDEVICE not found. You will need to manually upload firmware."
  echo "See MYDEVICE setting in this script."
  echo ""
  echo "Try simply pressing reset."
  read -n 1  -p "Press a key to continue (or Ctrl-C to abort)..."
fi


#*******************************************************************************************************
# use esptool.py to check connected device
#*******************************************************************************************************
if [ "$DEVICEFOUND" == "1" ]; then
  echo ""
  echo "Checking connected device at $MYDEVICE at $MYBAUD baud with esptool..."

  execUntilSuccessful "~/workspace/esptool/esptool.py --port $MYDEVICE --baud $MYBAUD flash_id"
fi

#*******************************************************************************************************
#*******************************************************************************************************
# check commandline params
#*******************************************************************************************************
#*******************************************************************************************************

#*******************************************************************************************************
# check if we are doing a FULL update, inclusing OS updates
#*******************************************************************************************************
if [ "$1" == "FULL" ]; then
  echo "*************************************************************************************************"
  echo "*************************************************************************************************"
  if [[ -a /home/pi/ ]]; then
    echo "  Updating Raspberry Pi and install dependencies as needed... "
  else
    echo "  Updating Debian and install dependencies as needed... "
  fi
  echo "*************************************************************************************************"
  echo "*************************************************************************************************"

  #*******************************************************************************************************
  #
  #*******************************************************************************************************
  # update RPi firmware (we assume this is an RPi if there's a /home/pi/ directory.
  if [[ -a /home/pi/ ]]; then
    sudo rpi-update --assume-yes
  fi

  # standard update
  sudo apt-get update --assume-yes && time sudo apt-get dist-upgrade --assume-yes

  # git should be installed, but let's just be sure

  sudo apt-get install git --assume-yes

  # RPi usually has the build tools installed, but perhaps Debian does not
  sudo apt-get install build-essential --assume-yes

  # completely optional, but I like to have xrdp (so that I can use Windows remote desktop)
  # sudo apt-get install xrdp

  # also optional is samba, so that I can mount the RPi as a Windows share
  # can be very handy for getting files onto & off of RPi
  # sudo apt-get install samba samba-common-bin
  # sudo smbpasswd -a pi
  # sudo smbpasswd -a root

  ## edit the file /etc/samba/smb.conf and put in these lines at the end (without single # comment markers!)
  ##*******************************************************************************************************
  # [home]
  #   comment= root
  #   path=/home/pi
  #   browseable=Yes
  #   writeable=Yes
  #   only guest=no
  #   create mask=0777
  #   directory mask=0777
  #   public=no
  #


  # every linux user should know how to use VI / VIM, right? (optional)
  # sudo apt-get install vim

  # I also like to have the optional dns tools installed (optional)
  # sudo apt-get install dnsutils

  # this is the big ESP8266 requirement install from pfalcon (slightly modified)
  sudo apt-get install make autoconf automake libtool gcc g++ gperf flex bison texinfo gawk ncurses-dev libexpat-dev python python-serial sed git unzip bash --assume-yes

  # listed as "maybe" but was required for me on raspian jessie
  sudo apt-get install libtool-bin --assume-yes

  # to run the /micropython/tests/run-tests we need to have python serial support installed
  sudo apt-get install python3-serial --assume-yes

  # install help2man
  sudo apt-get install help2man

  sudo apt-get install python2.7-dev

  # unrar install gave an error this error, so pulled out into separate install
  # even with the error, sees to work ok
  #
  # Package unrar is not available, but is referred to by another package.
  # This may mean that the package is missing, has been obsoleted, or
  # is only available from another source
  echo "It seems that the missing unrar can be ingored, but included here anyhow... (is it really needed? ignore the error)"
  sudo apt-get install unrar
fi # end of if - RPi system update



# now for the source code

# we'll put everything in the home workspace directory
cd ~
if ! [[ -a ~/workspace ]]; then
  echo "create directory: workspace"
  mkdir ~/workspace
fi

if [ "$1" == "MAKE-ONLY" ] || [ "$1" == "FULL" ]; then
  #*******************************************************************************************************
  # check that gcc is installed before attempting to build
  #*******************************************************************************************************
  echo "*************************************************************************************************"
  echo "*************************************************************************************************"
  echo " Checking toolchain basics... "
  echo "*************************************************************************************************"
  echo "*************************************************************************************************"

  whereis gcc make
  EXIT_STAT=$?
  if [ $EXIT_STAT -ne 0 ];then
    echo "Error: make not found"
    exit 2
  else
    echo "Success: It appears make was found."
  fi

  gcc -v
  EXIT_STAT=$?
  if [ $EXIT_STAT -ne 0 ];then
    echo "Error: gcc not found"
    exit 2
  else
    echo "Success: It appears gcc was found."
  fi

  make -v
  EXIT_STAT=$?
  if [ $EXIT_STAT -ne 0 ];then
    echo "Error: make not found"
    exit 2
  else
    echo "Success: It appears make was found."
  fi

  #*******************************************************************************************************
  # next fetch the pfalcon esp-open-sdk from github
  # (I believe pfalcon warning that the esp=open-sdk needs to be rebuilt fresh every time!)
  #*******************************************************************************************************
  cd ~/workspace
  if ! [[ -a ~/workspace/esp-open-sdk ]]; then
    echo "git clone esp-open-sdk"
    git clone --recursive https://github.com/pfalcon/esp-open-sdk.git
  fi

  echo "*************************************************************************************************"
  echo "*************************************************************************************************"
  echo "*  Update latest esp-open-sdk from git "
  echo "*************************************************************************************************"
  echo "*************************************************************************************************"
  cd ~/workspace/esp-open-sdk

  make clean

  git submodule update --init
  git fetch origin

  # the next git commmands are suggested on https://github.com/pfalcon/esp-open-sdk
  git pull
  git submodule sync
  git submodule update

  echo "*************************************************************************************************"
  echo "*************************************************************************************************"
  echo "*  make esp-open-sdk (highly recommended, but takes a long time to build) "
  echo "*************************************************************************************************"
  echo "*************************************************************************************************"
  # TODO - determine if git fetched anything new, if not, no need to rebuild!
  # compile esp-open-sdk (this takes a ridiculously long time)
  make

  echo ""
  echo "make eps-open-sdk complete."
  ~/workspace/esp-open-sdk/xtensa-lx106-elf/bin/xtensa-lx106-elf-cc --version
fi


# should eventually get a message like this at the end. (note important path note!):
#
#   Xtensa toolchain is built, to use it:
#
#   export PATH=/home/pi/workspace/esp-open-sdk/xtensa-lx106-elf/bin:$PATH
#
#   Espressif ESP8266 SDK is installed, its libraries and headers are merged with the toolchain
#

# be sure to add the path as suggested

if [[ $PATH != */workspace/esp-open-sdk/xtensa-lx106-elf/bin* ]]; then
  export PATH=~/workspace/esp-open-sdk/xtensa-lx106-elf/bin:$PATH
fi


#*******************************************************************************************************
# next, fetch micropython source from github and build, as needed (skip if we are only writing firmware)
#*******************************************************************************************************
if [ "$1" == "FULL" ] || [ "$1" == "MAKE-ONLY" ] ||  [ "$1" == "MAKE-ONLY-ESP8266" ] || [ "$1" == "RUN-TESTS" ]; then
  cd ~/workspace

  if ! [[ -a ~/workspace/micropython ]]; then
    echo "git clone micropython"
    git clone --recursive https://github.com/micropython/micropython.git
  fi
  echo "*************************************************************************************************"
  echo "*************************************************************************************************"
  echo "*  Update latest micropython from git "
  echo "*************************************************************************************************"
  echo "*************************************************************************************************"
  cd ~/workspace/micropython/

  git submodule update --init

  git fetch origin
  git pull

  # the next git commmands are suggested on https://github.com/pfalcon/esp-open-sdk
  git submodule sync
  git submodule update
fi


#*******************************************************************************************************
# compile mpy-cross
# see https://github.com/micropython/micropython/tree/master/esp8266
#*******************************************************************************************************
cd ~/workspace/micropython/
make -C mpy-cross

#*******************************************************************************************************
# check if we are only running tests  (note we need to ensure we have the lasted MicroPython scripts!)
#*******************************************************************************************************
if [ "$1" == "RUN-TESTS" ]; then
  echo "*************************************************************************************************"
  echo "*************************************************************************************************"
  echo "*  Running MicroPython tests... "
  echo "*************************************************************************************************"
  echo "*************************************************************************************************"
  cd ~/workspace/micropython/tests/
  ./run-tests  --target esp8266 --device $MYDEVICE
  echo "Done!"
  exit 0
fi


#*******************************************************************************************************
# build the esp8266 MicroPython firmware
#*******************************************************************************************************
if [ "$1" == "FULL" ] || [ "$1" == "MAKE-ONLY" ] ||  [ "$1" == "MAKE-ONLY-ESP8266" ]; then
  echo "*************************************************************************************************"
  echo "*************************************************************************************************"
  echo "*  Build ESP8266"
  echo "*************************************************************************************************"
  echo "*************************************************************************************************"
  cd ~/workspace/micropython/esp8266

  make clean

  make axtls

  make
fi


#*******************************************************************************************************
# show the newly built firmware
#*******************************************************************************************************
echo "*************************************************************************************************"
echo "*************************************************************************************************"
echo "*  Newly built firmware in  ~/workspace/micropython/esp8266/build/"
echo "*************************************************************************************************"
echo "*************************************************************************************************"

if  ([ -e  ~/workspace/micropython/esp8266/build/firmware-combined.bin ]); then
  ls ~/workspace/micropython/esp8266/build/firmware* -al
else
  echo "ERROR: Fresh build file not found.  ~/workspace/micropython/esp8266/build/firmware-combined.bin"
  echo "Aborting..."
  exit 2
fi


if [ "$DEVICEFOUND" == "0" ]; then
  echo "Device not found, exiting."
  exit 2
fi

echo "Ready to send firmware-combined.bin to $MYDEVICE (press reset on ESP8266 now if desired)"
echo ""
read -n 1  -p "Press a key to continue (or Ctrl-C to abort)..."

#*******************************************************************************************************
# check to see if a device is connected and send the new firmware
#*******************************************************************************************************
echo "Looking for $MYDEVICE ..."
if [ -c "$MYDEVICE" ]; then
  echo "*************************************************************************************************"
  echo "*  Changing permissions on $MYDEVICE"
  echo "*************************************************************************************************"
  if [[ -a /home/pi/ ]]; then
    sudo chown pi:pi $MYDEVICE
  else
    echo "Changing permissions on $MYDEVICE ..."
    sudo chmod 777 $MYDEVICE
    THISUSER=$(whoami)
    echo "Adding $THISUSER to dialout group..."
    # sudo adduser $THISUSER dialout # this is not immediately effective
    sudo gpasswd -a $THISUSER dialout
    echo "Refreshing group membership without logging out..."
    # newgrp dialout # this starts a new shell
  fi
  #*******************************************************************************************************
  # erase the flash (a good idea before applying new firmware)
  #*******************************************************************************************************
  echo "*************************************************************************************************"
  echo "*  Erasing..."
  echo "*************************************************************************************************"
  execUntilSuccessful "~/workspace/esptool/esptool.py --port $MYDEVICE erase_flash"

  #*******************************************************************************************************
  # send newly compiled image to your ESP8266
  #*******************************************************************************************************
  echo "*************************************************************************************************"
  echo "*  Writing image..."
  echo "*************************************************************************************************"
  execUntilSuccessful "~/workspace/esptool/esptool.py --port $MYDEVICE --baud $MYBAUD write_flash --flash_size=32m 0 \
                                      ~/workspace/micropython/esp8266/build/firmware-combined.bin"
else
  echo "Device $MYDEVICE not found. You will need to manually upload firmware."
  echo "See MYDEVICE setting in this script."
  read -n 1  -p "Press a key to continue (or Ctrl-C to abort)..."
fi

#
# successful write should look like this:
#
#Connecting...
#Erasing flash...
#Took 1.55s to erase flash block
#Wrote 409600 bytes at 0x00000000 in 13.7 seconds (238.7 kbit/s)...
#
#Leaving...
#

#****************************************************************************************
# Note the default serial parameters for ESP8266 are:
# 115200 buad, 8 data bits, 1 stop bit, No Parity, No flow control

# uncomment to configure minicom, without connecting
# minicom -o -s

# ready to connect!
# reminder Ctrl-A Z X to exit minocom
#
# sudo apt-get install minicom  --assume-yes
# minicom --device /dev/ttyUSB0 115200

# if you see an error like: minicom: cannot open /dev/modem
# then change the device like this:
# minicom -D /dev/ttyUSB0
# (or be sure to specify --device /dev/ttyUSB0

# you probably want to reset the ESP8266 after fresh firmware
# connect first, and see the very first startup message!


#****************************************************************************************
# other fun stuf....
#****************************************************************************************

# Perhaps we'll consider playing with I2C on the RPi, such as the RTC1307
#
# uncomment to run raspi-config (needed to enable kernel support for I2C)
# sudo raspi-config

# uncomment to add pi as I2C user
# sudo adduser pi i2c

# uncomment to install the I2C tools
# sudo apt-get install i2c-tools

# uncommment to turn on support for the RTC 1307 Real time Clock
# echo ds1307 0x68 | sudo tee /sys/class/i2c-adapter/i2c-1/new_device

# uncomment to remove RTC1307
# echo 0x68 | sudo tee /sys/class/i2c-adapter/i2c-1/delete_device

# Note that the RTC1307 typically needs an LIR2302 (rechargable!) battery.
# Be careful with non-rechargables. If used, consider removing charing resistors.
#
# if your RPi has the correct time, uncomment to set RTC clock to RPi time
# sudo hwclock -w

# uncomment to read the time from the RTC clock
# sudo hwclock -r

# uncomment if you want to play with I2C stuff on the RPi python,
# sudo apt-get install python-dev
# sudo apt-get install python-smbus
#   or python 3:
# sudo apt-get install python3-smbus
# sudo apt-get install python3-dev


# uncomment if you have a file called myI2C.py, and want to send it to the ESP8266 via pyboard.py
# python pyboard.py --device /dev/ttyUSB0 myI2C.py

# if you want to quickly see if the ESP8266 is operational
cd ~/workspace
echo "If the firmware uploaded correctly, now would be a good time to press reset on your ESP8266."
echo "If hello world prints, then MicroPython is probably working!"
read -n 1  -p "Press a key to continue..."
echo "Attempting initial pyboard.py command...."

execUntilSuccessful "~/workspace/micropython/tools/pyboard.py --device $MYDEVICE -c 'print(\"hello world\")'"
echo ""
echo "Hello World test complete!"
echo
echo "For reference, here is some local python info:"
apt-cache policy python3 python

echo ""
echo "Here is the xtensa version info:"
~/workspace/esp-open-sdk/xtensa-lx106-elf/bin/xtensa-lx106-elf-cc --version

# uncomment if you don't want to use minicom but need to open a terminal session to ESP8266
# sudo screen /dev/ttyUSB0 115200
# reminder:
#
# Ctrl-A Ctrl-D to detach, then connect later with screen -r   (holds the serial port in use!)
# per deshipu: To exit screen, use "ctrl+a ctrl+k" or "ctrl+a ctrl+K" (the latter if you don't want a confirmation question).

echo ""
echo "For auto-completion, do not forget to install 'ct-ng.comp' into"
echo "your bash completion directory (usually /etc/bash_completion.d)"
echo ""

echo "To run tests:"
echo ""
echo "~/workspace/micropython/tests/run-tests  --target esp8266 --device $MYDEVICE"
echo ""
echo ""
echo "Done!"
exit 0
