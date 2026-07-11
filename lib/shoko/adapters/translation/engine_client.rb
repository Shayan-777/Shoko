# frozen_string_literal: true

require 'json'
require_relative '../../shared/errors'
require_relative 'engine_locator'

module Shoko
  module Adapters
    module Translation
      # Owns the shoko-translate child process: spawns it lazily, speaks the
      # JSON-lines protocol, and recovers from crashes by respawning on the
      # next request (loaded models are re-sent on demand via ensure_loaded).
      class EngineClient
        # Engine process failure surfaced to the local translation adapter.
        class EngineError < Shoko::Error
          attr_reader :code

          def initialize(message, code: :engine_failed)
            super(message)
            @code = code
          end
        end

        READ_TIMEOUT_SECONDS = 30
        MISSING_ENGINE_MESSAGE =
          "Translation engine is not built (run: #{EngineLocator::BUILD_HINT})".freeze

        def initialize(engine_path: nil, logger: nil)
          @engine_path = engine_path
          @logger = logger
          @io = nil
          @loaded_slots = {}
          @mutex = Mutex.new
        end

        def ensure_loaded(slot, model_path:, vocab_path:)
          @mutex.synchronize do
            next if @loaded_slots[slot] && alive_locked?

            response = request_locked(
              op: 'load', slot: slot, model: model_path, vocab: vocab_path
            )
            @loaded_slots[slot] = true if response
          end
        end

        def translate(slot, text)
          @mutex.synchronize do
            raise EngineError.new('Model is not loaded', code: :engine_failed) unless @loaded_slots[slot]

            response = request_locked(op: 'translate', slot: slot, text: text)
            response.fetch(:text, '')
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
          !@io.nil? && !@io.closed?
        end

        def request_locked(payload)
          start_locked unless alive_locked?
          @io.write(JSON.generate(payload))
          @io.write("\n")
          @io.flush
          parse_response(read_line_with_timeout)
        rescue IOError, SystemCallError => e
          handle_engine_death(e)
        end

        def start_locked
          path = @engine_path || EngineLocator.path
          raise EngineError.new(MISSING_ENGINE_MESSAGE, code: :engine_missing) unless path && File.executable?(path)

          @loaded_slots = {}
          @io = IO.popen([path], 'r+', err: File::NULL)
          @logger&.debug('translator.engine_started', pid: @io.pid)
        rescue SystemCallError => e
          @io = nil
          raise EngineError.new("Cannot start translation engine: #{e.message}", code: :engine_missing)
        end

        def read_line_with_timeout
          ready = @io.wait_readable(READ_TIMEOUT_SECONDS)
          raise EngineError.new('Translation engine timed out', code: :engine_failed) unless ready

          line = @io.gets
          raise IOError, 'engine closed its output' if line.nil?

          line
        end

        def parse_response(line)
          response = JSON.parse(line, symbolize_names: true)
          return response if response[:ok]

          raise EngineError.new(response[:error].to_s, code: :engine_failed)
        rescue JSON::ParserError
          raise EngineError.new('Malformed response from translation engine', code: :engine_failed)
        end

        def handle_engine_death(error)
          @logger&.error('translator.engine_died', error: error.class.name, message: error.message)
          stop_locked
          raise EngineError.new('Translation engine stopped unexpectedly', code: :engine_died)
        end

        def stop_locked
          @loaded_slots = {}
          return if @io.nil?

          io = @io
          @io = nil
          pid = io.pid
          io.close unless io.closed?
          reap(pid)
        end

        def reap(pid)
          Process.kill('TERM', pid)
          Process.detach(pid)
        rescue Errno::ESRCH, Errno::ECHILD => e
          record_already_reaped(pid, e)
        end

        # The engine exiting before the TERM lands is the outcome reaping
        # wants; nothing is left to clean up.
        def record_already_reaped(pid, error)
          @logger&.debug('translator.engine_already_exited', pid: pid, error: error.class.name)
        end
      end
    end
  end
end
