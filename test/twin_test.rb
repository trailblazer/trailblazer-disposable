require "test_helper"

class TwinTest < Minitest::Spec
  class Collection < Array
    def initialize(*items)
        super(*items)

        @deleted = []
      end

    def delete_all!
      each { |item| @deleted = to_a }
    end

    # TODO: only prototyping
    def to_diff
      collect { |el| el }
    end
  end

=begin
  # hydration (population of new twin)
#read()
  values = nested.(source)
  populator.(values)

    # nested scalar
    value = read(source)
      # populator.(value) # no populator needed

    # nested
    values = read(source)        # eg. source.author
      values = nested.(values)    # eg.
      populator.(values)

    # nested collection
    values = read(source) # source.comments
      source.collect
        values = nested.(values)
        populator.(values)
      populator.(values)


  property :expense, populator: ->(hash, definition) { Expense::Twin.new(hash) }
    property :id,
=end

require "ostruct"

    Runtime = Disposable::Schema::Runtime

    module Populator
      module Collection
        def self.call(dfn, fragment, twin:, **)
          # {twin} is the parent twin, the {Expense}.

          collection = twin.send(dfn[:name]) # provide the original collection

          # return collection.delete_all! if fragment.empty? # THIS IS AN ASSUMPTION WE DO. this should be an Activity.
          # it would be cool if we could jump to failure here and then skip the parsing explicitly, not because `fragment` is empty.

          {twin: TwinTest::Collection.new, original_collection: collection}
        end

        module Item
          def self.call(dfn, fragment, twin:, index:, original_collection:, **)
            # {twin} is the new collection
            # {original_collection} is the, well, original collection


            # twin[index]  # TODO: test "simple" populator where we use index, only.

            # here, we match by {percent}
            # existing = twin.find { |el| el.percent == fragment[:percent] }

            twin << item = dfn[:twin].new({}) # TODO: introduce a "parse twin" that is mutable

            {twin: item}
          end
        end
      end
    end
#
  let(:twin_schema) do

# TODO: move that into the Hydration library
    # what to do after the "activity" ran and we collected all values for hydration on that level.
    populator        = ->(hash, definition, *) { definition[:twin].new( hash ) }
    populator_scalar = ->(value, definition, *) { value }
    populator_to_h = ->(value, definition, *) { Hash[value] }

    populator_scalar_to_f = ->(value, definition, *) { value.to_f } # this is just for testing.

    populator_scalar_parse = ->(dfn, value, twin) { {twin: value} }

    twin_schema = {
      recursion: :recurse_nested, populator: populator,
      twin: Disposable::Twin.build_for(:id, :total, :taxes, :memos, :ids_ids, :ids),
      to_hash_populator: populator_to_h,
      definitions: [
        {name: :id,    recursion: :recurse_scalar, populator: populator_scalar, parse_populator: populator_scalar_parse, to_hash_populator: populator_scalar },
        {name: :total, recursion: :recurse_nested, populator: populator, twin: Disposable::Twin.build_for(:amount, :currency), parse_populator: ->(dfn, fragment, twin:, **) { {twin: twin.total} }, to_hash_populator: populator_to_h,
          definitions: [
            {name: :amount,  recursion: :recurse_scalar, populator: populator_scalar, parse_populator: populator_scalar_parse, to_hash_populator: populator_scalar },
            {name: :currency,  recursion: :recurse_scalar, populator: populator_scalar, parse_populator: populator_scalar_parse, to_hash_populator: populator_scalar },
          ]
        },

        {name: :taxes, recursion: :recurse_collection, populator: populator, twin: Collection, parse_populator: Populator::Collection, to_hash_populator: populator_scalar,
          item_dfn: {
            name: :bla, recursion: :recurse_nested, populator: populator, twin: Disposable::Twin.build_for(:amount, :percent), parse_populator: Populator::Collection::Item, to_hash_populator: populator_to_h,
            definitions: [
              {name: :amount,  recursion: :recurse_scalar, populator: populator_scalar, parse_populator: ->(dfn, fragment, twin:, **) { {twin: fragment} }, to_hash_populator: populator_scalar },
              {name: :percent,  recursion: :recurse_scalar, populator: populator_scalar, parse_populator: ->(dfn, fragment, twin:, **) { {twin: fragment} }, to_hash_populator: populator_scalar },
            ]
        } },

        {name: :memos, recursion: :recurse_collection, populator: populator, twin: Collection, item_dfn:
          {
            recursion: :recurse_nested, populator: populator, twin: Disposable::Twin.build_for(:comments),
            definitions: [
              {
                name: :comments,
                recursion: :recurse_collection, populator: populator, twin: Collection, item_dfn:
                {
                  recursion: :recurse_nested, populator: populator, twin: Disposable::Twin.build_for(:text),
                  definitions: [
                    {name: :text,  recursion: :recurse_scalar, populator: populator_scalar },
                  ]
                },
              }
            ],
          }
        },

        {name: :ids_ids, recursion: :recurse_collection, populator: populator, twin: Collection, item_dfn: {
            recursion: :recurse_collection, populator: populator, twin: Collection, item_dfn: {
              recursion: :recurse_scalar, populator: populator_scalar_to_f
            }
          }
        },

        {
          name:       :ids,
          recursion:   :recurse_collection,
          populator:  populator,
          twin:       Collection,
          item_dfn: {
            recursion: :recurse_scalar, populator: populator_scalar_to_f
          }
        },
      ]
    }
  end

