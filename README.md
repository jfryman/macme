# MacMe

This is a small set of helper applications designed to help us keep tabs of folks in the office. Written in Ruby, this app is broken into very small bits:

* DeviceScanner: Scans devices on a subnet with `arp-scan`, and publishes to MQTT
* LDAPScanner: Scans for devices on MQTT, and updates if an owner is defined in LDAP
* LDAPRegister: Small API allowing for users to register a device, saves to LDAP

## Flow

* Scanner detects devices, drops on MQTT
* DeviceOwnerUpdater detects device on line, checks for owner, and updates / drops on MQTT
* PresenceUpdater detects OwnedDevice, updates presence state
* ChatAPI provides MQTT chat based interface to all the things
