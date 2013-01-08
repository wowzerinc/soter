require_relative 'soter/config'
require_relative 'soter/job_worker'

require 'mongo'
require 'mongo_queue'

module Soter

  require 'mongo_queue'

  def self.config
    @config ||= Soter::Config.new
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
