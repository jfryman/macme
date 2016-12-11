# MacMe

This is a small set of helper applications designed to help us keep tabs of folks in the office. Written in Ruby, this app is broken into very small bits:

* DeviceScanner: Scans devices on a subnet with `arp-scan`, and publishes to MQTT
* LDAPScanner: Scans for devices on MQTT, and updates if an owner is defined in LDAP
* LDAPRegister: Small API allowing for users to register a device, saves to LDAP

## Environment Variables

* MACME_SUBNET (Default: 10.255.0.0/24)
* MACME_SCAN_DELAY (Default: 300)
* MACME_MQTT_TOPIC (Default: macme)
* MACME_OFFICE_NAME (Default: hq)
* MQTT_HOST
* MQTT_USERNAME
* MQTT_PASSWORD
* MQTT_PORT
* LDAP_HOST
* LDAP_USERNAME
* LDAP_PASSWORD

### To be implemented
* MQTT_CA_CERT
* MQTT_CERT
* MQTT_CERT_KEY

