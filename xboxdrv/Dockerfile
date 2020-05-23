
# DESCRIPTION:	  Connect an Xbox 360 controller
# AUTHOR:		  Ian Cleary <iancleary@pm.me>
# COMMENTS:
#	This file describes how to build xboxdrv
#	in a container with all dependencies installed.
#	Tested on Debian Jessie.
# USAGE:
#	# Download atom Dockerfile
#	wget https://raw.githubusercontent.com/iancleary/dockerfiles/master/xboxdrv/Dockerfile
#
#	# Build atom image
#	docker build -t xboxdrv .
#
#	docker run -v /tmp/.X11-unix:/tmp/.X11-unix \
#		-e DISPLAY=unix$DISPLAY atom
#

# Base docker image
FROM ubuntu:bionic


# Tell debconf to run in non-interactive mode
ENV DEBIAN_FRONTEND noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y \
    kmod \
    xboxdrv

# Unload the default driver
# (part of the kmod package)
# RUN rmmod xpad

# Check path to xboxdrv
RUN which xboxdrv

# Autorun xboxdrv
# ENTRYPOINT [ "rmmod", "xpad", "&&", "xboxdrv", "--silent" ]

RUN rmmod xpad || true
ENTRYPOINT [ "xboxdrv", "--silent", "--detach-kernel-driver", "-v" ]

#ENTRYPOINT [ "xboxdrv", "--silent", "--detach-kernel-driver", "-v", "--no-uinput"]
