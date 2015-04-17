# Tracebox-Android
Building Tracebox on Android.

This has been made/tested for Android Platform rev. >= 15.

In order to be used, the device must be rooted.

The script will produce an ARM v5 binary in bin/tracebox.

To install it:
1. Enable USB debugging on your phone
2. Plug your phone on your computer with your USB cable
3. Accept the connection on the phone
4. $ adb push bin/tracebox /data/location/on/the/phone

To use it (on the phone or through adb shell):
1. su
2. /path/to/tracebox
