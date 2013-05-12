require_relative 'soter/config'
require_relative 'soter/job_worker'

require 'moped'
require 'mongo_queue'

module Soter

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

  def self.reset_database_connections
    !!(@database.disconnect if @database)
  end

  def self.on_starting_job(&callback)
    callbacks << callback
  end

  private

  def self.database
    hosts = if Soter.config.host
              [ "#{Soter.config.host}:#{Soter.config.port}" ]
            else
              Soter.config.hosts
            end

    @database ||= Moped::Session.new(hosts, safe: true, consistency: :strong)
  end

  def self.queue
    @queue ||= Mongo::Queue.new(database, config.queue_settings)
  end

  def self.callbacks
    @callbacks ||= []
  end

  def self.workers
    #TODO: Remove this rescue clause, moped might not have this issue
    begin
      result = database[config.collection].
        distinct(:locked_by, {:locked_by => {"$ne" => nil}})
    rescue
      result = []
    end

    result || []
  end

  def self.dispatch_worker
    queue.cleanup! #remove stuck locks
    JobWorker.new.start if workers.count < max_workers
  end

  def self.max_workers
    Soter.config.workers || 5
  end

  # First 8 retry values in minutes are:
  # 2.minutes, 17.minutes, 2.hours, 6.hours,
  # 16.hours, 31.hours, 54.hours, 85.hours
  def self.retry_offset(retries)
    ( (retries-1) ** 3 ) * (15 * 60) + 120
  end

  def self.recursive_const_get(name)
    name.to_s.split("::").inject(self) do |b, c|
      b.const_get(c)
    end
  end

end
