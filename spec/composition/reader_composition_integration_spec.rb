# frozen_string_literal: true

require 'open3'
require 'spec_helper'
require 'fileutils'
require 'tmpdir'

# Builds the FULL reader controller graph through the composition root against
# a real minimal EPUB — in a fresh process under PLAIN boot (no test-mode eager
# requires), exactly like production. Until this spec existed, the
# overlay/controller assembly only ever ran in production: a missing require or
# a privately-defined composition hook crashed every book open while the whole
# suite stayed green (the in-process suite preloads all runtime files, masking
# both failure classes).
RSpec.describe 'Reader controller composition integration' do
  let(:root) { File.expand_path('../..', __dir__) }

  around do |example|
    Dir.mktmpdir do |dir|
      @workdir = dir
      example.run
    end
  end

  def write_minimal_epub(path)
    container_xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
        <rootfiles>
          <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
        </rootfiles>
      </container>
    XML

    opf = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
          <dc:identifier id="uid">urn:uuid:spec-minimal-epub</dc:identifier>
          <dc:title>Minimal Composition Book</dc:title>
          <dc:creator>Spec Author</dc:creator>
          <dc:language>en</dc:language>
        </metadata>
        <manifest>
          <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
        </manifest>
        <spine>
          <itemref idref="chapter1"/>
        </spine>
      </package>
    XML

    chapter = <<~XHTML
      <?xml version="1.0" encoding="UTF-8"?>
      <html xmlns="http://www.w3.org/1999/xhtml">
        <head><title>Chapter One</title></head>
        <body>
          <h1>Chapter One</h1>
          <p>A single paragraph so the reader has something to paginate.</p>
        </body>
      </html>
    XHTML

    SpecZipBuilderHelper.write_stored_zip(
      path,
      {
        'mimetype' => 'application/epub+zip',
        'META-INF/container.xml' => container_xml,
        'OEBPS/content.opf' => opf,
        'OEBPS/chapter1.xhtml' => chapter,
      }
    )
  end

  it 'builds the full reader controller graph from the composition root under plain boot' do
    epub_path = File.join(@workdir, 'minimal.epub')
    write_minimal_epub(epub_path)

    # Hooks invoked by the event loop and by composition itself. They must sit
    # on the PUBLIC surface: a private slip either crashes the reader build
    # (register_async_relay) or silently disables the feature behind a
    # respond_to? guard (resize redraws, async draining).
    code = <<~RUBY
      $LOAD_PATH.unshift File.expand_path('lib', #{root.dump})
      require 'shoko'
      container = Shoko::Composition::ContainerFactory.create_default_container
      controller = Shoko::Composition::ContainerFactory.send(:build_reader_controller, container, #{epub_path.dump})
      hooks = %i[
        register_async_relay drain_async_results async_work_pending? consume_pending_resize?
        dispatch_input_keys draw_screen read_input_keys perform_first_paint main_loop
        translator_cycle_picker translator_open_picker
        translator_paste_source translator_copy_translation
      ]
      missing = hooks.reject { |hook| controller.public_methods.include?(hook) }
      abort("private or missing reader hooks: \#{missing.join(', ')}") unless missing.empty?
      puts 'READER_GRAPH_OK'
    RUBY

    env = {
      'SHOKO_TEST_MODE' => nil,
      'SHOKO_EAGER_BOOT' => nil,
      'XDG_CONFIG_HOME' => File.join(@workdir, 'config'),
      'XDG_CACHE_HOME' => File.join(@workdir, 'cache'),
    }
    stdout, stderr, status = Open3.capture3(env, 'ruby', '-e', code)

    expect(status.success?).to be(true), "reader graph failed to build under plain boot:\n#{stderr}"
    expect(stdout).to include('READER_GRAPH_OK')
  end
end
