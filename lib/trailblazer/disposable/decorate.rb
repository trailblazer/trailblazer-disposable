module Trailblazer
  module Disposable
    module Decorate
      extend Read # #from_h

      class << self
        public :from_h # TODO: fuck this shit!
      end

      module_function

      # TODO:
      #   * no ../
      #   * it doesn't wrap nested objects since we don't call any nested "populator"

      def read(source, definition)
        # #<Declarative::Definitions::Definition:0x0000000002a57c90 @options={:from=>"./id", :name=>"id"}>
        # TODO: do that at compile time
        root, *segments = definition[:from].split("/")
        element, *segments = segments.reverse

        if root == "."
          puts "@@@@@ #{segments.inspect}"

          if segments.any?
            source = segments.reverse.inject(source) { |memo, segment| memo[segment.to_sym] }
          end

          source[element.to_sym]
        else
          raise "not yet implemented!"
        end
      end

      def for_nested(source, definition)
        from_h(
          source,
          definitions: definition[:nested].definitions,
          populator:   ->(hash) { OpenStruct.new(hash).freeze } # TODO: make this unnecessary.
        )

      end
    end
  end
end
