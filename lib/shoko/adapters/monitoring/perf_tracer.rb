# frozen_string_literal: true

require 'fileutils'
require 'time'
require_relative '../../application/ports/outbound/runtime_config'

module Shoko
  module Adapters
    module Monitoring
      # Collects per-open performance timings when profiling is enabled.
      # Instance-based — created by the DI container with configuration.
      class PerfTracer
        SESSION_KEY = :shoko_perf_session
        STAGES = [
          'open.invoke',
          'cache.pipeline',
          'cache.lookup',
          'zip.read',
          'opf.parse',
          'xhtml.normalize',
          'pagination.build',
          'formatting.ensure',
          'page_map.hydrate',
          'render.first_paint.ttfp',
        ].freeze

        attr_reader :profile_path

        def initialize(runtime_config:, profile_path: nil)
          unless runtime_config.is_a?(Shoko::Application::Ports::Outbound::RuntimeConfig)
            raise ArgumentError, 'runtime_config must implement Application::Ports::Outbound::RuntimeConfig'
          end

          normalized_path = profile_path.to_s.strip
          @profile_path = normalized_path.empty? ? nil : normalized_path
          @runtime_config = runtime_config
        end

        def enabled?
          return @enabled unless @enabled.nil?

          @enabled = @runtime_config.debug_perf_enabled? || !@profile_path.nil?
        end

        alias active? enabled?

        def start_open(path)
          return unless enabled?

          session = Session.new(path, profile_path: @profile_path)
          Thread.current[SESSION_KEY] = session
          session
        end

        def current_session
          Thread.current[SESSION_KEY]
        end

        def measure(stage, &)
          session = current_session
          return yield unless session

          session.measure(stage, &)
        end

        def record(stage, duration)
          session = current_session
          session&.record(stage, duration)
        end

        def complete(open_type:, total_duration: nil)
          session = current_session
          return unless session

          session.add_metadata(open_type: open_type)
          session.record('open.invoke', total_duration) if total_duration
          session.open_type = open_type
          session.emit
        ensure
          clear_session
        end

        def clear_session
          Thread.current[SESSION_KEY] = nil
        end

        def cancel
          clear_session
        end

        def annotate(metadata)
          session = current_session
          session&.add_metadata(metadata)
        end

        # Internal per-open timing tracker.
        class Session
          attr_accessor :open_type

          def initialize(path, profile_path: nil)
            @path = path
            @profile_path = profile_path
            @started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            @timings = Hash.new(0.0)
            @open_type = 'unknown'
            @metadata = { book: path }
          end

          def measure(stage)
            start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            yield
          ensure
            duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
            @timings[stage] += duration if duration
          end

          def record(stage, duration)
            @timings[stage] += duration.to_f
          end

          def add_metadata(hash)
            return unless hash.is_a?(Hash)

            hash.each do |k, v|
              @metadata[k.to_sym] = v unless v.nil?
            end
          end

          def emit
            total = @timings['open.invoke']
            total = elapsed unless total.positive?
            output = [metadata_line, "stages #{stage_fields(total).join(' ')}", '---'].join("\n")
            write_output(output)
          end

          private

          def timestamp
            Time.now.utc.iso8601
          end

          def open_type_label
            label = @open_type.to_s.strip
            label.empty? ? 'unknown' : label
          end

          def elapsed
            Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started_at
          end

          def format_ms(seconds)
            ms = (seconds.to_f * 1000.0)
            "#{ms.round}ms"
          end

          def metadata_line
            [
              "time=#{timestamp}",
              "book=#{@metadata[:book]}",
              ("cache_hit=#{@metadata[:cache_hit]}" if @metadata.key?(:cache_hit)),
              ("pagination_cache=#{@metadata[:pagination_cache]}" if @metadata.key?(:pagination_cache)),
              ("chapters=#{@metadata[:chapters]}" if @metadata.key?(:chapters)),
              "open_type=#{open_type_label}",
            ].compact.join(' ')
          end

          def stage_fields(total)
            PerfTracer::STAGES.map do |stage|
              duration = stage == 'open.invoke' ? total : @timings[stage]
              "#{stage}=#{format_ms(duration)}"
            end
          end

          def write_output(text)
            if @profile_path && !@profile_path.to_s.strip.empty?
              begin
                FileUtils.mkdir_p(File.dirname(@profile_path))
                File.open(@profile_path, 'a') { |f| f.puts(text) }
                return
              rescue SystemCallError, IOError
                # profile path unwritable (permissions, missing dir) — fall
                # through to stdout rather than losing the trace
              end
            end
            $stdout.puts(text)
          end
        end
      end
    end
  end
end
