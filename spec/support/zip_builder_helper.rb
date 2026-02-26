# frozen_string_literal: true

require 'zlib'

module SpecZipBuilderHelper
  module_function

  def write_stored_zip(path, entries)
    File.binwrite(path, build_stored_zip(entries))
  end

  def build_stored_zip(entries)
    local_data = +''
    central_data = +''
    offset = 0

    entries.each do |name, content|
      entry_name = name.to_s.b
      payload = content.to_s.b
      crc = Zlib.crc32(payload)

      local_header = [
        0x04034B50, # local header signature
        20, # version needed to extract
        0, # general purpose bit flag
        0, # compression method (stored)
        0, # last mod file time
        0, # last mod file date
        crc,
        payload.bytesize,
        payload.bytesize,
        entry_name.bytesize,
        0, # extra length
      ].pack('VvvvvvVVVvv')

      central_header = [
        0x02014B50, # central header signature
        20, # version made by
        20, # version needed to extract
        0, # general purpose bit flag
        0, # compression method (stored)
        0, # last mod file time
        0, # last mod file date
        crc,
        payload.bytesize,
        payload.bytesize,
        entry_name.bytesize,
        0, # extra length
        0, # comment length
        0, # disk number start
        0, # internal attrs
        0, # external attrs
        offset,
      ].pack('VvvvvvvVVVvvvvvVV')

      local_data << local_header << entry_name << payload
      central_data << central_header << entry_name
      offset += local_header.bytesize + entry_name.bytesize + payload.bytesize
    end

    eocd = [
      0x06054B50, # EOCD signature
      0, # disk number
      0, # central dir disk
      entries.length,
      entries.length,
      central_data.bytesize,
      local_data.bytesize,
      0, # comment length
    ].pack('VvvvvVVv')

    (local_data + central_data + eocd).b
  end
end
