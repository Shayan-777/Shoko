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
                return unless catalog_available_for_setup?

                show_download_lookup_status(source, target)
                entry = catalog_entry_for_setup(source, target)
                return unless entry

                name = catalog_entry_name(entry, source, target)
                download_catalog_entry(entry, name, source, target)
                finalize_download_setup(name, source, target)
              rescue Shoko::Error => e
                setup_error("Download failed: #{e.message}", stage: :prompt_target)
              end

              def find_catalog_entry(remote_items, source:, target:)
                Array(remote_items).find do |item|
                  src = item[:source]
                  tgt = item[:target]
                  normalize_dictionary_language(src) == source &&
                    normalize_dictionary_language(tgt) == target
                end
              end

              def dictionary_storage_path
                @dictionary_storage&.ensure_databases_path(@config_reader.dictionary_path)
              end

              def monotonic_now
                @clock.monotonic_now
              end

              def catalog_available_for_setup?
                return true if @dictionary_catalog_service

                setup_error('Dictionary catalog unavailable.', stage: :prompt_target)
                false
              end

              def show_download_lookup_status(source, target)
                update_download_setup_popup(
                  source: source,
                  target: target,
                  status: "Looking for #{source}-#{target} dataset...",
                  progress: 0.0,
                  prompt: '',
                  input_value: ''
                )
              end

              def catalog_entry_for_setup(source, target)
                remote_items = @dictionary_catalog_service.list_remote
                entry = find_catalog_entry(remote_items, source: source, target: target)
                return entry if entry

                setup_error("No dictionary dataset found for #{source}-#{target}.", stage: :prompt_target)
                nil
              end

              def catalog_entry_name(entry, source, target)
                entry[:name] || "#{source}-#{target}.sqlite3"
              end

              def download_catalog_entry(entry, name, source, target)
                last_draw = monotonic_now
                @dictionary_catalog_service.download(entry, dictionary_storage_path) do |done, total|
                  progress, message = download_progress(done, total, name)
                  update_download_setup_popup(
                    source: source,
                    target: target,
                    status: message,
                    progress: progress,
                    redraw: false
                  )
                  last_draw = redraw_download_screen(progress, last_draw)
                end
              end

              def download_progress(done, total, name)
                progress = total.to_i.positive? ? done.to_f / total : 0.0
                percent = total.to_i.positive? ? (progress * 100).round : nil
                message = percent ? "Downloading #{name}... #{percent}%" : "Downloading #{name}..."
                [progress, message]
              end

              def redraw_download_screen(progress, last_draw)
                now = monotonic_now
                return last_draw if (now - last_draw) < 0.08 && progress < 1.0

                draw_dictionary_screen
                now
              end

              def finalize_download_setup(name, source, target)
                update_download_setup_popup(
                  source: source,
                  target: target,
                  status: "Installed #{name}",
                  status_level: :success,
                  progress: 1.0
                )
                complete_lookup_after_setup(source, target)
              end

              def update_download_setup_popup(source:, target:, status:, progress:, status_level: nil,
                                              redraw: true, prompt: nil, input_value: nil)
                update_setup_popup(
                  stage: :downloading,
                  source_lang: source,
                  target_lang: target,
                  prompt: prompt,
                  input_value: input_value,
                  status: status,
                  status_level: status_level,
                  progress: progress,
                  redraw: redraw
                )
              end
            end
          end
        end
      end
    end
  end
end
