#!/usr/bin/env python
# -*- coding: utf-8 -*-
import dbus
import logging
import subprocess
import math

from gi.repository import GLib
from dbus.mainloop.glib import DBusGMainLoop

MIN_LIGHT=.1
MAX_LIGHT=1.00
BOOST_LIGHT=.3
KB_BACKLIGHT_FULL = 400
KB_BACKLIGHT_OFF = 1000

DBusGMainLoop(set_as_default=True)
loop = GLib.MainLoop()
bus = dbus.SystemBus()


def get_kb_brightness(amb):
    if amb > KB_BACKLIGHT_OFF:
        return 0
    elif amb > KB_BACKLIGHT_FULL:
        return 2
    return 1

def set_kb_brightness(amb):
    kb_brightness = get_kb_brightness(amb)
    kbd_backlight_proxy = bus.get_object('org.freedesktop.UPower', '/org/freedesktop/UPower/KbdBacklight')
    kbd_backlight = dbus.Interface(kbd_backlight_proxy, 'org.freedesktop.UPower.KbdBacklight')
    kbd_backlight.SetBrightness(kb_brightness)


def get_display_brightness(amb):
    return max(MIN_LIGHT, min(MAX_LIGHT, BOOST_LIGHT + math.log(amb) / 10))


def set_display_brightness(amb):
    brightness = get_display_brightness(amb)
    subprocess.call(['xrandr', '--output', 'eDP-1', '--brightness', str(brightness)])


def sensor_proxy_signal_handler(source, changedProperties, invalidatedProperties, **kwargs):
    print('Got an update!: %s', source)
    if source == u'net.hadess.SensorProxy' and 'LightLevel' in changedProperties:
        light_level = changedProperties['LightLevel']
        logging.error('LightLevel changed: {}'.format(light_level))
        set_kb_brightness(light_level)
        set_display_brightness(light_level)


proxy = bus.get_object('net.hadess.SensorProxy', '/net/hadess/SensorProxy')
iface = dbus.Interface(proxy, 'net.hadess.SensorProxy')
iface.ClaimLight()
props = dbus.Interface(proxy, 'org.freedesktop.DBus.Properties')
props.connect_to_signal('PropertiesChanged', sensor_proxy_signal_handler, sender_keyword='sender')
loop.run()
