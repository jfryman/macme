require_relative 'env.rb'


module MacMe
  module Device
    include MacMe::Env

    def device_presence_mqtt_topic(device)
      [
        mqtt_topic,
        zone_name,
        'presence'
      ].join('/')
    end

    def device_mqtt_topic(device)
      [
        mqtt_topic,
        zone_name,
        device[:mac]
      ].join('/')
    end

    def devices_mqtt_topic
      [
        mqtt_topic,
        zone_name,
        '#'
      ].join('/')
    end

    def device_has_owner?(device={})
      device.key?(:uid)
    end

  end  # Device
end  # MacMe
