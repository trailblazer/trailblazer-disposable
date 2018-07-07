module Trailblazer
  module Disposable
    class Twin
      extend Declarative::Schema
      # def self.definition_class
      #   Definition
      # end

      # def self.inherited(subclass)
      #   # no super here!
      #   heritage.(subclass) do |cfg|
      #     cfg[:args].last.merge!(_inherited: true) if cfg[:method] == :property
      #   end
      # end

      # def schema
      #   Definition::Each.new(self.class.definitions) # TODO: change this interface.
      # end

      module Types
        include Dry::Types.module
      end

      class << self
        def value!
          @value = Class.new(Dry::Struct::Value) do
            constructor_type :strict_with_defaults # TODO: remove me when failed_logins etc is sorted
          end
        end

        def inherited(subclass)
          super

          subclass.value!
        end

        # def struct_for(definitions)
        #   Class.new(Dry::Struct::Value) do
        #     constructor_type :strict_with_defaults # TODO: remove me when failed_logins etc is sorted

        #     definitions.each do |dfn|
        #       # attribute :password_digest, Types::Strict::String
        #       puts "@@@@@ #{dfn[:name].inspect} ==> #{dfn[:type]}"
        #       attribute dfn[:name], dfn[:type]
        #     end
        #   end
        # end

        def to_value
          @value
        end

        def default_nested_class
          Twin
        end

        # TODO: move to Declarative, as in Representable and Reform.
        def property(name, options={}, &block)
          # options[:private_name] ||= options.delete(:from) || name
          # is_inherited = options.delete(:_inherited)

          # if options.delete(:virtual)
          #   options[:writeable] = options[:readable] = false
          # end

          # options[:nested] = options.delete(:twin) if options[:twin]

          # super(name, options, &block).tap do |definition| # super is Declarative::Schema::property.
          #   create_accessors(name, definition) unless is_inherited
          # end
          _options = super

          puts "adding #{name.inspect} to #{@value} "
          if block_given? # FIXME
            if options[:collection] # FIXME
              @value.attribute name.to_sym, Types::Strict::Array#,_options[:nested].instance_variable_get(:@value) # Dry-struct definition

            else
              @value.attribute name.to_sym, _options[:nested].instance_variable_get(:@value) # Dry-struct definition
            end
          else
            @value.attribute name.to_sym, options[:type] # Dry-struct definition
          end
        end

        def collection(name, options={}, &block)
          property(name, options.merge(collection: true), &block)
        end
      end
    end
  end
end
