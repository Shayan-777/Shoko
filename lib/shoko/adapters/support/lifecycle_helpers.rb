# frozen_string_literal: true

require_relative '../../shared/text_sanitizer'

module Shoko
  module Adapters
    module Support
      # Shared lifecycle helpers used by importers and cache pipeline stages.
      module LifecycleHelpers
        private

        def report(message, progress: nil)
          reporter = @progress_reporter
          return unless reporter
          return if message.nil? || message.to_s.strip.empty?

          reporter.update_status(message: message, progress: progress)
        rescue Shoko::Error
          raise
        end

        def instrument(label, &)
          instrumentation = @instrumentation
          if instrumentation
            instrumentation.measure(label, &)
          else
            yield
          end
        end

        def fallback_title_from_path(path, strip_suffixes: [], trim_parenthetical: false, &sanitizer)
          base = File.basename(path.to_s)
          stripped = strip_compound_suffix(base, strip_suffixes)
          stripped = File.basename(stripped, File.extname(stripped)) if stripped == base
          stripped = stripped.tr('_', ' ').strip
          stripped = trim_parenthetical_suffix(stripped) if trim_parenthetical
          sanitize_title_text(stripped, &sanitizer)
        rescue Shoko::Error
          base.to_s
        end

        def strip_compound_suffix(value, suffixes)
          text = value.to_s
          Array(suffixes).each do |suffix|
            normalized = suffix.to_s
            next if normalized.empty?

            if text.downcase.end_with?(normalized.downcase)
              return text[0...-normalized.length]
            end
          end
          text
        end

        def trim_parenthetical_suffix(text)
          matched = text.to_s.match(/\A(.+?)\s*\(.*\)\s*\z/)
          matched ? matched[1].strip : text
        end

        def sanitize_title_text(text)
          value = block_given? ? yield(text.to_s) : Shoko::Shared::TextSanitizer.sanitize(
            text.to_s,
            preserve_newlines: false,
            preserve_tabs: false
          )
          value.to_s
        rescue Shoko::Error
          text.to_s
        end
      end
    end
  end
end