# hydrate a fresh twin from an existing source model.
  it do
    Memo = Struct.new(:comments)
    Comment = Struct.new(:text)

    model = Struct.new(:id, :taxes, :total, :memos, :ids_ids, :ids).new(1, [Struct.new(:amount, :percent).new(99, 19)], Struct.new(:amount, :currency).new(199, "EUR"),
      # collection with property with collection
      [Memo.new([Comment.new("a"), Comment.new("b")])],

      # collection in collection
      [[1,2], [3,4]],
      # collection of scalars
      [1,2,3]
    )

    pp twin = Runtime.run_scalar(twin_schema, model)

    twin.taxes.class.must_equal Collection
    twin.memos.class.must_equal Collection
    twin.memos[0].comments.class.must_equal Collection

    # read
    twin.memos[0].comments[0].text.must_equal "a"
    twin.memos[0].comments[1].text.must_equal "b"
    twin.id.must_equal 1
    twin.taxes.size.must_equal 1
    twin.taxes[0].amount.must_equal 99
    twin.taxes[0].percent.must_equal 19
    twin.total.amount.must_equal 199
    twin.total.currency.must_equal "EUR"
  end

# parse document to twin

  describe "Parse" do
    let(:model) { Struct.new(:id, :taxes, :total, :memos, :ids_ids, :ids).new(1, [Struct.new(:amount, :percent).new(99, 19)], Struct.new(:amount, :currency).new(199, "EUR"), [], [], []) }
    let(:twin)  { Runtime.run_scalar(twin_schema, model) }

    it do
      document = {
        id: "1.1",

        total: {
          amount: 100,
          # currency  : 7,
        },

        taxes: [
          { amount: 98, percent: 9},
        ]
      }


      # TODO: call `nested`

      _twin = Disposable::Schema::Parse.run_definitions(twin_schema, document, twin: twin)

      twin = _twin[0] # FIXME

      pp twin

      twin.id.must_equal "1.1"
      twin.total.amount.must_equal 100

      twin.taxes.size.must_equal 1
      twin.taxes[0].amount.must_equal 98
      twin.taxes[0].percent.must_equal 9

      # TODO:
      # twin.diff
    end

    it "allows resetting collections" do
      document = {
        taxes: []
      }

      tax_1 = twin.taxes[0]

      _twin = Disposable::Schema::Parse.run_definitions(twin_schema, document, twin: twin)

      twin = _twin[0] # FIXME

      pp twin

      twin.taxes.size.must_equal 0 # collection is reset

    # original collection is still there
      twin.instance_variable_get(:@fields)[:taxes].size.must_equal 1
      twin.instance_variable_get(:@fields)[:taxes][0].amount.must_equal 99

      # TODO: twin.diff
    end

    it "allows adding and removing items" do
      document = {
        taxes: [
          { amount: 190, percent: 20 },
          { amount: 200, percent: 7  },
        ]
      }

      tax_1 = twin.taxes[0]

      _twin = Disposable::Schema::Parse.run_definitions(twin_schema, document, twin: twin)

      twin = _twin[0] # FIXME
      pp twin

