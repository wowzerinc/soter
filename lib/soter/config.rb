module Soter
  class Config < Struct.new(:fork, :logfile, :logger, :host, :port, :options,
                            :workers, :attempts, :hosts, :timeout, :collection,
                            :worker_misses_limit, :worker_miss_sleep,
                            :worker_throttle_value)

    def queue_settings
      host_settings = host ? {host: host, port: port} : {hosts: hosts}

      host_settings.merge!(database: options['database']) if options['database']

      host_settings.merge!(collection: collection,
                           timeout:    timeout,
                           attempts:   attempts)
    end

    def worker_misses_limit
      self['worker_misses_limit'] || 3
    end

    def worker_miss_sleep
      self['worker_miss_sleep'] || 5
    end

    def timeout
      self['timeout'] || 300
    end

    def attempts
      self['attempts'] || 3
    end

    def collection
      self['collection'] || "soter_queue"
    end

    def workers
      self['workers'] || 5
    end

    def options
      self['options'] || {}
    end

    def worker_throttle_value
      value = self['worker_throttle_value'] || 2.0
      raise "Throttle value must be a float" unless value.is_a?(Float)
      value
    end

  end
end
