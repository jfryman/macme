#!/usr/bin/env ruby

require_relative 'lib/macme.rb'
require_relative 'lib/device.rb'
require_relative 'lib/mqtt.rb'
require 'arp_scan'

module MacMe
  class DeviceScanner
    include MacMe::MQTT
    include MacMe::Device

    def initialize
      @scan_subnet = ENV['MACME_SUBNET'] || '10.255.0.0/24'

      MacMe::Logger.log.debug "Beginning ARP poll of #{@scan_subnet}"
      self.poll
    end

    def scan_delay
      if ENV['MACME_SCAN_DELAY']
        ENV['MACME_SCAN_DELAY'].to_i
      else
        300
      end
    end

    def arp_scan_for_devices
      ARPScan(@scan_subnet).hosts
    end

    def map_device_info(device)
      {
        "mac" => device.mac,
        "ip" => device.ip_addr,
        "last_seen" => Time.now,
        "last_seen_epoch" => Time.now.to_i
      }
    end

    def update_device_last_seen_timestamp(device)
      updated_timestamps = {
        "last_seen" => Time.now,
        "last_seen_epoch" => Time.now.to_i
      }

      device.merge(updated_timestamps)
    end

    def update_device_to_mqtt(device)
      publish_device_to_mqtt(
        update_device_last_seen_timestamp(
          get_device_from_mqtt(device)))
    end

    def get_device_from_mqtt(device)
      message = mqtt_client.get device_mqtt_topic device

      JSON.parse message[1]
    end

    def publish_device_to_mqtt(device)
      topic = device_mqtt_topic device
      payload = device.to_json

      MacMe::Logger.log.debug "[publish_device_to_mqtt] #{topic} / #{payload}"
      mqtt_client.publish(topic, payload, true)
    end

    def device_previously_published_on_mqtt?(device)
      topic = device_mqtt_topic device
      mqtt_client.subscribe(topic)

      published = !mqtt_client.queue_empty?

      mqtt_client.unsubscribe(topic)

      published
    end

    def poll
      while true do
        arp_scan_for_devices.each do |scanned_device|
          device = map_device_info scanned_device

          if device_previously_published_on_mqtt? device
            update_device_to_mqtt device
          else
            publish_device_to_mqtt device
          end
        end

        MacMe::Logger.log.debug "Pausing runloop for #{scan_delay} seconds"
        sleep scan_delay
      end
    end
  end
end

MacMe::DeviceScanner.new
