require 'spec_helper'

describe Soter do

  let(:handler) { FakeHandler }
  let(:job_params) { {option: 'an_option'} }
  let(:logger)  { FakeLogger.new }
  let(:time)    { Time.now.utc }
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

  it 'configures correctly' do
    Soter.config.host = 'host'
    Soter.config.port = 'port'
    Soter.config.db   = 'test'
    Soter.config.attempts = 3

    Soter.config.queue_settings.should == {
      host:       'host',
      port:       'port',
      database:   'test',
      collection: 'mongo_queue',
      timeout:    300,
      attempts:   3
    }
  end

  it 'enqueues a job' do
    Soter.queue.should_receive(:insert).with(job)
    Soter::JobWorker.any_instance.should_receive(:start)

    Soter.enqueue(handler, job_params)
  end

  it 'enqueues a job active at a certain time' do
    job['active_at'] = time
    Soter.queue.should_receive(:insert).with(job)
    Soter::JobWorker.any_instance.should_receive(:start)

    Soter.enqueue(handler, job_params, {active_at: time})
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
    Soter.queue.should_receive(:insert).with(job)
    Soter.queue.should_receive(:cleanup!).once

    Soter.enqueue(handler, job_params)
  end

  it "calculates correct retry offset" do
    expected_values = [ 2, 17, 122, 407, 962]

    expected_values.each_with_index do |value, index|
      Soter.send(:retry_offset, index+1).should == value * 60
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
