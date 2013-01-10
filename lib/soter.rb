require_relative 'soter/config'
require_relative 'soter/job_worker'

require 'mongo'
require 'mongo_queue'

class Module
  def recursive_const_get(name)
    name.to_s.split("::").inject(self) do |b, c|
      b.const_get(c)
    end
  end
end

module Soter

  require 'mongo_queue'

  def self.config
    @config ||= Soter::Config.new
  end

  def self.enqueue(handler, job_params={}, queue_options={})
    job = {
      'job' => {
        'params' => job_params,
        'class' => handler.to_s
      },
      'queue_options' => queue_options,
      'active_at' => queue_options.delete(:active_at)
    }

    queue.insert(job)
    dispatch_worker
  end

  def self.dequeue(job_params)
    queue.remove('job_params' => job_params)
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
    if workers.count < max_workers
      JobWorker.new.start
    else
      queue.cleanup! #remove stuck locks
    end
  end

  def self.max_workers
    Soter.config.workers || 5
  end

end
