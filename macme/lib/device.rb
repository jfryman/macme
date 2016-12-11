require 'rubygems'

module MacMe::Device
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

  def device_has_owner?(device)
    device[:uid] ? true : false
  end

  def update_device_last_seen_timestamp(device)
    updated_timestamps = {
      :last_seen => Time.now,
      :last_seen_epoch => Time.now.to_i
    }

    device.merge(updated_timestamps)
  end
end
