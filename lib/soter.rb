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
      'active_at' => queue_options.delete(:active_at),
      'priority' => queue_options.delete(:priority) || 0
    }

    queue.insert(job)
    dispatch_worker
  end

  def self.dequeue(job_params)
    queue.remove({ 'job.params' => job_params })
  end

  def self.reschedule(job_params, active_at)
    queue.modify({ 'job.params' => job_params },
                 { 'active_at'  => active_at  })
    dispatch_worker
  end

  def self.update(handler, job_params={}, changes={})
    query = {
      'job' => {
        'params' => job_params,
        'class' => handler.to_s
      }
    }

    queue.modify(query, changes)
  end

  def self.queued?(handler, job_params={})
    query = {
      'job' => {
        'params' => job_params,
        'class' => handler.to_s
      },
      'attempts' => 0
    }

    queue.find(query).count != 0
  end

  def self.keep_alive(id)
    queue.modify({ '_id' => Moped::BSON::ObjectId.from_string(id) },
                 { 'keep_alive_at' => Time.now.utc })
  end

  def self.reset_database_connections
    @database.disconnect if @database
    @queue = nil
    @indexes_created = false

    !!queue
  end

  def self.on_worker_start(&callback)
    callbacks[:start] << callback
  end

  def self.on_worker_finish(&callback)
    callbacks[:finish] << callback
  end

  def self.on_job_error(&callback)
    callbacks[:error] << callback
  end

  #Deprecated
  def self.on_job_start(&callback)
    on_worker_start(&callback)
  end

  #Deprecated
  def self.on_starting_job(&callback)
    on_worker_start(&callback)
  end

  private

  def self.job_worker?
    @job_worker
  end

  def self.job_worker(boolean)
    @job_worker = boolean
  end

  def self.database
    return @database if @database

    hosts = if Soter.config.host
              [ "#{Soter.config.host}:#{Soter.config.port}" ]
            else
              Soter.config.hosts
            end

    @database = Moped::Session.new(hosts, safe: true, consistency: :strong)
  end

  def self.queue
    return @queue if @queue

    @queue = Mongo::Queue.new(database, config.queue_settings)
    create_indexes unless @indexes_created
    @queue
  end

  def self.create_indexes
    collection = queue.send(:collection)
    indexes    = collection.indexes

    indexes.create('_id' => 1)
    indexes.create(locked_by: 1, attempts: 1, active_at: 1, priority: -1)
    indexes.create(locked_by: 1, locked_at: 1)

    @indexes_created = true
  end

  def self.callbacks
    @callbacks ||= Hash.new { |hash, key| hash[key] = [] }
  end

  def self.workers
    #TODO: Remove this rescue clause, moped might not have this issue
    begin
      result = queue.send(:collection).
        find(:locked_by => {"$ne" => nil}).distinct(:locked_by) || []
    rescue Moped::Errors::MongoError
      result = Array.new(max_workers)
    end

    result || Array.new(max_workers)
  end

  def self.dispatch_worker
    queue.cleanup! #remove stuck locks

    if !job_worker? && workers.count < max_workers
      JobWorker.new.start
    end
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
