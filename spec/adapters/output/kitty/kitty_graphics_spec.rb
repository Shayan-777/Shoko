# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Kitty::KittyGraphics do
  let(:base_env) do
    {
      'KITTY_WINDOW_ID' => '',
      'TERM' => '',
      'TERM_PROGRAM' => '',
    }
  end
  let(:config) { Struct.new(:kitty_images).new(enabled) }
  let(:enabled) { true }

  describe '.supported?' do
    it 'detects Kitty via KITTY_WINDOW_ID' do
      with_env(base_env.merge('KITTY_WINDOW_ID' => '12')) do
        expect(described_class.supported?).to be(true)
      end
    end

    it 'detects Ghostty via TERM_PROGRAM' do
      with_env(base_env.merge('TERM_PROGRAM' => 'ghostty')) do
        expect(described_class.supported?).to be(true)
      end
    end

    it 'detects Ghostty via TERM' do
      with_env(base_env.merge('TERM' => 'xterm-ghostty')) do
        expect(described_class.supported?).to be(true)
      end
    end

    it 'returns false for unsupported terminals' do
      with_env(base_env.merge('TERM' => 'xterm-256color', 'TERM_PROGRAM' => 'tmux')) do
        expect(described_class.supported?).to be(false)
      end
    end
  end

  describe '.enabled_for?' do
    it 'requires both terminal support and config enablement' do
      with_env(base_env.merge('TERM_PROGRAM' => 'ghostty')) do
        expect(described_class.enabled_for?(config)).to be(true)
      end
    end

    context 'when config disables kitty images' do
      let(:enabled) { false }

      it 'returns false' do
        with_env(base_env.merge('TERM_PROGRAM' => 'ghostty')) do
          expect(described_class.enabled_for?(config)).to be(false)
        end
      end
    end

    it 'returns false when the terminal is unsupported' do
      with_env(base_env.merge('TERM' => 'screen-256color', 'TERM_PROGRAM' => 'tmux')) do
        expect(described_class.enabled_for?(config)).to be(false)
      end
    end

    it 'returns false (never raises) when the config does not expose #kitty_images' do
      with_env(base_env.merge('TERM_PROGRAM' => 'ghostty')) do
        expect(described_class.enabled_for?(Object.new)).to be(false)
      end
    end

    it 'returns false when the config is nil' do
      with_env(base_env.merge('TERM_PROGRAM' => 'ghostty')) do
        expect(described_class.enabled_for?(nil)).to be(false)
      end
    end
  end
end
