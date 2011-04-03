module SPDY
  module Protocol

    CONTROL_BIT = 1
    DATA_BIT    = 0
    VERSION     = 2

    module Control
      class Header < BinData::Record
        hide :u1

        bit1 :frame, :initial_value => CONTROL_BIT
        bit15 :version, :initial_value => VERSION
        bit16 :type

        bit8 :flags
        bit24 :len

        bit1 :u1
        bit31 :stream_id
      end

      class SynStream < BinData::Record
        hide :u1, :u2

        header :header

        bit1  :u1
        bit31 :associated_to_stream_id

        bit2  :pri
        bit14 :u2

        string :data, :read_length => lambda { header.len - 10 }
      end

      class SynReply < BinData::Record
        attr_accessor :uncompressed_data

        header :header
        bit16 :unused
        string :data, :read_length => lambda { header.len - 6 }

        def parse(chunk)
          self.read(chunk)

          data = Zlib.inflate(self.data.to_s)
          self.uncompressed_data = NV.new.read(data)
          self
        end

        def create(opts = {})
          self.header.type  = 2
          self.header.len   = 6

          self.header.flags   = opts[:flags] || 0
          self.header.stream_id = opts[:stream_id]

          nv = SPDY::Protocol::NV.new
          opts[:headers].each do |k, v|
            nv.headers << {:name_len => k.size, :name_data => k, :value_len => v.size, :value_data => v}
          end
          nv.pairs = opts[:headers].size

          nv = SPDY::Zlib.deflate(nv.to_binary_s)

          self.header.len = self.header.len.to_i + nv.size
          self.data = nv

          self
        end
      end
    end

    module Data
      class Frame < BinData::Record
        bit1 :frame, :initial_value => DATA_BIT
        bit31 :stream_id

        bit8 :flags, :initial_value => 0
        bit24 :len,  :initial_value => 0

        string :data

        def create(opts = {})
          self.stream_id = opts[:stream_id]
          self.flags     = opts[:flags] if opts[:flags]

          if opts[:data]
            self.len       = opts[:data].size
            self.data      = opts[:data]
          end

          self
        end
      end
    end

    class NV < BinData::Record
      bit16 :pairs
      array :headers, :initial_length => :pairs do
        bit16 :name_len
        string :name_data, :read_length => :name_len

        bit16 :value_len
        string :value_data, :read_length => :value_len
      end

      def to_h
        headers.inject({}) do |h, v|
          h[v.name_data.to_s] = v.value_data.to_s
          h
        end
      end
    end
  end
end