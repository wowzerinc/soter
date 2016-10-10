module Soter
  class Config < Struct.new(:fork, :logfile, :logger, :host, :port, :database,
                            :workers, :attempts, :hosts, :timeout, :collection)

    def queue_settings
      host_settings = host ? {host: host, port: port} : {hosts: hosts}

      host_settings.merge!(database: database) if database

      host_settings.merge!(collection: collection,
                           timeout:    timeout,
                           attempts:   attempts)
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

  end
end
