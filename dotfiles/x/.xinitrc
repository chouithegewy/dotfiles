xrdb -load $HOME/.Xresources
xset r rate 200 50 &
xsetroot -solid #000000 &
# Touchpad settings
syndaemon -i 1 -K -d &
xinput set-prop 12 "Synaptics Palm Detection" 1 &
exec i3

