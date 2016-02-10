require 'spec_helper'

describe Soter do

  let(:handler) { FakeHandler }
  let(:job_params) { {option: 'an_option'} }
  let(:logger)  { FakeLogger.new }
  let(:current_time) { Time.now.utc }
  let(:job) do
    {
      'job' => {
        'params' => job_params,
        'class'  => 'FakeHandler'
      },
      'queue_options' => {},
      'active_at'     => nil
    }
  end

  it "resets the database connections" do
    Soter.database
    Soter.reset_database_connections.should == true
  end

  context "configuration" do

    it 'configures one host correctly' do
      Soter.config.host     = 'host'
      Soter.config.port     = 'port'
      Soter.config.database = 'test'
      Soter.config.attempts = 3

      Soter.config.queue_settings.should == {
        host:       'host',
        port:       'port',
        database:   'test',
        collection: 'soter_queue',
        timeout:    300,
        attempts:   3
      }
    end

    it 'configures multiple hosts correctly' do
      Soter.config.host     = nil
      Soter.config.hosts    = ['localhost:27017']
      Soter.config.database = 'test'
      Soter.config.attempts = 3

      Soter.config.queue_settings.should == {
        hosts:      ['localhost:27017'],
        database:   'test',
        collection: 'soter_queue',
        timeout:    300,
        attempts:   3
      }
    end

    it 'sets logger correctly' do
      Soter.config.logger = logger

      Soter.config.logger.should == logger
    end

  end

  context "queueing and dequeueing" do

    it 'enqueues and starts a job' do
      Soter.queue.should_receive(:insert).with(job)
      Soter::JobWorker.any_instance.should_receive(:start)

      Soter.enqueue(handler, job_params)
    end

    context 'with option active_at' do

      it 'starts the job if the time has passed' do
        skip("This isn't testing what it claims")
        job['active_at'] = (active_at = current_time - 100)
        Soter.queue.should_receive(:insert).with(job)

        Soter.enqueue(handler, job_params, {active_at: active_at})
      end

      it 'does not start the job if the time has not passed' do
        skip("This isn't testing what it claims")
        job['active_at'] = (active_at = current_time + 100)
        Soter.queue.should_receive(:insert).with(job)

        Soter.enqueue(handler, job_params, {active_at: active_at})
      end

    end

    it 'dequeues a job' do
      Soter.queue.should_receive(:remove).with('job.params' => job_params)

      Soter.dequeue(job_params)
    end

  end

  context "workers" do

    it "dispatches at most the specified number of workers" do
      skip("This isn't testing what it claims")
      Soter.queue.should_receive(:insert).with(job)
      Soter.queue.should_receive(:cleanup!).once

      Soter.enqueue(handler, job_params)
    end

    it "calculates correct retry offset" do
      expected_values_in_minutes = [2, 17, 122, 407, 962]

      expected_values_in_minutes.each_with_index do |value, index|
        retries = index + 1
        Soter.send(:retry_offset, retries).should == value * 60
      end
    end

    it "rescues itself from a locked queue" do
      old_timeout = Soter.config.timeout
      Soter.config.timeout = -1

      #Lock the queue: all worker slots are occupied and timed out
      Soter.max_workers.times do
        Soter.queue.insert({})
        Soter.queue.lock_next('stuck worker')
      end

      #Enqueue a new job: stuck locks are removed,
      #the new worker clears the queue and exits
      Soter.enqueue(handler)

      Soter.workers.should be_empty
      Soter.config.timeout = old_timeout
    end

  end

  context "callbacks" do

    context "#on_starting_job" do

      it "is called successfully" do
        attempts = Soter.config.attempts

        Soter.on_starting_job { Soter.config.attempts += 1 }
        Soter.on_starting_job { Soter.config.attempts += 2 }

        Soter.enqueue(handler, {})
        Soter.config.attempts.should == attempts + 3
      end

      it "passes the forking configuration to callbacks" do
        Soter::JobWorker.any_instance.stub(:schrodingers_fork).
          and_return( lambda { yield } )

        Soter.config.fork = true
        Soter.on_starting_job { |fork| fork.should == true }

        Soter.config.fork = false
        Soter.on_starting_job { |fork| fork.should == false }

        Soter.enqueue(handler, {})
      end

    end

  end

  context "forking" do

    before(:all) { Soter.config.fork = true  }
    after(:all)  { Soter.config.fork = false }

    it "dispatches workers sucessfully" do
      skip("Concurrent tests are hard, what should we test?")
    end

  end

end
