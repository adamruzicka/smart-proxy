require 'test_helper'
require 'puppet_proxy_puppet_api/report_format12_transformer'

class ReportFormat12TransformerTest < Test::Unit::TestCase
  def metrics(overrides = {})
    {
      'resources' => {'name' => 'resources', 'label' => 'Resources', 'values' => [
        ['restarted', 'Restarted', 0],
        ['failed', 'Failed', 0],
        ['failed_to_restart', 'Failed to restart', 0],
        ['skipped', 'Skipped', 0],
      ]},
      'events' => {'name' => 'events', 'label' => 'Events', 'values' => [
        ['noop', 'Noop', 0],
        ['total', 'Total', 0],
      ]},
      'changes' => {'name' => 'changes', 'label' => 'Changes', 'values' => [
        ['total', 'Total', 0],
      ]},
    }.merge(overrides)
  end

  def report(overrides = {})
    {
      'host' => 'test.example.com',
      'time' => '2024-01-01T12:00:00Z',
      'status' => 'changed',
      'metrics' => metrics,
      'logs' => [],
    }.merge(overrides)
  end

  def transform(report)
    Proxy::PuppetApi::ReportFormat12Transformer.transform(report)
  end

  def test_maps_host_and_reported_at
    result = transform(report)
    assert_equal 'test.example.com', result['host']
    assert_equal '2024-01-01 12:00:00 UTC', result['reported_at']
  end

  def test_flattens_metrics_into_name_value_hashes
    result = transform(report)
    assert_equal 0, result['metrics']['resources']['failed']
    assert_equal 0, result['metrics']['changes']['total']
  end

  def test_status_counts_resolve_from_correct_metric_categories
    overrides = {
      'resources' => {'values' => [
        ['restarted', 'Restarted', 2],
        ['failed', 'Failed', 3],
        ['failed_to_restart', 'Failed to restart', 4],
        ['skipped', 'Skipped', 0],
      ]},
      'events' => {'values' => [['noop', 'Noop', 5], ['total', 'Total', 5]]},
      'changes' => {'values' => [['total', 'Total', 1]]},
    }
    result = transform(report('metrics' => metrics(overrides)))

    assert_equal({
                   'applied' => 1,
      'restarted' => 2,
      'failed' => 3,
      'failed_restarts' => 4,
      'skipped' => 0,
      'pending' => 5,
                 }, result['status'])
  end

  def test_zeroes_skipped_when_it_fully_accounts_for_the_status_total
    overrides = {'resources' => {'values' => [
      ['restarted', 'Restarted', 0],
      ['failed', 'Failed', 0],
      ['failed_to_restart', 'Failed to restart', 0],
      ['skipped', 'Skipped', 3],
    ]}}
    result = transform(report('metrics' => metrics(overrides), 'logs' => []))

    assert_equal 0, result['status']['skipped']
  end

  def test_does_not_zero_skipped_when_logs_account_for_the_difference
    overrides = {'resources' => {'values' => [
      ['restarted', 'Restarted', 0],
      ['failed', 'Failed', 0],
      ['failed_to_restart', 'Failed to restart', 0],
      ['skipped', 'Skipped', 3],
    ]}}
    logs = [{'level' => 'notice', 'message' => 'msg', 'source' => 'Foo'}]
    result = transform(report('metrics' => metrics(overrides), 'logs' => logs))

    assert_equal 3, result['status']['skipped']
  end

  def test_increments_failed_when_report_status_is_failed
    result = transform(report('status' => 'failed'))
    assert_equal 1, result['status']['failed']
  end

  def test_increments_failed_for_each_err_log_from_puppet_source
    logs = [
      {'level' => 'err', 'message' => 'oops', 'source' => 'Puppet'},
      {'level' => 'err', 'message' => 'also oops', 'source' => 'Something::Puppet'},
    ]
    result = transform(report('logs' => logs))
    assert_equal 2, result['status']['failed']
  end

  def test_does_not_increment_failed_for_non_err_level_from_puppet_source
    logs = [{'level' => 'notice', 'message' => 'fine', 'source' => 'Puppet'}]
    result = transform(report('logs' => logs))
    assert_equal 0, result['status']['failed']
  end

  def test_does_not_increment_failed_for_err_level_from_other_source
    logs = [{'level' => 'err', 'message' => 'oops', 'source' => 'Foo::Bar'}]
    result = transform(report('logs' => logs))
    assert_equal 0, result['status']['failed']
  end

  def test_drops_debug_logs_and_the_finished_catalog_run_summary
    logs = [
      {'level' => 'debug', 'message' => 'debug msg', 'source' => 'Foo'},
      {'level' => 'notice', 'message' => 'Finished catalog run in 1.23 seconds', 'source' => 'Puppet'},
      {'level' => 'notice', 'message' => 'Foo/bar: created', 'source' => '/Foo/bar'},
    ]
    result = transform(report('logs' => logs))

    assert_equal [{'log' => {'level' => 'notice', 'sources' => {'source' => '/Foo/bar'}, 'messages' => {'message' => 'Foo/bar: created'}}}], result['logs']
  end

  def test_raises_invalid_report_when_host_missing
    assert_raises(Proxy::PuppetApi::ReportFormat12Transformer::InvalidReport) do
      transform(report.tap { |r| r.delete('host') })
    end
  end

  def test_raises_invalid_report_when_time_missing
    assert_raises(Proxy::PuppetApi::ReportFormat12Transformer::InvalidReport) do
      transform(report.tap { |r| r.delete('time') })
    end
  end

  def test_raises_invalid_report_when_time_is_malformed
    assert_raises(Proxy::PuppetApi::ReportFormat12Transformer::InvalidReport) do
      transform(report('time' => 'not-a-time'))
    end
  end
end
