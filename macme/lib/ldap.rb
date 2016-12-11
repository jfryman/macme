#!/usr/bin/env ruby
require 'rubygems'
require 'net/ldap'

module MacMe::LDAP
  def ldap_client
    ldap_args = {}
    ldap_args[:host] = ENV['LDAP_HOST']
    ldap_args[:base] = ENV['LDAP_BASE_DN']
    ldap_args[:encryption] = :simple_tls if ENV['LDAP_SSL']
    ldap_args[:port] = ENV['LDAP_PORT'] || ENV['LDAP_SSL'] ? 636 : 389

    if ENV['LDAP_BIND_DN'] and ENV['LDAP_BIND_PASSWORD']
      auth = {}
      auth[:username] = bind_dn
      auth[:password] = password
      auth[:method] = :simple
      ldap_args[:auth] = auth
    end

    @ldap_client ||= Net::LDAP.new(ldap_args)
  end
end
