module Soter
  class Config < Struct.new(:fork, :logfile, :logger, :host, :port, :db,
                            :workers, :attempts, :hosts)

    def queue_settings
      host_settings = host ? {host: host} : {hosts: hosts}

      host_settings.merge({
        port:       port,
        database:   db,
        collection: "soter_queue",
        timeout:    300,
        attempts:   (attempts || 3)
      })
    end

  end
end
