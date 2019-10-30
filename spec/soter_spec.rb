require 'spec_helper'

describe Soter do

  let(:handler) { FakeHandler }
  let(:job_params) { {option: 'an_option'} }
  let(:logger)  { FakeLogger.new }
  let(:current_time) { Time.now.utc }
  let(:job) do
    {
      job: {
        params: job_params,
        class:  'FakeHandler'
      },
      queue_options: {},
      active_at:     nil,
      priority:      0
    }
  end

  def get_last_job
    Soter.queue.send(:collection).find.first
  end

  def get_stats
    Soter.queue.stats
  end

  before(:each) do
    Soter.queue.flush!
    Soter.config.worker_throttle_value = 0.0001
  end

  it "resets the database connections" do
    Soter.database
    Soter.reset_database_connections.should == true
  end

  context "configuration" do

    it 'configures one host correctly' do
      Soter.config.host     = 'host'
      Soter.config.port     = 'port'
      Soter.config.options  = { 'database' => 'test' }
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
      Soter.config.options  = { 'database' => 'test' }
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

  context "working with the queue" do

    it 'enqueues and starts a job' do
      Soter.queue.should_receive(:insert).with(job)
      Soter::JobWorker.any_instance.should_receive(:start)

      Soter.enqueue(handler, job_params)
    end

    it 'passes the priority option to the queue' do
      Soter.enqueue(handler, job_params, priority: -1, active_at: current_time + 100)
      expect(get_last_job['priority']).to eq(-1)
    end

    context 'with option active_at' do

      it 'starts the job if the time has passed' do
        active_at = current_time - 100
        Soter.enqueue(handler, job_params, {active_at: active_at})

        expect(get_stats[:available]).to eq(0)
      end

      it 'does not start the job if the time has not passed' do
        active_at = current_time + 100
        Soter.enqueue(handler, job_params, {active_at: active_at})

        expect(get_stats[:available]).to eq(1)
      end

    end

    it 'dequeues a job' do
      Soter.enqueue(handler, job_params, {active_at: current_time + 100})
      expect(get_stats[:available]).to eq(1)

      Soter.dequeue(job_params)
      expect(get_stats[:available]).to eq(0)
      expect(get_stats[:total]).to eq(0)
    end

    it 'reschedules a job' do
      Soter.enqueue(handler, job_params, {active_at: current_time + 100})
      expect(get_stats[:available]).to eq(1)

      Soter.reschedule(job_params, current_time - 100)
      expect(get_stats[:available]).to eq(0)
      expect(get_stats[:total]).to eq(0)
    end

    it 'updates a job' do
      job = Soter.enqueue(handler, job_params, {active_at: current_time + 100})
      Soter.update(job['_id'], job: { params: { stuff: 1 } })
      job = get_last_job

      expect(job['job']['params']['stuff']).to eq(1)
    end

    it 'finds if a job is already queued' do
      expect(Soter.queued?(handler, job_params)).to eq(false)
      Soter.enqueue(handler, job_params, {active_at: current_time + 100})
      expect(Soter.queued?(handler, job_params)).to eq(true)
    end

    it 'updates the keep alive for a job to avoid timeouts' do
      Soter.enqueue(handler, job_params, {active_at: current_time + 100})
      job = get_last_job
      expect(job['keep_alive_at']).to eq(nil)

      Soter.keep_alive(job['_id'])
      job = get_last_job
      expect(job['keep_alive_at'].to_i).to be_within(2).of(current_time.to_i)
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

  end

  context "callbacks" do

    before(:each) do
      Soter.callbacks.clear
    end

    context "#on_worker_start" do

      it "is called successfully" do
        attempts = Soter.config.attempts

        Soter.on_worker_start { Soter.config.attempts += 1 }
        Soter.on_worker_start { Soter.config.attempts += 2 }

        Soter.enqueue(handler, {})
        Soter.config.attempts.should == attempts + 3
      end

      it "passes the forking configuration to callbacks" do
        Soter.config.fork = true
        Soter.on_worker_start { |forked| forked.should == true }
        Soter.enqueue(handler, {})
        Soter.callbacks.clear

        Soter.config.fork = false
        Soter.on_worker_start { |forked| forked.should == false }
        Soter.enqueue(handler, {})
        Soter.callbacks.clear
      end

    end

  end

  context "forking" do

    before(:each) { Soter.config.fork = true;  Soter.config.timeout = -1  }
    after(:each)  { Soter.config.fork = false; Soter.config.timeout = nil }

    it "dispatches workers sucessfully" do
      skip("This spec should be run individually, and it does not guarantee " +
           "that it will pass every single time. There is a race condition " +
           "that can happen whenever jobs are enqueued faster than workers " +
           "are able to claim them AND expired workers exist." +
           "In most scenarios this should not be a problem, but in specs this " +
           "is prevented by the sleep() call.")
      Soter.config.fork = true

      100.times do
        Soter.enqueue(handler, {})
        sleep(0.05)
        Soter.workers.count.should <= Soter.config.workers
      end

      Soter.config.fork = false
    end

  end

end
