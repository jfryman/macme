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

    def get_uid_from_irc_nickname(nickname)
      result_attributes = ['dn']
      irc_nickname_filter = Net::LDAP::Filter.eq('displayName', nickname)
      result = ldap_client.search(:filter => irc_nickname_filter,
                                  :attributes => result_attributes)

      extract_uid_from_dn result.first.dn
    end

    def get_user_devices(uid)
      result_attributes = ['macAddress']
      uid_filter = Net::LDAP::Filter.eq('uid', uid)
      result = ldap_client.search(:filter => uid_filter,
                                  :attributes => result_attributes)

      begin
        result.first.macaddress
      rescue
        Array.new
      end
    end

    def uid_has_device_schema?(uid)
      get_uid_objectclass(uid).include? 'ieee802Device'
    end

    def add_device_schema(uid)
      updated_objectclass = get_uid_objectclass(uid) + ['ieee802Device']
      dn = user_dn uid

      ldap_client.replace_attribute dn, :objectClass, updated_objectclass
    end

    def add_device_to_user(nickname, device)
      uid = get_uid_from_irc_nickname nickname
      dn = user_dn uid
      updated_devices = get_user_devices(uid) + [device]

      add_device_schema uid unless uid_has_device_schema? uid
      ldap_client.replace_attribute dn, :macAddress, updated_devices
    end

    def remove_device_from_user(nickname, device)
      uid = get_uid_from_irc_nickname nickname
      dn = user_dn uid
      updated_devices = get_user_devices(uid) - [device]

      ldap_client.replace_attribute dn, :macAddress, updated_devices
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

    def extract_uid_from_dn(dn)
      dn[/^uid=(.*),ou=/,1]
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

      result = ldap_client.search(:filter => displayname_filter,
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
        mqtt_respond(topic, "#{username}: Your user has not been linked")
        cmd_help
      else
        mac_address = extract_mac_address_from_message message
        username = extract_username_from_topic topic

        if mac_address
          add_device_to_user(username, mac_address)
          mqtt_respond(topic, "#{username}: Registered MAC #{mac_address} to your account")
        else
          mqtt_respond(topic, "#{username}: That does not appear to be a valid MAC")
        end
      end
    end

    def cmd_remove(topic, message)
      if user_is_not_linked?(topic, message)
        mqtt_respond(topic, "#{username}: Your user has not been linked")
        cmd_help(topic, message)
      else
        mac_address = extract_mac_address_from_message message
        username = extract_username_from_topic topic

        if mac_address
          remove_device_from_user(username, mac_address)
          mqtt_respond(topic, "#{username}: Removed MAC #{mac_address} from your account")
        else
          mqtt_respond(topic, "#{username}: That does not appear to be a valid MAC")
        end
      end
    end

    def cmd_link(topic, message)
      ldap_uid = extract_uid_from_message message
      username = extract_username_from_topic topic

      if ldap_uid
        dn = user_dn ldap_uid
        # ldap_client.replace_attribute dn, :displayName, username
        mqtt_respond(topic, "#{username}: Added nick #{username} to #{dn}")
      else
        mqtt_respond(topic, "#{username}: Missing an IRC username to link")
        cmd_help(topic, message)
      end
    end

    def cmd_get_user_devices(topic, message)
      if user_is_not_linked?(topic, message)
        mqtt_respond(topic, "#{username}: Your user has not been linked")
        cmd_help(topic, message)
      else
        username = extract_username_from_topic topic
        uid = get_uid_from_irc_nickname username
        devices = get_user_devices uid

        if devices.size > 0
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
