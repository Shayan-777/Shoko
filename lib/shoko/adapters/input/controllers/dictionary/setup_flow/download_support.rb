# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Dictionary
          module SetupFlow
            # Catalog lookup and download/installation behavior for setup flow.
            module DownloadSupport
              private

              def download_pair_for_setup(source, target)
                unless @dictionary_catalog_service
                  setup_error('Dictionary catalog unavailable.', stage: :prompt_target)
                  return
                end

                update_setup_popup(
                  stage: :downloading,
                  source_lang: source,
                  target_lang: target,
                  prompt: '',
                  input_value: '',
                  status: "Looking for #{source}-#{target} dataset...",
                  status_level: nil,
                  progress: 0.0
                )

                remote_items = @dictionary_catalog_service.list_remote
                entry = find_catalog_entry(remote_items, source: source, target: target)
                unless entry
                  setup_error("No dictionary dataset found for #{source}-#{target}.", stage: :prompt_target)
                  return
                end

                name = entry[:name] || entry['name'] || "#{source}-#{target}.sqlite3"
                destination = dictionary_storage_path
                last_draw = monotonic_now
                @dictionary_catalog_service.download(entry, destination) do |done, total|
                  progress = total.to_i.positive? ? done.to_f / total : 0.0
                  percent = total.to_i.positive? ? (progress * 100).round : nil
                  message = percent ? "Downloading #{name}... #{percent}%" : "Downloading #{name}..."
                  update_setup_popup(
                    stage: :downloading,
                    source_lang: source,
                    target_lang: target,
                    status: message,
                    status_level: nil,
                    progress: progress,
                    redraw: false
                  )
                  now = monotonic_now
                  next if (now - last_draw) < 0.08 && progress < 1.0

                  draw_dictionary_screen
                  last_draw = now
                end

                update_setup_popup(
                  stage: :downloading,
                  source_lang: source,
                  target_lang: target,
                  status: "Installed #{name}",
                  status_level: :success,
                  progress: 1.0
                )
                complete_lookup_after_setup(source, target)
              rescue Shoko::Error => e
                setup_error("Download failed: #{e.message}", stage: :prompt_target)
              end

              def find_catalog_entry(remote_items, source:, target:)
                Array(remote_items).find do |item|
                  src = item[:source] || item['source']
                  tgt = item[:target] || item['target']
                  normalize_dictionary_language(src) == source &&
                    normalize_dictionary_language(tgt) == target
                end
              end

              def dictionary_storage_path
                @dictionary_storage&.ensure_databases_path(@config_reader.dictionary_path)
              rescue Shoko::Error
                nil
              end

              def monotonic_now
                @clock.monotonic_now
              end
            end
          end
        end
      end
    end
  end
end
