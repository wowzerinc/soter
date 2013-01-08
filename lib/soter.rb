require_relative 'soter/job_worker'

require 'mongo'
require 'mongo_queue'

module Soter

  require 'mongo_queue'

  class Config < Struct.new(:fork, :logfile, :logger, :host, :port, :db,
                            :workers)

    def queue_settings
      { 
        host:       self.host,   
        port:       self.port,
        database:   self.db, 
        collection: "mongo_queue",
        timeout:    300,
        attempts:   3
      }
    end

  end

  def self.config
    @config ||= Config.new
  end

  def self.enqueue(handler, options)
    queue.insert(options.merge({'handler_class' =>  handler.to_s}))
    dispatch_worker
  end

  def self.dequeue(options)
    queue.remove(options)
  end

  private

  def self.database
    @database ||= Mongo::Connection.new
  end

  def self.queue
    @queue ||= Mongo::Queue.new(database, Soter.config.queue_settings)
  end

  def self.workers
    begin
      result = @queue.send(:collection).
        distinct(:locked_by, {:locked_by => {"$ne" => nil}})
    rescue
      result = []
    end

    result || []
  end

  def self.dispatch_worker
    if workers.count < default_workers
      JobWorker.new.start
    else
      queue.cleanup! #remove stuck locks
    end
  end

  def self.default_workers
    Soter.config.workers || 5
  end

end
