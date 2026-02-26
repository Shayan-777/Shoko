# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Zip::File do
  it 'exposes central directory entries through #entries' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'sample.zip')
      SpecZipBuilderHelper.write_stored_zip(
        path,
        {
          'nested/book.fb2' => '<book/>',
          'nested/meta.txt' => 'hello'
        }
      )

      zip = described_class.open(path)
      begin
        names = zip.entries.map(&:name)

        expect(names).to eq(%w[nested/book.fb2 nested/meta.txt])
        expect(zip.entries.first).to be_a(Zip::Entry)
      ensure
        zip.close
      end
    end
  end
end
