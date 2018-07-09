require "test_helper"

class DisposableTest < Minitest::Spec
  it do

    # class Ficken < Dry::Struct::Value
    #   attribute :arr, Dry::Types.module::Strict::Array
    # end

    # pp Ficken.new(arr: [ Struct.new(:a).new(1), 2])



    class Expense
      # Define what you _want_ from the source object, and what the source looks like. (also, data types)
      class Source < Disposable::Twin

        property :id, type: Types::Strict::Int
        property :data do
          collection :taxes do
            property :amount, type: Types::Strict::Int
            property :percent, type: Types::Strict::Int # fixme
          end
          property :country, type: Types::Strict::String
        end
        property :amount, type: Types::Strict::Int
      end

      class Domain < Disposable::Twin #Decorator
        # source Source

        property :id, from: "./id"

        # unnest :taxes, from: :data
        collection :taxes, from: "./data/taxes" do
          property :amount, from: "./amount"
          property :percent, from: "./percent"
        end

        # alias  :total, from: :amount
        property :total, from: "./amount"

        # property :data do
        #   # nest :id, from: "../"
        #   property :id, from: "../id"
        # end
      end

      # TODO: coercion here?
      class Twin < Disposable::Twin
        # source Domain

        property :id

        collection :taxes do
          property :amount
          property :percent
        end

        property :total
      end
    end

    # pp Expense::Source.definitions["data"][:nested].definitions["taxes"][:nested].instance_variable_get(:@value).new(amount: 1, percent: 2)
    # raise

    source = Struct.new(:id, :data, :amount, :rubbish).new(
      1,
      Struct.new(:taxes, :country).new([
        {
          amount: 1,
          percent: 2,
        }
        ],
        "DEU",
      ),
      99,
      "bla ignore me",
    )

    # we want a immutable twin that matches the Source (but only specified properties, plus defaults, plus coercions?)
    twin = Disposable::Read.from_h(source, definitions: Expense::Source.definitions, populator: ->(hash, definition:) { definition[:nested].to_value.new(hash) }, definition: {nested: Expense::Source} )

    twin.to_h.must_equal({:id=>1, :data=>{:taxes=>[{:amount=>1, :percent=>2}], :country=>"DEU"}, :amount=>99})

    # decorate ("domain object")
    decorated = Disposable::Decorate.from_h(twin, definitions: Expense::Domain.definitions, populator: ->(hash, definition:) { OpenStruct.new(hash).freeze }, definition: nil )
    decorated.inspect.must_equal %{#<OpenStruct id=1, taxes=[#<OpenStruct amount=1, percent=2>], total=99>}
    # decorated.to_h.must_equal()

    decorated.id.must_equal 1
    decorated.taxes[0].percent.must_equal 2

    # to_mutable
    form = Disposable::Twin.from_h(decorated, definitions: Expense::Twin.definitions, populator: ->(hash, definition:) { definition[:nested].to_twin.new(hash) }, definition: {nested: Expense::Twin}  )
  end
end
