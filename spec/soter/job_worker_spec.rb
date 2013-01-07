require 'spec_helper'

describe Soter::JobWorker do

  let(:handler) { FakeHandler.new } 
  let(:logger)  { FakeLogger.new }
  let(:worker)  { described_class.new(handler, logger) }

  before :each do
    logger.reset
  end


  it "reschedules unsuccessful requests" do
    pending('define retry logic')
    url = "http://test.com"
    body = "Boom"

    FakeWeb.register_uri(:post, url, body: body, status: [500, body])
    JobDispatcher.http_request(url)

    logger.log.should =~ /FAILURE/
    JobDispatcher.send(:queue).stats[:available].should == 1
  end

  context "Non-Forking" do

    it "sends an email job successfully" do
      pending('does the action right away')
      mail_count = ActionMailer::Base.deliveries.count
      JobDispatcher.mail(:to => "test@test.com")
      JobDispatcher.send(:queue).stats[:errors].should == 0
      ActionMailer::Base.deliveries.count.should_not == mail_count
    end

    it "rescues itself from a locked queue" do
      pending('what does this means?')
      old_timeout = QUEUE_SETTINGS[:timeout]
      QUEUE_SETTINGS[:timeout] = 0
      JobDispatcher.instance_variable_set("@queue", nil)

      QUEUE_SETTINGS[:workers].times do 
        JobDispatcher.queue.insert(:to => "test@test.com")
        JobDispatcher.queue.lock_next("test")
      end

      JobDispatcher.mail(:to => "test@test.com")
      JobDispatcher.workers.should be_blank
      QUEUE_SETTINGS[:timeout] = old_timeout
    end

    it "queues a job" do
    end

    it "unqueues a job" do
    end

  end

  context "Forking" do

    before :each do
      #Rails.env = "test_fork"
    end

    after :each do
      #Rails.env = "test"
    end

    it "saves a job successfully" do
      pending
      JobDispatcher.stubs(:dispatch_worker).returns(nil)

      JobDispatcher.mail(:to => "test@test.com", :from => "me@me.com")
      JobDispatcher.send(:queue).stats[:total].should == 1
    end

    it "returns the current workers" do
      pending
      JobDispatcher.stubs(:dispatch_worker).returns(nil)

      JobDispatcher.send(:workers).should == []
      JobDispatcher.mail({:to => "test@test.com"}, {:locked_by => "test"})
      JobDispatcher.mail(:to => "test@test.com")

      JobDispatcher.send(:workers).should == ["test"]
    end

    it "dispatches workers sucessfully" do
      pending("Concurrent tests are hard")
    end

    it "dispatches at most the specified number of workers" do
      pending "Concurrency is hard"

      if JobDispatcher.send(:workers).count > QUEUE_SETTINGS[:workers]
        return
      end

      5.times do
        JobDispatcher.mail(:to => "test@test.com",
                           :from => "me@me.com",
                           :subject => "whatever",
                           :message => "stuff")
      end

      JobDispatcher.send(:workers).count.should <=
        QUEUE_SETTINGS[:workers]
    end

    it "returns the default workers" do
      pending
      JobDispatcher.default_workers.should be_a_kind_of(Numeric)
    end

    it "should raise an error if the job type is unknown" do
      pending
      JobDispatcher.send(:queue).insert({"job"=>"unknown_job"})
      JobDispatcher.send(:dispatch_worker)

      lambda { raise StandardError.new("Unknown job type") }.
        should raise_error(StandardError)
    end

  end
end
