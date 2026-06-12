# frozen_string_literal: true

require 'spec_helper'

# Constitution §IV: max directory depth 4 levels under lib/shoko/<layer>/, and
# require_relative may climb at most 2 levels. Far references go through the
# load path (`require 'shoko/...'`) — the lib root is on $LOAD_PATH from every
# entry point (bin/shoko, lib/shoko.rb, spec_helper, the isolated-require
# harness). The pre-rule deep trees were flattened/deleted on 2026-06-12; both
# rules now hold with no allowlist (see constitution amendment 2026-06-12).
RSpec.describe 'Directory depth' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }

  MAX_DEPTH_BELOW_LAYER = 4
  MAX_REQUIRE_CLIMB = 2

  it 'keeps files within 4 directory levels below their layer' do
    offenders = Dir[File.join(lib_root, '**', '*.rb')].filter_map do |path|
      rel = path.delete_prefix("#{lib_root}/")
      segments = rel.split('/')
      directories_below_layer = segments.length - 2 # drop the layer dir and the filename
      next unless directories_below_layer > MAX_DEPTH_BELOW_LAYER

      "#{rel} (#{directories_below_layer} levels)"
    end

    expect(offenders).to eq([]),
                         "Files nested deeper than #{MAX_DEPTH_BELOW_LAYER} levels below their layer " \
                         "(constitution §IV — move the file, don't deepen the tree):\n#{offenders.sort.join("\n")}"
  end

  it 'keeps require_relative climbs to at most 2 levels' do
    climbing = /require_relative\s+['"](?:\.\.\/){#{MAX_REQUIRE_CLIMB + 1},}/
    offenders = Dir[File.join(lib_root, '**', '*.rb')].flat_map do |path|
      File.foreach(path).with_index(1).filter_map do |line, lineno|
        next unless line.match?(climbing)

        "#{path.delete_prefix("#{root}/")}:#{lineno}"
      end
    end

    expect(offenders).to eq([]),
                         "require_relative must climb at most #{MAX_REQUIRE_CLIMB} levels " \
                         "(constitution §IV — use `require 'shoko/...'` for far references):\n" \
                         "#{offenders.sort.join("\n")}"
  end
end
