require 'logger'


module MacMe
  module Logger
    def self.log
      if @logger.nil?
        @logger = ::Logger.new STDOUT
        @logger.level = ENV['MACME_LOG_LEVEL'] || ::Logger::DEBUG
        @logger.datetime_format = '%Y-%m-%d %H:%M:%S '
      end
      @logger
    end

    def self.trace(module_name, log, topic=nil, message=nil)
      if topic and message
        log_line = "[#{module_name}] #{log} (#{topic} / #{message})"
      else
        log_line = "[#{module_name}] #{log}"
      end

      self.log.debug log_line
    end

  end  # Logger
end  # MacMe
