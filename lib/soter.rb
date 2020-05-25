require_relative 'soter/config'
require_relative 'soter/job_worker'

require 'mongo'
require 'mongo_queue'

module Soter

  attr_accessor :client

  def self.config
    @config ||= Soter::Config.new
  end

  def self.enqueue(handler, job_params={}, queue_options={})
    job = {
      job: {
        params: job_params,
        class:  handler.to_s
      },
      queue_options: queue_options,
      active_at:     queue_options.delete(:active_at),
      priority:      queue_options.delete(:priority) || 0
    }

    Rails.logger.debug("\n\n[SOTER][PID #{Process.pid}][WP_DB_ID #{::Mongoid.default_client.object_id }]\n enqueue #{job_params.inspect}")
    Rails.logger.debug("\n\n[SOTER][PID #{Process.pid}][SOT_DB_ID #{@client.object_id }]\n enqueue\n") if @client
    job = queue_command(:insert, job)
    dispatch_worker
    return job
  end

  def self.dequeue(job_params)
    queue_command(:remove, { 'job.params' => job_params })
  end

  def self.reschedule(job_params, active_at)
    queue_command(:modify, { 'job.params' => job_params },
                           { 'active_at'  => active_at  })
    dispatch_worker
  end

  def self.update(id, changes={})
    queue_command(:modify, { '_id' => BSON::ObjectId.from_string(id) }, changes)
  end

  def self.queued?(handler, job_params={})
    query = {
      'job' => {
        'params' => job_params,
        'class' => handler.to_s
      },
      'attempts' => 0
    }

    queue_command(:find, query).count != 0
  end

  def self.keep_alive(id)
    update(id, { 'keep_alive_at' => Time.now.utc })
  end

  def self.reset_database_connections
    Rails.logger.debug("\n\n[SOTER][PID #{Process.pid}][WP_DB_ID #{::Mongoid.default_client.object_id }]\n reset_database_connections\n")
    Rails.logger.debug("\n\n[SOTER][PID #{Process.pid}][SOT_DB_ID #{@client.object_id }]\n reset_database_connections\n") if @client
    @client.close if @client
    #@client.reconnect if @client
    @client = nil
    @queue = nil
    @indexes_created = false
    @database = nil

    !!queue
  end

  def self.drop_queue_collection
    queue.instance_variable_get("@connection").database.drop
  end

  def self.on_worker_start(&callback)
    callbacks[:worker_start] << callback
  end

  def self.on_worker_finish(&callback)
    callbacks[:worker_finish] << callback
  end

  def self.on_job_start(&callback)
    callbacks[:job_start] << callback
  end

  def self.on_job_finish(&callback)
    callbacks[:job_finish] << callback
  end

  def self.on_job_error(&callback)
    callbacks[:job_error] << callback
  end

  def self.worker_relative_directory
    'tmp/soter_workers'
  end

  private

  def self.job_worker?
    @job_worker
  end

  def self.job_worker(boolean)
    @job_worker = boolean
  end

  def self.client
    return @client if @client

    hosts = if config.host
              [ "#{config.host}:#{config.port}" ]
            else
              config.hosts
            end
    Rails.logger.debug("\n\n[SOTER][PID #{Process.pid}] CREATING NEW SOTER CLIENT AFTER RESTART?\n")
    @client = Mongo::Client.new(hosts, config.options)
    Rails.logger.debug("\n\n[SOTER][PID #{Process.pid}] CREATING NEW SOTER CLIENT AFTER RESTART -> #{@client.object_id}\n")

    @client
  end

  def self.queue
    return @queue if @queue

    @queue = Mongo::Queue.new(client, config.queue_settings)
    create_indexes unless @indexes_created
    @queue
  end

  def self.create_indexes
    collection = queue.send(:collection)
    indexes    = collection.indexes

    indexes.create_one('_id' => 1)
    indexes.create_one(attempts: 1) #queued?
    indexes.create_one(locked_by: 1, attempts: 1, active_at: 1, priority: -1)
    indexes.create_one(locked_by: 1, locked_at: 1)

    @indexes_created = true
  end

  def self.callbacks
    @callbacks ||= Hash.new { |hash, key| hash[key] = [] }
  end

  def self.workers
    Dir[worker_relative_directory + '/**']
  end

  def self.dispatch_worker
    Rails.logger.debug("\n\n[SOTER][PID #{Process.pid}][WP_DB_ID #{::Mongoid.default_client.object_id }]\n dispatch_worker\n")
    Rails.logger.debug("\n\n[SOTER][PID #{Process.pid}][SOT_DB_ID #{@client.object_id }]\n dispatch_worker\n") if @client
    cleanup_workers

    throttle_worker_request

    if !job_worker? && !worker_slots_full?
      JobWorker.new.start
    end
  end

  def self.cleanup_workers
    #Clear all timed-out jobs
    queue.cleanup!

    #Find all the long-running workers
    long_running_workers = workers.select do |worker|
      begin
        File.mtime(worker) + config.timeout <= Time.now.utc
      rescue Errno::ENOENT
        false
      end
    end

    unless long_running_workers.empty?
      #Find all the currently active workers
      busy_workers = queue.send(:collection).
                     find(:locked_by => {"$ne" => nil}).
                     distinct(:locked_by) || []

      #Remove active workers from the kill list
      long_running_workers.reject! do |worker|
        id = worker.split('/').last
        busy_workers.include?(id)
      end

      #Worker is kill
      long_running_workers.each do |worker|
        File.delete(worker) if File.exist?(worker)
      end
    end
  end

  def self.throttle_worker_request
    sleep(rand(0..config.worker_throttle_value))
  end

  def self.worker_slots_full?
    workers.count >= max_workers
  end

  def self.max_workers
    config.workers
  end

  # First 8 retry values in minutes are:
  # 2.minutes, 17.minutes, 2.hours, 6.hours,
  # 16.hours, 31.hours, 54.hours, 85.hours
  def self.retry_offset(retries)
    ( (retries-1) ** 3 ) * (15 * 60) + 120
  end

  def self.recursive_const_get(name)
    name.to_s.split("::").inject(Object) do |b, c|
      b.const_get(c)
    end
  end

  def self.queue_command(command, *args)
    retries ||= 0
    Rails.logger.debug("\n\n[SOTER][PID #{Process.pid}][WP_DB_ID #{::Mongoid.default_client.object_id }]\n Queue command #{command} #{args.inspect}")
    Rails.logger.debug("\n\n[SOTER][PID #{Process.pid}][SOT_DB_ID #{@client.object_id }]") if @client
    queue.send(command, *args)
  rescue Mongo::Error::SocketError => error
    retries += 1
    Rails.logger.debug("\n\n#{error.class}")
    Rails.logger.debug(error.message)
    Rails.logger.debug(error.backtrace.join("\n") + "\n\n")
    Rails.logger.debug("\n\n[SOTER][PID #{Process.pid}] #{command} FAILED!!!\n\nResetting the database, retry ##{retries}")
    reset_database_connections
    Rails.logger.debug("\n\n[SOTER][PID #{Process.pid}] #{command} FAILED!!!\n\nReady for retry")
    #retry if retries < 2

    raise error
  end
end