#!/usr/bin/env ruby
require 'rubygems'
require 'tempfile'
require 'mqtt'
require 'base64'
require_relative 'logger.rb'

module MacMe
  module MQTT
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
        mqtt_args[:ca_file]= extract_cert_from_env(:ca_file, ENV['MQTT_CA_CERT'])
      end

      if ENV['MQTT_CERT'] and ENV['MQTT_KEY']
        mqtt_args[:cert_file] = extract_cert_from_env(:cert_file, ENV['MQTT_CERT'])
        mqtt_args[:key_file] = extract_cert_from_env(:key_file, ENV['MQTT_KEY'])
      end

      @mqtt_client ||= ::MQTT::Client.connect(mqtt_args)
    end

    def extract_cert_from_env(cert, env_variable)
      cert_file = Tempfile.new(
        Digest::SHA256.hexdigest(env_variable))
      cert_file.write(Base64.decode64(env_variable))
      cert_file.close

      cert_file.path
    end
  end
end
