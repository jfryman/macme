#!/usr/bin/env ruby

require_relative 'lib/macme.rb'
require_relative 'lib/mqtt.rb'
require_relative 'lib/ldap.rb'
require_relative 'lib/device.rb'

module MacMe
  class MQTTChatApi
    include MacMe::MQTT
    include MacMe::LDAP
    include MacMe::Device

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

    def get_user_devices(uid)
      result_attributes = ['macAddress']
      uid_filter = Net::LDAP::Filter.eq('uid', uid)
      ldap_client.search(:filter => uid_filter,
                        :attributes => result_attributes)
    end

    def get_uid_from_irc_nickname(nickname)
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
      devices.filter { |device| device[:last_seen_epoch] >= Time.now.to_i + device_stale_time }
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

    def extract_room_from_topic(topic)
      topic[/room\/(\w+)\//,1]
    end

    def is_macme_command?(message)
      case message
      when /[\W]device\s+(.*)/ then true
      when /[\W]macme\s+(.*)/ then true
      when /[\W]#{zone_name}/ then true
      else false
      end
    end

    def process_command(topic, message)
      MacMe::Logger.log.debug "Processing message: [#{topic}] #{message}"

      case message
      when /register/
        cmd_register(topic, message)
      when /deregister/
        cmd_deregister(topic, message)
      when /(list|view)/
        cmd_get_user_devices(topic, message)
      when /me/
        cmd_get_office_peeps(topic, message)
      else
        cmd_help(topic, message)
      end
    end

    def cmd_register(topic, message)
      mqtt_respond(topic, "cmd_register")
    end

    def cmd_deregister(topic, message)
      mqtt_respond(topic, "cmd_deregister")
    end

    def cmd_get_user_devices(topic, message)
      mqtt_respond(topic, "cmd_get_user_devices")
    end

    def cmd_get_office_peeps(topic, message)
      mqtt_respond(topic, "cmd_get_office_peeps")
    end

    def cmd_help(topic, message)
      response = %Q{
      !#{zone_name} me               - View who's all in your zone (#{zone_name})
      !macme register <macAddress>   - Register your device to your user
      !macme deregister <macAddress> - Deregister device from your user
      !macme list                    - View all devices registered to you
      }

      mqtt_respond(topic, response)
    end

    def mqtt_respond(topic, message)
      command_topic = [
        "hubot",
        "respond",
        "room",
        extract_room_from_topic(topic)
      ].join('/')

      mqtt_client.publish(command_topic, message)
    end

    # def cmd_register_device(topic, message)
    #   uid =
    #     get_uid_from_irc_nickname(
    #       extract_username_from_topic(topic))
    #   mac_address = extract_mac_address_from_message message

    #   add_device_to_user(uid, mac_address)
    # end

    # def cmd_deregister_device(topic, message)
    #   uid =
    #     get_uid_from_irc_nickname(
    #       extract_username_from_topic(topic))
    #   mac_address = extract_mac_address_from_message message

    #   remove_device_from_user(uid, mac_address)
    # end

    # def cmd_get_user_devices(topic, message)
    #   uid =
    #     get_uid_from_irc_nickname(
    #     extract_username_from_topic(topic))

    #   respond_devices(
    #     get_user_devices(uid))
    # end

    # def cmd_get_office_peeps
    #   respond_users(
    #     extract_users(
    #       filter_old_devices(
    #         mqtt_client.get(devices_topic))))
    # end

    def poll
      MacMe::Logger.log.debug "MQTT: Subscribing to #{mqtt_chat_poll_topic}"

      mqtt_client.get(mqtt_chat_poll_topic) do |topic, message|
        process_command(topic, message) if is_macme_command? message
      end
    end
  end
end

MacMe::MQTTChatApi.new
