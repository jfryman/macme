require_relative 'lib/macme.rb'
require_relative 'lib/mqtt.rb'
require_relative 'lib/device.rb'


module MacMe
  class PresenceManager
    include MacMe::MQTT
    include MacMe::Device

    def initialize
      MacMe::Logger.log.debug "Starting MacMe::PresenceManager"

      @state ||= Array.new

      mqtt_client.subscribe(devices_mqtt_topic)
      self.poll
    end

    def track_device(device)
      purge_device device

      @state << device
    end

    def purge_device(device)
      purged_state = @state.each_with_object([]) { |known_device, l|
        l.push(known_device) if device[:mac] != known_device[:mac]
      }

      @state = purged_state
    end

    def purge_aged_devices
      purged_state = @state.each_with_object([]) { |device, l|
        l.push(device) if device[:last_seen_epoch] >= Time.now.to_i + device_stale_time
      }

      @state = purged_state
    end

    ## Commands
    def cmd_get_state(topic, message)
      if message.key?[:callback_module]
        payload = {
          :command   => message[:command],
          :options   => message[:options],
          :response  => {:state => @state},
          :recipient => message[:callback_module],
        }

        send_message(callback_topic, payload)
      end
    end

    ## MacMe::MQTT Implementation
    def module_name(message)
      @module_name ||= "MacMe::PresenceManager"
    end

    def process_command(topic, message)
      case message[:command]
      when /get_state/
        cmd_get_state(topic, message)
      end
    end

    def process_message(topic, message)
      if device_has_owner? message
        MacMe::Logger.log.debug("Tracking device #{message} in presence state")

        purge_aged_devices
        track_device message
      end
    end

  end  # PresenceManager
end  # MacMe

MacMe::PresenceManager.new
