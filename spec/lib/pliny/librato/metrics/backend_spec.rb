require 'spec_helper'

RSpec.describe Pliny::Librato::Metrics::Backend do
  let(:source)        { 'myapp.production' }
  let(:interval)      { 1 }
  let(:librato_queue) { Librato::Metrics::Queue.new(skip_measurement_times: true) }
  let(:counter_cache) { Librato::Collector::CounterCache.new(default_tags: nil) }
  let(:aggregator)    { Librato::Metrics::Aggregator.new }
  let(:metrics)       { { 'foo.bar' => 1, baz: 2 } }

  subject(:backend) do
    described_class.new(
      interval: interval,
      source:   source
    )
  end

  describe '#initialize' do
    it 'creates a Librato::Metrics::Queue' do
      expect(Librato::Metrics::Queue).to receive(:new).with(
        source: source,
        skip_measurement_times: true,
      ).and_call_original

      expect(backend.send(:librato_queue))
        .to be_an_instance_of(Librato::Metrics::Queue)
    end

    it 'creates a Librato::Metrics::Aggregator' do
      expect(Librato::Metrics::Aggregator).to receive(:new).and_call_original

      expect(backend.send(:librato_queue))
        .to be_an_instance_of(Librato::Metrics::Queue)
    end

  end

  describe '#report_counts' do
    it 'utilizes the counter cache' do
      allow(backend).to receive(:counter_cache).and_return(counter_cache)
      10.times do
        backend.report_counts(metrics)
      end

      expected = {
        "foo.bar"=>{:name=>"foo.bar", :value=>10},
        "baz"=>{:name=>"baz", :value=>20}
      }
      expect(counter_cache.instance_variable_get(:@cache)).to eq(expected)
    end
  end

  describe '#report_measures' do
    before do
      allow(librato_queue).to receive(:merge!)
      allow(backend).to receive(:librato_queue).and_return(librato_queue)
      backend.start
    end

    after do
      backend.stop
    end

    it 'utilizes the aggregator' do
      allow(backend).to receive(:aggregator).and_return(aggregator)
      10.times do
        backend.report_measures(metrics)
      end
      expected = {
        :gauges=>[
          {:name=>"foo.bar", :count=>10, :sum=>10.0, :min=>1.0, :max=>1.0},
          {:name=>"baz", :count=>10, :sum=>20.0, :min=>2.0, :max=>2.0}
        ]
      }
      expect(aggregator.queued).to eq(expected)
    end
  end

  describe '#flush_librato' do
    it 'grabs the counter and aggregator' do
      allow(backend).to receive(:librato_queue).and_return(librato_queue)
      allow(librato_queue).to receive(:submit)

      backend.report_counts(requests: { value: 1 })
      backend.report_measures(request_time: { value: 10 })
      backend.send(:flush_librato)

      expected = {
        :gauges=>[
          {:name=>"requests", :value=>1},
          {:name=>"request_time", :count=>1, :sum=>10.0, :min=>10.0, :max=>10.0}
        ]
      }

      expect(librato_queue.queued).to eq(expected)
    end
  end

  describe '#start' do
    before do
      allow(backend).to receive(:librato_queue).and_return(librato_queue)
      allow(librato_queue).to receive(:submit)

      allow(Thread).to receive(:new).and_call_original
      backend.start
    end

    after do
      backend.stop
    end

    it 'creates a new timer thread' do
      expect(backend.send(:timer)).to be_a(Thread)
    end
  end

  describe '#stop' do
    before do
      allow(backend).to receive(:librato_queue).and_return(librato_queue)
      backend.start
    end

    it 'flushes the librato queue' do
      expect(librato_queue).to receive(:submit)
      backend.stop
    end
  end

  describe '#timer' do
    let(:interval) { 0.05 }
    let(:count)    { 500 }

    before do
      allow(backend).to receive(:librato_queue).and_return(librato_queue)
      allow(librato_queue).to receive(:submit)
      backend.start
    end

    it 'periodically flushes the queue' do
      sleep 0.1
      expect(librato_queue).to have_received(:submit).at_least(1).times
    end
  end
end
