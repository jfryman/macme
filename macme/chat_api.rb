require_relative 'lib/macme.rb'
require_relative 'lib/mqtt.rb'
require_relative 'lib/ldap.rb'
require_relative 'lib/device.rb'
require_relative 'lib/env.rb'


module MacMe
  class ChatApi
    include MacMe::MQTT
    include MacMe::LDAP
    include MacMe::Device
    include MacMe::Env

    def initialize
      MacMe::Logger.log.debug "Starting MacMe::ChatApi"

      mqtt_client.subscribe(callback_topic)
      mqtt_client.subscribe(mqtt_chat_poll_topic)

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

    def random_lookup_response
      [
        "Standby, looking to see who's at #{zone_name}",
        "One moment while I take a look",
        "Hold your horses. I'll get to it."
      ].sample
    end

    def uid_filter(uid)
      Net::LDAP::Filter.eq('uid', uid)
    end

    def get_uid_objectclass(uid)
      result_attributes = ['objectClass']

      result = ldap_client.search(:filter     => uid_filter(uid),
                                  :attributes => result_attributes)

      result.first.objectclass
    end

    def get_uid_from_irc_nickname(nickname)
      result_attributes = ['dn']
      irc_nickname_filter = Net::LDAP::Filter.eq('displayName', nickname)

      result = ldap_client.search(:filter     => irc_nickname_filter,
                                  :attributes => result_attributes)

      extract_uid_from_dn result.first.dn
    end

    def get_user_devices(uid)
      result_attributes = ['macAddress']

      result = ldap_client.search(:filter     => uid_filter(uid),
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

    def user_is_not_registered?(topic, message)
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

    def user_respond(topic, message)
      topic = [
        "hubot",
        "respond",
        "room",
        extract_room_from_topic(topic)
      ].join('/')

      send_message(topic, message, false)
    end

    def is_macme_command?(message)
      case message
      when /[\W]device\s+(.*)/ then true
      when /[\W]macme\s+(.*)/ then true
      when /[\W]#{zone_name}/ then true
      else false
      end
    end

    ## MacMe::MQTT Public Implementation
    def module_name
      @module_name ||= "MacMe::ChatApi"
    end

    def poll
      mqtt_client.get do |topic, message|
        MacMe::Logger.log.debug("[MacMe::ChatApi]: Processing message #{topic} #{message}")

        if is_app_mqtt? message
          unpacked_message = unpack_message message
          process_callback(topic, unpacked_message) if is_callback?(topic, unpacked_message)
        else
          process_command(topic, message) if is_macme_command? message
        end
      end
    end

    def process_callback(topic, message)
      case message[:command]
      when /get_state/
        callback_get_state(topic, message)
      end
    end

    def process_command(topic, message)
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

    ## Extracts
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

    def extract_users_from_state(state)
      state.map { |device| device[:nickname] }.uniq
    end

    ## Commands
    def cmd_register(topic, message)
      if user_is_not_registered?(topic, message)
        user_respond(topic, "#{username}: Your user has not been linked")
        cmd_help
      else
        mac_address = extract_mac_address_from_message message
        username = extract_username_from_topic topic

        if mac_address
          add_device_to_user(username, mac_address)
          user_respond(topic, "#{username}: Registered MAC #{mac_address} to your account")
        else
          user_respond(topic, "#{username}: That does not appear to be a valid MAC")
        end
      end
    end

    def cmd_remove(topic, message)
      if user_is_not_registered?(topic, message)
        user_respond(topic, "#{username}: Your user has not been linked")
        cmd_help(topic, message)
      else
        mac_address = extract_mac_address_from_message message
        username = extract_username_from_topic topic

        if mac_address
          remove_device_from_user(username, mac_address)
          user_respond(topic, "#{username}: Removed MAC #{mac_address} from your account")
        else
          user_respond(topic, "#{username}: That does not appear to be a valid MAC")
        end
      end
    end

    def cmd_link(topic, message)
      ldap_uid = extract_uid_from_message message
      username = extract_username_from_topic topic

      if ldap_uid
        dn = user_dn ldap_uid
        ldap_client.replace_attribute dn, :displayName, username
        user_respond(topic, "#{username}: Added nick #{username} to #{dn}")
      else
        user_respond(topic, "#{username}: Missing an IRC username to link")
        cmd_help(topic, message)
      end
    end

    def cmd_get_user_devices(topic, message)
      username = extract_username_from_topic topic

      if user_is_not_registered?(topic, message)
        user_respond(topic, "#{username}: Your user has not been linked")
        cmd_help(topic, message)
      else
        uid = get_uid_from_irc_nickname username
        devices = get_user_devices uid

        response = devices.empty? ?
                     "#{username}: No devices currently registered" :
                     "#{username}: Devices registered - #{devices.join(',')}"

        user_respond(topic, response)
      end
    end

    def cmd_get_office_peeps(topic, message)
      username = extract_username_from_topic topic

      payload = {
        :command => "get_state",
        :options => {
          :username => username,
          :topic => topic,
        },
      }

      response = "#{username}: #{random_lookup_response}"

      user_respond(topic, response)
      send_message(command_topic, payload)
    end

    def cmd_help(topic, message)
      response = %Q{
      !#{zone_name} me - View who's all in your zone (#{zone_name})
      !macme link <ldapUid> - Link LDAP account with nickname
      !macme register <macAddress> - Register a device
      !macme remove <macAddress> - Remove device
      !macme list - View all your registered devices}

      user_respond(topic, response)
    end

    ## Callbacks
    def callback_get_state(topic, message)
      username = message[:options][:username]
      reply_topic = message[:options][:topic]

      users_in_office = extract_users_from_state(message[:response][:state])


      response = users_in_office.empty? ?
                   "#{username}: #{random_no_presence_response}" :
                   "#{username}: #{random_presence_response} - #{users_in_office.join(',')}"

      user_respond(reply_topic, response)
    end

  end  # ChatApi
end  # MacMe

MacMe::ChatApi.new
