#!/usr/bin/env bash

# Init wallpaper
swww init &
swww img ~/tiger.jpg

# Net applet
# pkgs.networkmangerapplet
nm-applet --indicator &

# Init WayBar
waybar &

# Notification deamon
dunst
