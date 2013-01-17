module Soter
  class Config < Struct.new(:fork, :logfile, :logger, :host, :port, :db,
                            :workers, :attempts)

    def queue_settings
      { 
        host:       self.host,   
        port:       self.port,
        database:   self.db, 
        collection: "mongo_queue",
        timeout:    300,
        attempts:   ( self.attempts || 3 )
      }
    end

  end
end
