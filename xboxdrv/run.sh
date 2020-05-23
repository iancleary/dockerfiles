#!/bin/bash

USB_DEVICE_GREP=$(lsusb | grep Xbox)
echo "${USB_DEVICE_GREP}"

USB_DEVICE_NUMBER="${USB_DEVICE_GREP:15:3}"
echo "${USB_DEVICE_NUMBER}"

# load the Xbox 360 USB Device
docker run -it --rm \
    --device=/dev/bus/usb/001/${USB_DEVICE_NUMBER}/ \
    -v /dev/input/uinput:/dev/input/uinput \
    -v /dev/uinput:/dev/uinput \
    -v /dev/misc/uinput:/dev/misc/uinput \
    iancleary/xboxdrv
