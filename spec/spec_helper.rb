require_relative '../lib/soter.rb'

class FakeLogger
  def <<(s); (@log ||= '') << s; end
  def log; @log; end
  def close; end
  def reset; @log = ''; end
end

FakeHandler = Class.new do
  def initialize(*)
  end

  def perform
    sleep(Random.rand) if Soter.config.fork
  end

  def message
    'message'
  end
  
  def success?
    true
  end
end

module Handlers
  Fake = FakeHandler
end

Soter.config.host = 'localhost'
Soter.config.port = 27017
