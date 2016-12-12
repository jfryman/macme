#!/usr/bin/env ruby

require 'rubygems'
require 'json'
require_relative 'lib/ldap.rb'
require_relative 'lib/mqtt.rb'
require_relative 'lib/device.rb'
require_relative 'lib/logger.rb'

module MacMe
  class DeviceOwnerUpdater
    include MacMe::MQTT
    include MacMe::LDAP
    include MacMe::Device

    def initialize
      MacMe::Logger.log.debug "Beginning DeviceUpdater Poll"
      self.poll
    end

    def lookup_and_add_owner_to_device(device)
      result_attributes = ['uid', 'gecos']
      mac_address_filter = Net::LDAP::Filter.eq('macAddress', device[:mac])

      ldap_client.search(:filter => mac_address_filter,
                         :attributes => result_attributes) do |result|
        device_owner = {
          :uid => result.uid.first,
          :gecos => result.gecos.first
        }

        publish_device_to_mqtt(device.merge(device_owner))
      end
    end

    def publish_device_to_mqtt(device)
      device_topic = device_mqtt_topic device
      mqtt_client.publish(device_topic, device.to_json, true)
    end

    def poll
      mqtt_client.get(devices_mqtt_topic) do |topic, device_json|
        device = JSON.parse device_json

        lookup_and_add_owner_to_device device unless device_has_owner? device
      end
    end
  end
end

MacMe::DeviceOwnerUpdater.new
