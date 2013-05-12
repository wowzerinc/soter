module Soter
  class Config < Struct.new(:fork, :logfile, :logger, :host, :port, :database,
                            :workers, :attempts, :hosts, :timeout, :collection)

    def queue_settings
      host_settings = host ? {host: host, port: port} : {hosts: hosts}

      host_settings.merge!(database: database) if database

      host_settings.merge!({
        collection: collection || "soter_queue",
        timeout:    timeout    || 300,
        attempts:   attempts   || 3
      })
    end

  end
end
