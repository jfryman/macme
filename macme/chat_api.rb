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
      @device_stale_time ||= if ENV['MQTT_DEVICE_STALE_TIMEOUT']
                               ENV['MQTT_DEVICE_STALE_TIMEOUT'].to_i
                             else
                               300
                             end
    end

    def get_uid_objectclass(uid)
      result_attributes = ['objectClass']
      uid_filter = Net::LDAP::Filter.eq('uid', uid)

      result = ldap_client.search(:filter => uid_filter,
                                  :attributes => result_attributes)

      result.first.objectclass
    end

    def uid_has_device_schema?(uid)
      get_uid_objectclass(uid).include? 'ieee802Device'
    end

    def add_device_schema(uid)
      updated_objectclass = get_uid_objectclass(uid) + ['ieee802Device']
      user_dn = ""

      ldap_client.replace_attribute user_dn, :objectClass, updated_objectclass
    end


    def get_user_devices(uid)
      result_attributes = ['macAddress']
      uid_filter = Net::LDAP::Filter.eq('uid', uid)
      result = ldap_client.search(:filter => uid_filter,
                                  :attributes => result_attributes)

      begin
        result.first.macaddress
      rescue
        nil
      end
    end

    def get_uid_from_irc_nickname(nickname)
      result_attributes = ['displayName']
      irc_nickname_filter = Net::LDAP::Filter.eq('displayName', nickname)
      @ldap_client.search(:filter => irc_nickname_filter,
                        :attributes => result_attributes) do |result|
        return result.uid.first
      end
    end

    def add_device_to_user(uid, device)
      add_device_schema uid unless uid_has_device_schema?

      "Successfully added device #{device}"
    end

    def remove_device_from_user(uid, device)
      "Successfully removed device #{device}"
    end

    def filter_old_devices(devices)
      devices.filter { |device| device["last_seen_epoch"] >= Time.now.to_i + device_stale_time }
    end

    def extract_users(devices)
      devices.collect { |device| device["uid"] }
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

    def extract_uid_from_message(message)
      message[/link\s+(\w+)/,1]
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
      when /remove/
        cmd_remove(topic, message)
      when /link/
        cmd_link(topic, message)
      when /(list|view)/
        cmd_get_user_devices(topic, message)
      when /me$/
        cmd_get_office_peeps(topic, message)
      else
        cmd_help(topic, message)
      end
    end

    def user_is_not_linked?(topic, message)
      result_attributes = ['displayName']
      username = extract_username_from_topic topic
      displayname_filter = Net::LDAP::Filter.eq('displayName', username)

      result = @ldap_client.search(:filter => displayname_filter,
                                  :attributes => result_attributes)

      begin
        result.first.displayname
        false
      rescue
        true
      end
    end

    def cmd_register(topic, message)
      if user_is_not_linked?(topic, message)
        mqtt_respond(topic, "#{username}: Your user has not been registered")
        cmd_help
      else
        mac_address = extract_mac_address_from_message message
        username = extract_username_from_topic topic

        if mac_address
          response = add_device_to_user(username, mac_address)
          mqtt_respond(topic, "#{username}: #{response}")
        else
          mqtt_respond(topic, "#{username}: That does not appear to be a valid MAC")
        end
      end
    end

    def cmd_remove(topic, message)
      if user_is_not_linked?(topic, message)
        mqtt_respond(topic, "#{username}: Your user has not been registered")
        cmd_help
      else
        mac_address = extract_mac_address_from_message message
        username = extract_username_from_topic topic

        if mac_address
          response = remove_device_from_user(username, mac_address)
          mqtt_respond(topic, "#{username}: #{response}")
        else
          mqtt_respond(topic, "#{username}: That does not appear to be a valid MAC")
        end
      end
    end

    def cmd_link(topic, message)
      ldap_uid = extract_uid_from_message message
      username = extract_username_from_topic topic
      user_dn = "uid=#{ldap_uid},ou=People,dc=websages,dc=com"

      ldap_client.replace_attribute user_dn, :displayName, username
      mqtt_respond(topic, "#{username}: Added nick #{username} to #{user_dn}")
    end

    def cmd_get_user_devices(topic, message)
      if user_is_not_linked?(topic, message)
        mqtt_respond(topic, "#{username}: Your user has not been registered")
        cmd_help
      else
        username = extract_username_from_topic
        uid = get_uid_from_irc_nickname username
        devices = get_user_devices uid

        if devices
          mqtt_respond(topic, "#{username}: Devices registered - #{devices.join(',')}")
        else
          mqtt_respond(topic, "#{username}: No devices currently registered")
        end
      end
    end

    def cmd_get_office_peeps(topic, message)
      mqtt_respond(topic, "cmd_get_office_peeps")
    end

    def cmd_help(topic, message)
      response = %Q{
      !#{zone_name} me - View who's all in your zone (#{zone_name})
      !macme link <ldapUid> - Link LDAP account with nickname
      !macme register <macAddress> - Register a device
      !macme remove <macAddress> - Remove device
      !macme list - View all your registered devices}

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

    def poll
      MacMe::Logger.log.debug "MQTT: Subscribing to #{mqtt_chat_poll_topic}"

      mqtt_client.get(mqtt_chat_poll_topic) do |topic, message|
        process_command(topic, message) if is_macme_command? message
      end
    end
  end
end

MacMe::MQTTChatApi.new
