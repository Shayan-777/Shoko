# frozen_string_literal: true

require 'open3'
require 'spec_helper'

RSpec.describe 'XHTML parser factory dependency loading' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:env) do
    {
      'SHOKO_TEST_MODE' => nil,
      'SHOKO_EAGER_BOOT' => nil,
    }
  end

  it 'builds the deferred xhtml parser factory without eager boot' do
    stdout, stderr, status = Open3.capture3(env, 'ruby', '-e', code)

    expect(status.success?).to be(true), stderr
    expect(stdout.lines.map(&:strip)).to eq(
      [
        'Shoko::Adapters::BookSources::Epub::XHTMLContentParser',
        'constant',
      ]
    )
  end

  def code
    <<~RUBY
      $LOAD_PATH.unshift File.expand_path('lib', #{root.dump})
      require 'shoko'
      container = Shoko::Composition::ContainerFactory.create_default_container
      parser = container.resolve(:xhtml_parser_factory).call('<html><body><p>hello</p></body></html>')
      puts parser.class.name
      puts defined?(Shoko::Adapters::BookSources::Epub::XHTMLContentParser)
    RUBY
  end
end
