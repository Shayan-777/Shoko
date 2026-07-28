# frozen_string_literal: true

require_relative '../base_adapter'
require_relative '../../core/models/translation_language'
require_relative '../../core/models/translation_result'
require_relative '../../application/ports/outbound/translation_repository'
require_relative '../../shared/language_directory'
require_relative 'engine_client'
require_relative 'model_store'
require_relative 'sentence_splitter'

module Shoko
  module Adapters
    module Translation
      # On-device translation backend running Firefox translation models
      # through the bundled shoko-translate engine. Language coverage comes
      # from the packs installed in the model store; pairs without a direct
      # model are routed through English (the same pivot Firefox uses).
      class LocalTranslateAdapter < Shoko::Adapters::BaseAdapter
        include Shoko::Application::Ports::Outbound::TranslationRepository

        PIVOT_LANG = 'en'
        AUTO = Shoko::Shared::LanguageDirectory::AUTO

        def initialize(engine_client:, model_store:, logger: nil)
          super(logger: logger)
          @engine = engine_client
          @model_store = model_store
        end

        def available_languages
          packs = @model_store.installed_packs
          targets = reachable_targets(packs)
          codes = (packs.map(&:from) + packs.map(&:to)).uniq
          codes.map { |code| build_language(code, targets[code] || []) }
               .sort_by { |language| language.name.downcase }
        end

        def translate(text, source_lang:, target_lang:)
          source = resolve_source(source_lang.to_s, target_lang.to_s)
          target = target_lang.to_s
          route = resolve_route(source, target)
          translated, finish_reason = translate_segments(normalize(text), route)
          Shoko::Core::Models::TranslationResult.new(
            query: text,
            translated_text: translated,
            source_lang: source,
            target_lang: target,
            detected_source_lang: nil,
            route: route.flat_map { |pack| [pack.from, pack.to] }.uniq,
            finish_reason: finish_reason
          )
        rescue EngineClient::EngineError => e
          raise RepositoryError.new(e.message, code: e.code)
        end

        private

        # --- routing ---------------------------------------------------------

        def resolve_source(source, _target)
          return source unless source.empty? || source == AUTO

          raise RepositoryError.new(
            'On-device translation requires an explicit source language.',
            code: :source_required
          )
        end

        def resolve_route(source, target)
          if source == target
            raise RepositoryError.new('Source and target languages are the same.', code: :invalid_request)
          end

          direct = @model_store.find(source, target)
          return [direct] if direct

          hop_in = @model_store.find(source, PIVOT_LANG)
          hop_out = @model_store.find(PIVOT_LANG, target)
          return [hop_in, hop_out] if hop_in && hop_out

          raise RepositoryError.new(
            "Language pack #{source} -> #{target} is not installed.",
            code: :model_missing
          )
        end

        def route_exists?(source, target)
          return true if @model_store.installed?(source, target)

          @model_store.installed?(source, PIVOT_LANG) &&
            @model_store.installed?(PIVOT_LANG, target)
        end

        def reachable_targets(packs)
          direct = Hash.new { |hash, key| hash[key] = [] }
          packs.each { |pack| direct[pack.from] << pack.to }
          direct.transform_values do |targets|
            extended = targets.dup
            extended |= direct[PIVOT_LANG] - [PIVOT_LANG] if targets.include?(PIVOT_LANG)
            extended.uniq.sort
          end
        end

        def build_language(code, targets)
          Shoko::Core::Models::TranslationLanguage.new(
            code: code,
            name: Shoko::Shared::LanguageDirectory.name_for(code),
            targets: targets
          )
        end

        # --- translation ------------------------------------------------------

        def normalize(text)
          text.to_s.unicode_normalize(:nfkc)
        end

        def translate_segments(text, route)
          output = +''
          finish_reason = 'eos'
          SentenceSplitter.segments(text).each do |segment, separator|
            current = segment
            route.each do |pack|
              response = engine_translate(pack, current)
              current = response.text
              finish_reason = 'max_tokens' if response.truncated?
            end
            output << current
            output << separator
          end
          [output, finish_reason]
        end

        def engine_translate(pack, text)
          return text if text.strip.empty?

          core, leading, trailing = extract_whitespace(text)
          response = invoke_engine(pack, core)
          preserve_whitespace(response, leading, trailing)
        rescue EngineClient::EngineError => e
          raise unless %i[engine_died model_not_loaded engine_timeout engine_protocol].include?(e.code)

          # The engine respawns lazily; retry the segment once.
          response = invoke_engine(pack, core)
          preserve_whitespace(response, leading, trailing)
        end

        def invoke_engine(pack, text)
          slot = "#{pack.from}-#{pack.to}"
          @engine.ensure_loaded(slot, model_path: pack.model_path, vocab_path: pack.vocab_path)
          @engine.translate_with_metadata(slot, collapse_spaces(text))
        end

        def extract_whitespace(text)
          leading = text[/\A\s*/].to_s
          trailing = text[/\s*\z/].to_s
          core = text[leading.length...(text.length - trailing.length)].to_s
          [core, leading, trailing]
        end

        def preserve_whitespace(response, leading, trailing)
          response.with(text: "#{leading}#{response.text}#{trailing}")
        end

        def collapse_spaces(text)
          text.gsub(/\s+/, ' ').strip
        end
      end
    end
  end
end
