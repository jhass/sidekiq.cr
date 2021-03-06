require "./spec_helper"
require "../src/sidekiq/server"

class FakeWorker
  include Sidekiq::Worker
  perform_types

  def perform
  end
end

class Foo < Sidekiq::Middleware::Entry
  def call(job, ctx)
    yield
  end
end

describe "Sidekiq::Server" do
  it "allows adding middleware" do
    s = Sidekiq::Server.new
    s.middleware.add Foo.new
    s.middleware.entries.size.should eq(3)
  end

  it "will stop" do
    s = Sidekiq::Server.new
    s.stopping?.should be_false
    s.request_stop
    s.stopping?.should be_true
  end

  it "maintains the processor list" do
    s = Sidekiq::Server.new
    s.processors.size.should eq(0)
    p = s.processor_died(nil, nil)
    s.processors.size.should eq(1)
    s.processor_stopped(nil)
    s.processors.size.should eq(1)
    r = s.processor_died(p, nil)
    r.should_not be_nil
    s.processors.size.should eq(1)
    s.request_stop
    t = s.processor_died(r, nil)
    t.should be_nil
    s.processors.size.should eq(0)
  end
end
