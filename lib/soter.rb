module Soter

  require 'mongo_queue'

  class Config < Struct.new(:fork, :logfile, :queue_settings)
  end

  def self.config
    @config ||= Config.new
  end

  def self.enqueue(handler, options)
    queue.insert(options)
    dispatch_worker(handler)
  end

  def self.dequeue(options)
    queue.remove(options)
  end

  def self.logger
    @logger
  end

  def self.logger=(logger)
    @logger = logger
  end

  private

  def self.database
    @database ||= Mongoid.database.connection
  end

  def self.queue
    @queue ||= Mongo::Queue.new(database, 
                                Soter.config.queue_settings)
  end

  def self.workers
    begin
      result = queue.send(:collection).
        distinct(:locked_by, {:locked_by => {"$ne" => nil}})
    rescue
      result = []
    end

    result || []
  end

  def self.dispatch_worker(handler)
    if workers.count < default_workers
      JobWorker.new(handler, logger).start
    else
      queue.cleanup! #remove stuck locks
    end
  end

  def self.default_workers
    Soter.config.queue_settings[:workers] || 5
  end

end
