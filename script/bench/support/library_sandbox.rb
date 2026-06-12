# frozen_string_literal: true

require 'English'
require 'fileutils'
require 'json'
require 'rbconfig'

module ShokoBench
  # Builds an isolated HOME/XDG environment with a known set of books
  # imported into the Shoko cache, so end-to-end benchmarks never touch the
  # user's real config or cache and are reproducible run to run.
  class LibrarySandbox
    APP_ROOT = File.expand_path('../../..', __dir__)

    # Mirrors a realistic mixed library: epub/fb2/rtf with many small
    # chapters, plus the formats whose imports yield huge chapters (PDF,
    # Kindle) — those are the worst case for background repagination because
    # any cooperative yielding can only happen between chapters.
    DEFAULT_BOOK_GLOBS = [
      'Class Struggle*.epub',
      'Worte des Vortsitzenden*.epub',
      'Wut und Liebe*.epub',
      'niccolo-machiavelli*.epub',
      'Ósmann*.epub',
      'Империализм*.epub',
      'Как устроена экономика*.fb2',
      'Pride and Prejudice*.mobi',
      'Pride And Prejudice*.rtf',
      'The Decline of the West*.pdf',
      'Technofeudalism*.pdf',
      'Revolutionary Suicide*.pdf',
    ].freeze

    BASE_CONFIG = {
      'schema_version' => 2,
      'view_mode' => 'single',
      'line_spacing' => 'normal',
      'download_source' => 'gutendex',
      'page_numbering_mode' => 'dynamic',
      'theme' => 'default',
      'show_page_numbers' => true,
      'highlight_quotes' => true,
      'highlight_keywords' => false,
      'prefetch_pages' => 20,
      'kitty_images' => false,
      'prepaginate_on_resize' => false,
      'last_paginated_size' => nil,
    }.freeze

    attr_reader :root, :books_dir, :import_timings

    def initialize(root:, book_globs: DEFAULT_BOOK_GLOBS, log: $stderr)
      @root = root
      @books_dir = File.join(root, 'books')
      @log = log
      @book_globs = book_globs
      @import_timings = []
    end

    def env
      {
        'HOME' => @root,
        'XDG_CONFIG_HOME' => File.join(@root, '.config'),
        'XDG_CACHE_HOME' => File.join(@root, '.cache'),
        'SHOKO_BOOK_SCAN_DIRS' => @books_dir,
        'TERM' => 'xterm-256color',
        'COLORTERM' => 'truecolor',
      }
    end

    def config_path
      File.join(env['XDG_CONFIG_HOME'], 'shoko', 'config.json')
    end

    def import_timings_path
      File.join(@root, 'import_timings.json')
    end

    SNAPSHOT_DIRS = %w[.cache .config].freeze

    def snapshot_dir
      File.join(@root, 'snapshot')
    end

    def prepared?
      File.exist?(config_path) && Dir.exist?(@books_dir) && !Dir.empty?(@books_dir)
    end

    def prepare!
      FileUtils.mkdir_p([@books_dir, File.dirname(config_path)])
      copy_books
      write_config
      import_books
      File.write(import_timings_path, JSON.generate(@import_timings))
      self
    end

    def load_import_timings
      @import_timings = JSON.parse(File.read(import_timings_path)) if File.exist?(import_timings_path)
      @import_timings
    end

    # Snapshot/restore of the mutable app state (.cache + .config) so every
    # measured phase starts from the identical post-prewarm state — without
    # this, the first completed warmup would leave page caches behind and
    # turn every later "busy" run into a cache-hit no-op.
    def snapshot!
      FileUtils.rm_rf(snapshot_dir)
      FileUtils.mkdir_p(snapshot_dir)
      SNAPSHOT_DIRS.each { |dir| FileUtils.cp_r(File.join(@root, dir), snapshot_dir) }
    end

    def snapshot?
      Dir.exist?(snapshot_dir)
    end

    def restore!
      raise 'no snapshot to restore' unless snapshot?

      SNAPSHOT_DIRS.each do |dir|
        FileUtils.rm_rf(File.join(@root, dir))
        FileUtils.cp_r(File.join(snapshot_dir, File.basename(dir)), @root)
      end
    end

    # Rewrites only the pagination-warmup knobs between benchmark phases.
    def configure_warmup(enabled:, last_paginated_size:)
      config = JSON.parse(File.read(config_path))
      config['prepaginate_on_resize'] = enabled
      config['last_paginated_size'] = last_paginated_size
      File.write(config_path, JSON.pretty_generate(config))
    end

    def current_config
      JSON.parse(File.read(config_path))
    end

    def shoko_argv
      [RbConfig.ruby, File.join(APP_ROOT, 'bin', 'shoko')]
    end

    private

    def copy_books
      sources = @book_globs.flat_map { |glob| Dir.glob(File.join(APP_ROOT, 'testbooks', glob)) }
      raise "no testbooks matched #{@book_globs.inspect}" if sources.empty?

      sources.each { |source| FileUtils.cp(source, @books_dir) }
      @log.puts "sandbox: copied #{sources.length} books"
    end

    def write_config
      File.write(config_path, JSON.pretty_generate(BASE_CONFIG))
    end

    def import_books
      importer = File.join(APP_ROOT, 'script', 'bench', 'support', 'import_books.rb')
      lines = []
      IO.popen(env, [RbConfig.ruby, importer, @books_dir], err: %i[child out]) do |io|
        io.each_line do |line|
          lines << line
          @log.puts "sandbox: #{line.strip}" if line.include?('"event"')
        end
      end
      raise "book import failed:\n#{lines.join}" unless $CHILD_STATUS.success?

      @import_timings = lines.filter_map do |line|
        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end
    end
  end
end
