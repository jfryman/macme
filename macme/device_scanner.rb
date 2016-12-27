require 'arp_scan'
require_relative 'lib/macme.rb'
require_relative 'lib/device.rb'
require_relative 'lib/mqtt.rb'
require_relative 'lib/env.rb'


module MacMe
  class DeviceScanner
    include MacMe::MQTT
    include MacMe::Device
    include MacMe::Env

    def initialize
      MacMe::Logger.log.debug "Beginning ARP poll of #{scan_subnet}"

      self.poll
    end

    def arp_scan_for_devices
      ARPScan(scan_subnet).hosts
    end

    def map_device_info(device)
      {
        :mac => device.mac,
        :ip => device.ip_addr,
        :last_seen => Time.now,
        :last_seen_epoch => Time.now.to_i
      }
    end

    def publish_device(device)
      topic = device_mqtt_topic device
      MacMe::Logger.log.debug "[MacMe::DeviceScanner] #{topic} / #{device}"

      send_message(topic, device)
    end

    def poll
      while true do
        arp_scan_for_devices.each do |scanned_device|
          device = map_device_info scanned_device

          publish_device device

        end

        MacMe::Logger.log.debug "Pausing runloop for #{scan_delay} seconds"
        sleep scan_delay
      end
    end

  end  # DeviceScanner
end  # MacMe

MacMe::DeviceScanner.new