# the "new" taxes collection represents the parsed incoming collection, not the old one.
      twin.taxes.size.must_equal 2
      twin.taxes[0].amount.must_equal 190
      twin.taxes[1].amount.must_equal 200

# we still have the original collection.
      twin.instance_variable_get(:@fields)[:taxes][0].amount.must_equal 99
      # TODO: Twin.to_h(twin)

# to_h
_twin_schema = twin_schema.dup
_twin_schema[:definitions].pop
_twin_schema[:definitions].pop
_twin_schema[:definitions].pop

# render the complete twin with effective values
      hash = Disposable::Schema::ToHash.run_scalar(_twin_schema, twin)

      hash.must_equal(
        {
          :id=>1,
          :total=>{:amount=>199, :currency=>"EUR"},
          :taxes=>[
            {:amount=>190, :percent=>20},
            {:amount=>200, :percent=>7}
          ]
        }
      )

      # render only changed
      pp twin.instance_variable_get(:@changed)
            hash = Disposable::Schema::ToHash::Changed.run_scalar(_twin_schema, twin.instance_variable_get(:@changed))  # FIXME.
    end



  end




  module Expense
    class Twin < Disposable::Twin
      property :id, twin: ->(value) { value }

      collection :taxes, collection_populator: ->(items, definition) { Collection.new(items) } do
        property :amount, twin: ->(value) { value }
        property :percent, twin: ->(value) { value }
      end

      property :total do
        property :amount, twin: ->(value) { value }
        property :currency, twin: ->(value) { value }
      end
    end
  end

  it do
    model = Struct.new(:id, :taxes, :total).new(1, [Struct.new(:amount, :percent).new(99, 19)], Struct.new(:amount, :currency).new(199, "EUR"))

    twin = Disposable::Schema.for_property(
      {nested: Expense::Twin, twin: Expense::Twin, name: "/root"},
      {"/root".to_sym => model},

      populator:   ->(hash, definition:) { definition[:twin].(hash) },

      # definitions: Expense::Twin.definitions,
      # # per "item"
      # # per collection
      # # collection_populator: ->(ary, definition) { snippet },
    )

    puts "result"
    pp twin
    pp twin[1].taxes[0].amount

    twin = twin[1]

    twin.taxes.class.must_equal Collection
  end

  it do
    model = Struct.new(:id, :taxes, :total).new(1, [Struct.new(:amount, :percent).new(99, 19)], Struct.new(:amount, :currency).new(199, "EUR"))

    twin = Disposable::Twin::Schema.from_h(model,
      definitions: Expense::Twin.definitions,
      # per "item"
      populator:   ->(hash, definition:) { definition[:nested].new(hash) },
      # per collection
      # collection_populator: ->(ary, definition) { snippet },
      definition:  {nested: Expense::Twin}
    )

    # read
    twin.id.must_equal 1
    twin.taxes.size.must_equal 1
    twin.taxes[0].amount.must_equal 99
    twin.taxes[0].percent.must_equal 19
    twin.total.amount.must_equal 199
    twin.total.currency.must_equal "EUR"

    # write
    twin.id = 2
    twin.taxes = []
    twin.total.amount = 200

    # updated read
    twin.id.must_equal 2
    twin.taxes.size.must_equal 0
    twin.total.amount.must_equal 200
    twin.total.currency.must_equal "EUR"

    # to_h
    Disposable::Twin.to_h(Expense::Twin, )
  end
end
