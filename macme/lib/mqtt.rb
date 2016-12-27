require 'rubygems'
require 'tempfile'
require 'mqtt'
require 'base64'
require_relative 'env.rb'
require_relative 'logger.rb'


module MacMe
  module MQTT
    include MacMe::Env

    def mqtt_client
      mqtt_args = {}

      mqtt_args[:host] = ENV['MQTT_HOST']
      mqtt_args[:port] = ENV['MQTT_PORT'] || ENV['MQTT_SSL'] ? 8883 : 1883
      mqtt_args[:ssl] = true if ENV['MQTT_SSL'] or ENV['MQTT_PORT'].to_i == 8883

      if ENV['MQTT_USERNAME'] and ENV['MQTT_PASSWORD']
        mqtt_args[:username]= ENV['MQTT_USERNAME']
        mqtt_args[:password] = ENV['MQTT_PASSWORD']
      end

      if ENV['MQTT_CA_CERT']
        mqtt_args[:ca_file]= extract_cert_from_env(ENV['MQTT_CA_CERT'])
      end

      if ENV['MQTT_CERT'] and ENV['MQTT_KEY']
        mqtt_args[:cert_file] = extract_cert_from_env(ENV['MQTT_CERT'])
        mqtt_args[:key_file] = extract_cert_from_env(ENV['MQTT_KEY'])
      end

      @mqtt_client ||= ::MQTT::Client.connect(mqtt_args)
    end

    def extract_cert_from_env(env_variable)
      cert_file = Tempfile.new(
        Digest::SHA256.hexdigest(env_variable))
      cert_file.write(Base64.decode64(env_variable))
      cert_file.close

      cert_file.path
    end

    def app_command_topic
      [
        mqtt_topic,
        zone_name,
        'command'
      ].join('/')
    end

    def callback_topic
      [
        mqtt_topic,
        zone_name,
        'callback'
      ].join('/')
    end

    def is_command?(topic="", message)
      if topic == app_command_topic and message.key?(:command)
        true
      else
        false
      end
    end

    def is_app_mqtt?(message)
      begin
        unpack_message message

        true
      rescue
        false
      end
    end

    def is_callback?(topic, message)
      if topic == callback_topic and
        message.key(:command) and
        message.key?(:recipient) and
        message.key?(:response)

        true
      else
        false
      end
    end

    def intended_recipient?(topic, message)
      if message.key?(:recipient)
        message[:recipient] == module_name(message)
      else
        false
      end
    end

    def module_name(message)
      message[:recipient]
    end

    def unpack_message(message)
      JSON.parse(message, {:symbolize_names => true})
    end

    def send_message(topic, message, to_json = true)
      payload = to_json ? message.to_json : message

      mqtt_client.publish(topic, payload)
    end

    def process_targeted_incoming_message(topic, message)
      if is_callback?(topic, message)
        process_callback(topic, unpack_message(message))
      elsif is_command?(topic, message)
        process_command(topic, unpack_message(message))
      end
    end

    def process_incoming_message(topic, message)
      if intended_recipient?(topic, message)
        process_targeted_incoming_message(topic, message)
      else
        process_message(topic, message)
      end
    end

    # MacMe::MQTT Public Implementation
    def poll
      mqtt_client.subscribe(app_command_topic)
      mqtt_client.subscribe(callback_topic)

      mqtt_client.get do |topic, message|
        if is_app_mqtt? message
          process_incoming_message(topic, unpack_message(message))
        end
      end
    end

    def process_command(topic, message)
      true
    end

    def process_message(topic, message)
      true
    end

    def process_callback(topic, message)
      true
    end

  end # MQTT
end # MacMe
