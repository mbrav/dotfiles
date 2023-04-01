#!/bin/bash

echo $(wakatime --today | awk -F 'Coding' '{print $1}')
