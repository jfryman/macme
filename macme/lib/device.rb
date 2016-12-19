require 'rubygems'

module MacMe
  module Device
    def mqtt_topic
      @mqtt_topic ||= ENV['MACME_MQTT_TOPIC'] || 'macme'
    end

    def zone_name
      @zone_name ||= ENV['MACME_ZONE_NAME'] || 'hq'
    end

    def device_mqtt_topic(device)
      [
        mqtt_topic,
        zone_name,
        device["mac"]
      ].join('/')
    end

    def devices_mqtt_topic
      [
        mqtt_topic,
        zone_name,
        '#'
      ].join('/')
    end
  end
end
