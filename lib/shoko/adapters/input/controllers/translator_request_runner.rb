# frozen_string_literal: true

require 'shoko/core/services/language_directory'

module Shoko
  module Adapters
    module Input
      module Controllers
        # Owns request generations and the worker/UI-thread translation handoff.
        class TranslatorRequestRunner
          Request = Data.define(:text, :source_lang, :target_lang, :announce, :generation)

          def initialize(reader_state:, translation_service:, ui_session:, async_relay:, on_message:)
            @reader_state = reader_state
            @translation_service = translation_service
            @ui_session = ui_session
            @async_relay = async_relay
            @on_message = on_message
            @generation = 0
          end

          def submit(text, announce: false)
            request = build_request(text, announce)
            @on_message.call('Translating…', 2)
            submitted = @async_relay.submit { perform(request) }
            @on_message.call('Translation worker is unavailable', 3) unless submitted
            submitted
          end

          def invalidate = @generation += 1

          private

          def build_request(text, announce)
            @generation += 1
            Request.new(
              text: text,
              source_lang: @reader_state.translator_source_lang.to_s,
              target_lang: @reader_state.translator_target_lang.to_s,
              announce: announce,
              generation: @generation
            )
          end

          def perform(request)
            result = @translation_service.translate(
              request.text, source_lang: request.source_lang, target_lang: request.target_lang
            )
            @async_relay.enqueue do
              next unless current_context?(request)

              @ui_session.apply_result(result, query: request.text)
              announce(result) if request.announce
            end
          end

          def current_context?(request)
            request.generation == @generation && @ui_session.visible? &&
              @reader_state.translator_query.to_s.strip == request.text.to_s.strip &&
              @reader_state.translator_source_lang.to_s == request.source_lang &&
              @reader_state.translator_target_lang.to_s == request.target_lang
          end

          def announce(result)
            if result.error?
              detail = result.error_message.to_s.strip
              @on_message.call(detail.empty? ? 'Translation failed' : "Translation failed — #{detail}", 3)
            else
              name = Shoko::Core::Services::LanguageDirectory.name_for(@reader_state.translator_target_lang)
              @on_message.call("Translated to #{name}", 2)
            end
          end
        end
      end
    end
  end
end
