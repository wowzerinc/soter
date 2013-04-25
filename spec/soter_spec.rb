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

  it 'configures one host correctly' do
    Soter.config.host = 'host'
    Soter.config.port = 'port'
    Soter.config.db   = 'test'
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
    Soter.config.host  = nil
    Soter.config.hosts = ['127.0.0.1:27017', 'localhost:27017']
    Soter.config.db    = 'test'
    Soter.config.attempts = 3

    Soter.config.queue_settings.should == {
      hosts:      ['127.0.0.1:27017', 'localhost:27017'],
      database:   'test',
      collection: 'soter_queue',
      timeout:    300,
      attempts:   3
    }
  end

  it 'enqueues and starts a job' do
    Soter.queue.should_receive(:insert).with(job)
    Soter::JobWorker.any_instance.should_receive(:start)

    Soter.enqueue(handler, job_params)
  end

  context 'with option active_at' do

    it 'starts the job if the time has passed' do
      pending("This isn't testing what it claims")
      job['active_at'] = (active_at = current_time - 100)
      Soter.queue.should_receive(:insert).with(job)

      Soter.enqueue(handler, job_params, {active_at: active_at})
    end

    it 'does not start the job if the time has not passed' do
      pending("This isn't testing what it claims")
      job['active_at'] = (active_at = current_time + 100)
      Soter.queue.should_receive(:insert).with(job)

      Soter.enqueue(handler, job_params, {active_at: active_at})
    end

  end

  it 'dequeues a job' do
    Soter.queue.should_receive(:remove).with('job_params' => job_params)

    Soter.dequeue(job_params)
  end

  it 'sets logger correctly' do
    Soter.config.logger = logger

    Soter.config.logger.should == logger
  end

  it "dispatches at most the specified number of workers" do
    pending("This isn't testing what it claims")
    Soter.queue.should_receive(:insert).with(job)
    Soter.queue.should_receive(:cleanup!).once

    Soter.enqueue(handler, job_params)
  end

  it "calculates correct retry offset" do
    expected_values = [ 2, 17, 122, 407, 962]

    expected_values.each_with_index do |value, index|
      retries = index+1
      Soter.send(:retry_offset, retries).should == value * 60
    end
  end

  context "Forking" do

    before :each do
      Soter.config.fork = true
    end

    it "dispatches workers sucessfully" do
      pending("Concurrent tests are hard, what should we test?")
    end

  end
end
