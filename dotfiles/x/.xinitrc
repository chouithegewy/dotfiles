#!/bin/sh

if command -v xrdb >/dev/null 2>&1 && [ -r "$HOME/.Xresources" ]; then
  xrdb -merge "$HOME/.Xresources"
fi

xset r rate 200 50
xsetroot -solid #000000
exec i3
