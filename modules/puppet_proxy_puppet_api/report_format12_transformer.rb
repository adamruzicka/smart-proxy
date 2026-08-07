require 'time'

module Proxy::PuppetApi
  # Turns a Puppet report_format 12 report (Puppet::Transaction::Report#to_data_hash,
  # per Puppet's api/schemas/report.json) into the config_report shape Foreman's
  # /api/config_reports expects. Ported from puppet-puppetserver_foreman's report.rb,
  # which builds the same shape from live Puppet::Transaction::Report objects instead.
  class ReportFormat12Transformer
    class InvalidReport < StandardError; end

    METRIC = %w[applied restarted failed failed_restarts skipped pending].freeze
    FINISHED_CATALOG_RUN = /^Finished catalog run in \d+.\d+ seconds$/

    def self.transform(report)
      new(report).transform
    end

    def initialize(report)
      @report = report
    end

    def transform
      {
        'host' => host,
        'reported_at' => reported_at,
        'status' => status_counts,
        'metrics' => flattened_metrics,
        'logs' => log_entries,
      }
    end

    private

    attr_reader :report

    def host
      report.fetch('host') { raise InvalidReport, "report is missing 'host'" }
    end

    def reported_at
      time = report.fetch('time') { raise InvalidReport, "report is missing 'time'" }
      Time.parse(time).utc.strftime('%Y-%m-%d %H:%M:%S UTC')
    rescue ArgumentError, TypeError => e
      raise InvalidReport, "report has an invalid 'time': #{e.message}"
    end

    def logs
      report['logs'] || []
    end

    def flattened_metrics
      (report['metrics'] || {}).transform_values do |category|
        (category['values'] || []).to_h { |name, _label, value| [name, value] }
      end
    end

    def status_counts
      metrics = flattened_metrics
      counts = METRIC.each_with_object({}) do |name, result|
        category, key = metric_source(name)
        result[name] = metrics.dig(category, key) || 0
      end

      if counts['skipped'] > 0 && (counts.values.sum - counts['skipped'] == logs.size)
        counts['skipped'] = 0
      end
      counts['failed'] += 1 if report['status'] == 'failed'
      counts['failed'] += logs.count { |log| log['source'].to_s =~ /Puppet$/ && log['level'].to_s == 'err' }

      counts
    end

    def metric_source(name)
      case name
      when 'applied'
        ['changes', 'total']
      when 'failed_restarts'
        ['resources', 'failed_to_restart']
      when 'pending'
        ['events', 'noop']
      else
        ['resources', name]
      end
    end

    def log_entries
      logs.each_with_object([]) do |log, entries|
        next if log['level'] == 'debug'
        next if log['message'].to_s =~ FINISHED_CATALOG_RUN

        entries << {
          'log' => {
            'level' => log['level'],
            'sources' => {'source' => log['source']},
            'messages' => {'message' => log['message']},
          },
        }
      end
    end
  end
end
