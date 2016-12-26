require_relative 'lib/macme.rb'
require_relative 'lib/ldap.rb'
require_relative 'lib/mqtt.rb'
require_relative 'lib/device.rb'


module MacMe
  class DeviceOwnerUpdater
    include MacMe::MQTT
    include MacMe::LDAP
    include MacMe::Device

    def initialize
      MacMe::Logger.log.debug "Starting MacMe::DeviceOwnerUpdater"
      mqtt_client.subscribe(devices_mqtt_topic)

      self.poll
    end

    def lookup_device_owner(device)
      result_attributes  = ['uid', 'gecos', 'displayName']
      mac_address_filter = Net::LDAP::Filter.eq('macAddress', device[:mac])

      result = ldap_client.search(:filter     => mac_address_filter,
                                  :attributes => result_attributes)

      if result.first.nil?
        MacMe::Logger.log.debug("No registered owner for #{device}")

        device_lookup = {
          :device_lookup => true
        }
      else
        device_lookup = {
          :uid      => result.first.uid.first,
          :gecos    => result.first.gecos.first,
          :nickname => result.first.displayname.first,
          :device_lookup => true
        }
      end

      device.merge(device_lookup)
    end

    def unprocessed_message?(message)
      ! message.key? :device_lookup
    end

    # MacMe::MQTT Implementation
    def process_message(topic, message)
      if ! device_has_owner? message and unprocessed_message? message
        MacMe::Logger.log.debug("Looking up owner for #{message}")
        device = lookup_device_owner message

        send_message(topic, device)
      end
    end

  end  # DeviceOwnerUpdater
end  # MacMe

MacMe::DeviceOwnerUpdater.new
