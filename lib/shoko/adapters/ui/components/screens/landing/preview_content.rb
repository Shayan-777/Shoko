# frozen_string_literal: true

require 'time'
require 'shoko/shared/language_directory'
require 'shoko/shared/terminal/text_sanitizer'
require_relative '../../status_bar/palette'
require_relative 'preview'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          module Landing
            # Builds the live preview shown beside the highlighted menu entry.
            # Every preview reads real application state — the shelf, the cache,
            # saved annotations, RSS subscriptions, the active configuration —
            # so the landing screen answers "what's behind this entry?" before
            # it is opened. Disk-backed sources are memoized for a short TTL:
            # the menu redraws on every keypress and previews must never turn
            # cursor movement into file I/O. A failing provider degrades to a
            # quiet placeholder; the landing menu itself must never crash.
            class PreviewContent
              Palette = StatusBar::Palette
              Languages = Shoko::Shared::LanguageDirectory

              CACHE_TTL_SECONDS = 2.0

              BUILDERS = {
                browse: :browse_preview,
                library: :library_preview,
                annotations: :annotations_preview,
                rss_reader: :rss_preview,
                download: :download_preview,
                translator: :translator_preview,
                settings: :settings_preview,
                quit: :quit_preview,
              }.freeze

              SETTINGS_ROWS = [
                ['Theme', :theme],
                ['View Mode', :view_mode],
                ['Line Spacing', :line_spacing],
                ['Paragraph Style', :paragraph_style],
                ['Justify', :justify],
                ['Download Source', :download_source],
                ['Page Numbers', :show_page_numbers],
                ['Inline Images', :kitty_images],
              ].freeze

              TIME_INTERVALS = [
                { max: 3600, div: 60, singular: 'a minute ago', plural: '%d min ago' },
                { max: 86_400, div: 3600, singular: 'an hour ago', plural: '%d hours ago' },
                { max: 604_800, div: 86_400, singular: 'yesterday', plural: '%d days ago' },
                { max: Float::INFINITY, div: 604_800, singular: 'a week ago', plural: '%d weeks ago' },
              ].freeze

              def initialize(dependencies)
                @dependencies = dependencies
                @cache = {}
              end

              def build(key, rows:)
                send(BUILDERS.fetch(key, :quit_preview), rows) || fallback_preview(key)
              # resilient-boundary
              rescue StandardError => e
                swallow_preview_error(e, key)
              end

              private

              # A preview is decoration: when a provider breaks, show the bare
              # card instead of taking the landing menu down with it.
              def swallow_preview_error(_error, key)
                fallback_preview(key)
              end

              def fallback_preview(key)
                Preview.new(
                  title: key.to_s.split('_').map(&:capitalize).join(' '),
                  meta: '',
                  accent_fg: Accents.for(key),
                  lines: [],
                  hint: 'ENTER opens'
                )
              end

              # ----- Browse Library: the live shelf -----

              def browse_preview(rows)
                books = Array(catalog&.entries)
                lines = scanning? ? scan_status_lines : []
                lines += books_lines(books, rows - lines.length)
                Preview.new(
                  title: 'Browse Library',
                  meta: "#{books.length} #{books.length == 1 ? 'book' : 'books'}",
                  accent_fg: Accents.for(:browse),
                  lines: lines,
                  hint: 'ENTER browse the shelf · / search by title'
                )
              end

              def books_lines(books, budget)
                return empty_shelf_lines if books.empty? && !scanning?

                books.first([budget, 0].max).map do |book|
                  PreviewLine.new(
                    left: [[sanitize(book['name']), nil]],
                    right: [[size_label(book['size']), Palette::LANDING_DIM_FG]]
                  )
                end
              end

              def empty_shelf_lines
                [
                  PreviewLine.text('Your shelf is empty.'),
                  PreviewLine.blank,
                  PreviewLine.text('Download Books fetches classics and more,', Palette::LANDING_DIM_FG),
                  PreviewLine.text('or open any file with  shoko <path>.', Palette::LANDING_DIM_FG),
                ]
              end

              def scan_status_lines
                message = sanitize(catalog&.scan_message)
                [
                  PreviewLine.text(message.empty? ? 'Scanning for books…' : message, Accents.for(:browse)),
                  PreviewLine.blank,
                ]
              end

              def scanning?
                catalog&.scan_status == :scanning
              end

              # ----- Library: cached books, most recently touched first -----

              def library_preview(rows)
                items = cached(:library) { Array(catalog&.cached_library_entries) }
                lines = items.first(rows).map { |item| library_line(item) }
                lines = empty_library_lines if items.empty?
                Preview.new(
                  title: 'Library',
                  meta: "#{items.length} cached",
                  accent_fg: Accents.for(:library),
                  lines: lines,
                  hint: 'ENTER open the library · SPACE inspects metadata'
                )
              end

              def library_line(item)
                accessed = relative_time(item[:last_accessed])
                PreviewLine.new(
                  left: [[sanitize(item[:title]).empty? ? 'Untitled' : sanitize(item[:title]), nil]],
                  right: [[accessed, Palette::LANDING_DIM_FG]]
                )
              end

              def empty_library_lines
                [
                  PreviewLine.text('No cached books yet.'),
                  PreviewLine.blank,
                  PreviewLine.text('Books you open are cached here for instant', Palette::LANDING_DIM_FG),
                  PreviewLine.text('reopening, ready before the first keystroke.', Palette::LANDING_DIM_FG),
                ]
              end

              # ----- Annotations: latest notes across every book -----

              def annotations_preview(rows)
                records = cached(:annotations) { flatten_annotations }
                blocks = records.first([rows / 3, 1].max).flat_map { |record| annotation_block(record) }
                blocks = empty_annotations_lines if records.empty?
                Preview.new(
                  title: 'Annotations',
                  meta: annotations_meta(records),
                  accent_fg: Accents.for(:annotations),
                  lines: blocks,
                  hint: 'ENTER review your notes'
                )
              end

              def flatten_annotations
                map = @dependencies&.annotation_service&.list_all || {}
                records = map.flat_map do |path, annotations|
                  Array(annotations).map { |annotation| annotation_record(path, annotation) }
                end
                records.sort_by { |record| record[:created_at].to_s }.reverse
              end

              def annotation_record(path, annotation)
                {
                  book: File.basename(path.to_s, '.*'),
                  text: sanitize(annotation[:text]),
                  note: sanitize(annotation[:note]),
                  created_at: annotation[:created_at],
                }
              end

              def annotation_block(record)
                primary = record[:note].empty? ? record[:text] : record[:note]
                stamp = relative_time(record[:created_at])
                meta = [record[:book], stamp].reject(&:empty?).join(' · ')
                [
                  PreviewLine.text(primary.empty? ? '(empty note)' : primary),
                  PreviewLine.text(meta, Palette::LANDING_DIM_FG),
                  PreviewLine.blank,
                ]
              end

              def annotations_meta(records)
                return 'no notes yet' if records.empty?

                books = records.map { |record| record[:book] }.uniq.length
                "#{records.length} #{records.length == 1 ? 'note' : 'notes'} · " \
                  "#{books} #{books == 1 ? 'book' : 'books'}"
              end

              def empty_annotations_lines
                [
                  PreviewLine.text('No annotations yet.'),
                  PreviewLine.blank,
                  PreviewLine.text('Select a passage in a book and press a', Palette::LANDING_DIM_FG),
                  PreviewLine.text('to keep a note anchored to it.', Palette::LANDING_DIM_FG),
                ]
              end

              # ----- RSS Reader: subscriptions with unread counts -----

              def rss_preview(rows)
                snapshot = cached(:rss) { rss_snapshot }
                feeds = Array(snapshot[:feeds])
                unread = unread_by_feed(Array(snapshot[:articles]))
                lines = feeds.first(rows).map { |feed| rss_line(feed, unread) }
                lines = empty_rss_lines if feeds.empty?
                Preview.new(
                  title: 'RSS Reader',
                  meta: rss_meta(feeds, unread),
                  accent_fg: Accents.for(:rss_reader),
                  lines: lines,
                  hint: 'ENTER read articles · A adds a feed'
                )
              end

              def rss_snapshot
                snapshot = @dependencies&.rss_reader_service&.snapshot
                snapshot.is_a?(Hash) ? snapshot : { feeds: [], articles: [] }
              end

              def unread_by_feed(articles)
                articles.reject(&:read).group_by(&:feed_id).transform_values(&:length)
              end

              def rss_line(feed, unread)
                count = unread.fetch(feed.id, 0)
                marker = if count.positive?
                           [["#{count} unread", Accents.for(:rss_reader)]]
                         else
                           [['read', Palette::LANDING_DIM_FG]]
                         end
                PreviewLine.new(left: [[sanitize(feed.title), nil]], right: marker)
              end

              def rss_meta(feeds, unread)
                total_unread = unread.values.sum
                "#{feeds.length} #{feeds.length == 1 ? 'feed' : 'feeds'} · #{total_unread} unread"
              end

              def empty_rss_lines
                [
                  PreviewLine.text('No feeds yet.'),
                  PreviewLine.blank,
                  PreviewLine.text('Open the reader and press A to subscribe;', Palette::LANDING_DIM_FG),
                  PreviewLine.text('articles are readable right in the menu.', Palette::LANDING_DIM_FG),
                ]
              end

              # ----- Download Books: the active source, radio-style -----

              def download_preview(_rows)
                active = config_value(:download_source, :gutendex).to_sym
                Preview.new(
                  title: 'Download Books',
                  meta: "source: #{active}",
                  accent_fg: Accents.for(:download),
                  lines: download_lines(active),
                  hint: 'ENTER search for books · TAB switches source'
                )
              end

              def download_lines(active)
                [
                  source_line('Gutendex', 'Project Gutenberg classics', active == :gutendex),
                  source_line('Libgen', 'broad catalog via mirrors', active == :libgen),
                  PreviewLine.blank,
                  PreviewLine.text('Downloads land on your shelf automatically.', Palette::LANDING_DIM_FG),
                ]
              end

              def source_line(name, blurb, active)
                marker = active ? ['● ', Accents.for(:download)] : ['○ ', Palette::LANDING_DIM_FG]
                name_fg = active ? Accents.for(:download) : nil
                PreviewLine.new(
                  left: [marker, [name, name_fg], ["   #{blurb}", Palette::LANDING_DIM_FG]],
                  right: []
                )
              end

              # ----- Translator: the configured language pair -----

              def translator_preview(_rows)
                source, target = translator_pair
                Preview.new(
                  title: 'Translator',
                  meta: "#{source} → #{target}",
                  accent_fg: Accents.for(:translator),
                  lines: translator_lines(source, target),
                  hint: 'ENTER open the translator'
                )
              end

              def translator_pair
                reader = @dependencies&.menu_state_reader
                [
                  (reader&.translator_source_lang || Languages::AUTO).to_s,
                  (reader&.translator_target_lang || 'en').to_s,
                ]
              end

              def translator_lines(source, target)
                source_name = source == Languages::AUTO ? Languages::AUTO_NAME : Languages.name_for(source)
                [
                  PreviewLine.new(
                    left: [[source_name, nil], ['  →  ', Accents.for(:translator)], [Languages.name_for(target), nil]],
                    right: []
                  ),
                  PreviewLine.blank,
                  PreviewLine.text('Translates passages via LibreTranslate.', Palette::LANDING_DIM_FG),
                  PreviewLine.text('Also in-book: SHIFT+T while reading.', Palette::LANDING_DIM_FG),
                ]
              end

              # ----- Settings: the live configuration at a glance -----

              def settings_preview(rows)
                Preview.new(
                  title: 'Settings',
                  meta: "theme: #{config_value(:theme, :default)}",
                  accent_fg: Accents.for(:settings),
                  lines: SETTINGS_ROWS.first(rows).map { |label, field| settings_line(label, field) },
                  hint: 'ENTER adjust settings'
                )
              end

              def settings_line(label, field)
                PreviewLine.new(
                  left: [[format('%-17s', label), Palette::LANDING_DIM_FG], [humanize(config_value(field, '—')), nil]],
                  right: []
                )
              end

              # ----- Quit -----

              def quit_preview(_rows = nil)
                Preview.new(
                  title: 'Quit',
                  meta: '',
                  accent_fg: Accents.for(:quit),
                  lines: [
                    PreviewLine.text('Close Shoko.'),
                    PreviewLine.blank,
                    PreviewLine.text('Progress, bookmarks and annotations are', Palette::LANDING_DIM_FG),
                    PreviewLine.text('saved automatically. See you next chapter.', Palette::LANDING_DIM_FG),
                  ],
                  hint: 'ENTER quit'
                )
              end

              # ----- shared plumbing -----

              def catalog
                @dependencies&.catalog_service
              end

              def config_value(field, default)
                snapshot = @dependencies&.config_reader&.load
                value = snapshot.respond_to?(field) ? snapshot.public_send(field) : nil
                value.nil? ? default : value
              end

              def humanize(value)
                return 'On' if value == true
                return 'Off' if value == false

                value.to_s.split('_').map(&:capitalize).join(' ')
              end

              def cached(key)
                now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
                entry = @cache[key]
                return entry[:value] if entry && now - entry[:at] < CACHE_TTL_SECONDS

                value = yield
                @cache[key] = { value: value, at: now }
                value
              end

              def size_label(bytes)
                format('%.1f MB', bytes.to_f / (1024 * 1024))
              end

              def relative_time(iso)
                seconds = elapsed_seconds(iso)
                return '' unless seconds
                return 'just now' if seconds < 60

                interval = TIME_INTERVALS.find { |entry| seconds < entry[:max] }
                value = [seconds / interval[:div], 1].max
                value == 1 ? interval[:singular] : format(interval[:plural], value)
              end

              # Timestamps come from user-editable JSON; an unparseable one
              # only costs the "ago" label, never the preview.
              def elapsed_seconds(iso)
                return nil if iso.to_s.empty?

                (Time.now - Time.parse(iso.to_s)).to_i
              rescue ArgumentError, TypeError => e
                swallow_timestamp_error(e)
              end

              def swallow_timestamp_error(_error)
                nil
              end

              def sanitize(value)
                Shoko::Shared::Terminal::TextSanitizer.sanitize(
                  value.to_s, preserve_newlines: false, preserve_tabs: false
                ).strip
              end
            end
          end
        end
      end
    end
  end
end
