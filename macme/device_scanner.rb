#!/usr/bin/env ruby

require 'rubygems'
require 'arp_scan'
require 'json'
require_relative 'lib/mqtt.rb'


class DeviceScanner
  extend MacMe::MQTT

  attr_accessor :devices

  def initialize
    @devices ||= []

    @scan_subnet = ENV['MACME_SUBNET']          || '10.255.0.0/24'
    @scan_delay  = ENV['MACME_SCAN_DELAY'].to_i || 300

    self.poll
  end

  def arp_scan_for_devices
    ARPScan(@scan_subnet).hosts
  end

  def map_device_info(device)
    {
      :mac => host.mac,
      :ip => host.ip_addr,
      :last_seen => Time.now,
      :last_seen_epoch => Time.now.to_i
    }
  end

  def update_device_to_mqtt(device)
    publish_device_to_mqtt(
      update_device_last_seen_timestamp(
        get_device_from_mqtt(device)))
  end

  def get_device_from_mqtt(device)
    mqtt_client.get device_mqtt_topic device
  end

  def publish_device_to_mqtt(device)
    device_topic = device_mqtt_topic device
    mqtt_client.publish(device_topic, device.to_json, true)

    update_device_publish_cache(device)
  end

  def update_device_publish_cache(device)
    devices << device[:mac] unless devices.include? device[:mac]
  end

  def device_previously_published_on_mqtt?(device)
    devices.include? device[:mac] ? true : false
  end

  def poll
    while true do
      arp_scan_for_devices.each do |device|
        if device_previously_published_on_mqtt? device
          update_device_to_mqtt(
            map_device_info(device))
        else
          publish_device_to_mqtt(
            map_device_info(device))
        end
      end

      sleep @scan_delay
    end
  end
end

DeviceScanner.new
