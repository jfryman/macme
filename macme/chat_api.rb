#!/usr/bin/env ruby
require 'rubygems'
require_relative 'lib/mqtt.rb'
require_relative 'lib/ldap.rb'
require_relative 'lib/device.rb'


class MacMe::MQTTChatApi
  extend MacMe::MQTT
  extend MacMe::LDAP
  extend MacMe::Device

  def initialize
    self.poll
  end

  def mqtt_chat_poll_topic
    @mqtt_chat_poll_topic ||= ENV['MQTT_CHAT_TOPIC'] || 'irc/#'
  end

  def is_macme_command?(message)
    case message
    when /[\W]device\s+(.*)/
      true
    when /[\W]macme\s+(.*)/
      true
    when /[\W]#{zone_name} me$/
      true
    else
      false
    end
  end

  def process_command(topic, message)
    case message
    when /register/
      cmd_register(topic, message)
    when /deregister/
      cmd_deregister(topic, message)
    when /(list|view)/
      cmd_get_user_devices(topic, message)
    when /me/
      cmd_get_office_peeps
    else
      cmd_help
    end
  end

  def cmd_register_device(topic, message)
    true
  end

  def cmd_deregister_device(topic, message)
    true
  end

  def cmd_get_user_devices(topic, message)
    true
  end

  def cmd_get_office_peeps
    true
  end

  def cmd_help
    %Q{
    !#{zone_name} me               - View who's all in your zone (#{zone_name})
    !macme register <macAddress>   - Register your device to your user
    !macme deregister <macAddress> - Deregister device from your user
    !macme list                    - View all devices registered to you
    }
  end

  def poll
    mqtt_client.subscribe(mqtt_chat_poll_topic)

    mqtt_client.get do |topic, message|
      process_command(topic, message) if is_macme_command? message
    end
  end
end

MacMe::MQTTChatApi.new
