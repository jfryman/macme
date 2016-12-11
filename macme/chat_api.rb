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

  def random_presence_response
    [
      "The following folks are at #{zone_name}",
      "These peeps are around",
      "These fine people are at #{zone_name}"
    ].sample
  end

  def random_no_presence_response
    [
      "Nobody is at #{zone_name}. Be the first!",
      "Looks like nobody is around"
    ].sample
  end

  def mqtt_chat_poll_topic
    @mqtt_chat_poll_topic ||= ENV['MQTT_CHAT_TOPIC'] || 'irc/#'
  end

  def device_stale_time
    @device_stale_time ||= ENV['MQTT_DEVICE_STALE_TIMEOUT'].to_i || 300
  end

  def lookup_user_devices(uid)
    result_attributes = ['macAddress']
    uid_filter = Net::LDAP::Filter.eq('uid', uid)
    ldap_client.search(:filter => uid_filter,
                       :attributes => result_attributes)
  end

  def lookup_uid_from_irc_nickname(nickname)
    result_attributes = ['uid']
    irc_nickname_filter = Net::LDAP::Filter.eq('irc', nickname)
    ldap_client.search(:filter => irc_nickname_filter,
                       :attributes => result_attributes) do |result|
      return result.uid.first
    end
  end

  def add_device_to_user(uid, device)
    true
  end

  def remove_device_from_user(uid, device)
    true
  end

  def filter_old_devices(devices)
    devices.filter do |device|
      device[:last_seen_epoch] >= Time.now.to_i + device_stale_time
    end
  end

  def extract_users(devices)
    devices.collect { |device| device[:uid] }
  end

  def extract_mac_address_from_message(message)
    message[/(([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2}))/,1]
  end

  def extract_username_from_topic(topic)
    topic[/nick\/(\w+)\/said/,1]
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
    uid =
      lookup_uid_from_irc_nickname(
        extract_username_from_topic(topic))
    mac_address = extract_mac_address_from_message message

    add_device_to_user(uid, mac_address)
  end

  def cmd_deregister_device(topic, message)
    uid =
      lookup_uid_from_irc_nickname(
        extract_username_from_topic(topic))
    mac_address = extract_mac_address_from_message message

    remove_device_from_user(uid, mac_address)
  end

  def cmd_get_user_devices(topic, message)
    uid =
      lookup_uid_from_irc_nickname(
      extract_username_from_topic(topic))

    respond_devices(
      lookup_user_devices(uid))
  end

  def cmd_get_office_peeps
    respond_users(
      extract_users(
        filter_old_devices(
          mqtt_client.get(devices_topic))))
  end

  def cmd_help
    %Q{
    !#{zone_name} me               - View who's all in your zone (#{zone_name})
    !macme register <macAddress>   - Register your device to your user
    !macme deregister <macAddress> - Deregister device from your user
    !macme list                    - View all devices registered to you
    }
  end

  def respond_users(users)
    if users
      puts "#{random_presence_response}: #{users.join(',')}"
    else
      puts random_no_presence_response
    end
  end

  def respond_devices(devices)
    puts "The following devices belong to you: #{devices.join(',')}" if devices
  end

  def poll
    mqtt_client.subscribe(mqtt_chat_poll_topic)

    mqtt_client.get do |topic, message|
      process_command(topic, message) if is_macme_command? message
    end
  end
end

MacMe::MQTTChatApi.new
