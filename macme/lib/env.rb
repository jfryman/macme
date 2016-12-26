module MacMe
  module Env
    def mqtt_topic
      ENV['MACME_MQTT_TOPIC'] || 'macme'
    end

    def zone_name
      ENV['MACME_ZONE_NAME'] || 'hq'
    end

    def scan_delay
      ENV['MACME_SCAN_DELAY'] ? ENV['MACME_SCAN_DELAY'].to_i : 300
    end

    def scan_subnet
      ENV['MACME_SUBNET'] || '10.255.0.0/24'
    end

    def device_stale_time
      ENV['MQTT_DEVICE_STALE_TIMEOUT'] ?
        ENV['MQTT_DEVICE_STALE_TIMEOUT'].to_i : 600
    end

    def mqtt_chat_poll_topic
      ENV['MQTT_CHAT_TOPIC'] || 'irc/#'
    end

  end  # Env
end  # MacMe
