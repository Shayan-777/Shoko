# frozen_string_literal: true

require 'json'
require 'open3'
require_relative '../../shared/errors'
require_relative 'engine_locator'

module Shoko
  module Adapters
    module Translation
      # Owns the shoko-translate child process: spawns it lazily, speaks the
      # JSON-lines protocol, and recovers from crashes by respawning on the
      # next request (loaded models are re-sent on demand via ensure_loaded).
      class EngineClient
        TranslationResponse = Data.define(:text, :finish_reason) do
          def truncated? = finish_reason.to_s == 'max_tokens'
        end

        # Engine process failure surfaced to the local translation adapter.
        class EngineError < Shoko::Error
          attr_reader :code

          def initialize(message, code: :engine_failed)
            super(message)
            @code = code
          end
        end

        READ_TIMEOUT_SECONDS = 30
        SHUTDOWN_GRACE_SECONDS = 0.5
        MAX_RESPONSE_LINE_BYTES = 2 * 1024 * 1024
        MISSING_ENGINE_MESSAGE =
          "Translation engine is not built (run: #{EngineLocator::BUILD_HINT})".freeze

        def initialize(engine_path: nil, logger: nil)
          @engine_path = engine_path
          @logger = logger
          @engine_input = nil
          @engine_output = nil
          @wait_thread = nil
          @loaded_slots = {}
          @mutex = Mutex.new
        end

        def ensure_loaded(slot, model_path:, vocab_path:)
          @mutex.synchronize do
            response = request_locked(
              op: 'load', slot: slot, model: model_path, vocab: vocab_path
            )
            unless response[:evicted].nil? || response[:evicted].is_a?(String)
              stop_locked
              raise EngineError.new('Malformed load response from translation engine',
                                    code: :engine_protocol)
            end
            @loaded_slots.delete(response[:evicted].to_s) if response[:evicted]
            @loaded_slots[slot] = [model_path.to_s, vocab_path.to_s].freeze
          end
        end

        def translate(slot, text)
          translate_with_metadata(slot, text).text
        end

        def translate_with_metadata(slot, text)
          @mutex.synchronize do
            raise EngineError.new('Model is not loaded', code: :engine_failed) unless @loaded_slots[slot]

            response = request_locked(op: 'translate', slot: slot, text: text)
            unless response[:text].is_a?(String) &&
                   %w[eos max_tokens].include?(response.fetch(:finish_reason, 'eos'))
              stop_locked
              raise EngineError.new('Malformed translation response from translation engine',
                                    code: :engine_protocol)
            end
            TranslationResponse.new(
              text: response[:text],
              finish_reason: response.fetch(:finish_reason, 'eos')
            )
          end
        end

        def unload(slot)
          @mutex.synchronize do
            request_locked(op: 'unload', slot: slot) if alive_locked?
            @loaded_slots.delete(slot)
          end
        end

        def running?
          @mutex.synchronize { alive_locked? }
        end

        def shutdown
          @mutex.synchronize { stop_locked }
        end

        private

        def alive_locked?
          @wait_thread&.alive? == true &&
            !@engine_input.closed? && !@engine_output.closed?
        end

        def request_locked(payload)
          start_locked unless alive_locked?
          @engine_input.write(JSON.generate(payload))
          @engine_input.write("\n")
          @engine_input.flush
          parse_response(read_line_with_timeout)
        rescue EngineError => e
          stop_locked if %i[engine_timeout engine_protocol].include?(e.code)
          raise
        rescue IOError, SystemCallError => e
          handle_engine_death(e)
        end

        def start_locked
          path = @engine_path || EngineLocator.path
          raise EngineError.new(MISSING_ENGINE_MESSAGE, code: :engine_missing) unless path && File.executable?(path)

          @loaded_slots = {}
          @engine_input, @engine_output, @wait_thread = Open3.popen2(path, err: File::NULL)
          @logger&.debug('translator.engine_started', pid: @wait_thread.pid)
        rescue SystemCallError => e
          clear_process_handles
          raise EngineError.new("Cannot start translation engine: #{e.message}", code: :engine_missing)
        end

        def read_line_with_timeout
          ready = @engine_output.wait_readable(READ_TIMEOUT_SECONDS)
          raise EngineError.new('Translation engine timed out', code: :engine_timeout) unless ready

          line = @engine_output.gets(MAX_RESPONSE_LINE_BYTES + 1)
          raise IOError, 'engine closed its output' if line.nil?
          unless line.end_with?("\n")
            raise EngineError.new('Oversized or incomplete response from translation engine',
                                  code: :engine_protocol)
          end

          line
        end

        def parse_response(line)
          response = JSON.parse(line, symbolize_names: true)
          unless response.is_a?(Hash) && [true, false].include?(response[:ok])
            raise EngineError.new('Malformed response from translation engine', code: :engine_protocol)
          end
          return response if response[:ok] == true

          code = response[:code].to_s.strip
          code = 'engine_failed' if code.empty?
          raise EngineError.new(response[:error].to_s, code: code.to_sym)
        rescue JSON::ParserError
          raise EngineError.new('Malformed response from translation engine', code: :engine_protocol)
        end

        def handle_engine_death(error)
          @logger&.error('translator.engine_died', error: error.class.name, message: error.message)
          stop_locked
          raise EngineError.new('Translation engine stopped unexpectedly', code: :engine_died)
        end

        def stop_locked
          @loaded_slots = {}
          input = @engine_input
          output = @engine_output
          wait_thread = @wait_thread
          clear_process_handles
          close_pipe(input)
          terminate_process(wait_thread)
          close_pipe(output)
        end

        def clear_process_handles
          @engine_input = nil
          @engine_output = nil
          @wait_thread = nil
        end

        def close_pipe(pipe)
          pipe&.close unless pipe&.closed?
        rescue IOError => e
          swallow_pipe_close_error(e)
        end

        def swallow_pipe_close_error(error)
          @logger&.debug('translator.engine_pipe_already_closed', error: error.class.name)
        end

        def terminate_process(wait_thread)
          return unless wait_thread
          return if wait_thread.join(0)

          pid = wait_thread.pid
          signal_process('TERM', pid)
          return if wait_thread.join(SHUTDOWN_GRACE_SECONDS)

          signal_process('KILL', pid)
          wait_thread.join
        end

        def signal_process(signal, pid)
          Process.kill(signal, pid)
        rescue Errno::ESRCH => e
          @logger&.debug('translator.engine_already_exited', pid: pid, error: e.class.name)
        end
      end
    end
  end
end
