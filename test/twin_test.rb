require "test_helper"

class TwinTest < Minitest::Spec
  class Collection < Array
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
#
  let(:twin_schema) do

# TODO: move that into the Hydration library
    # what to do after the "activity" ran and we collected all values for hydration on that level.
    populator        = ->(hash, definition, *) { definition[:twin].new( hash ) }
    populator_scalar = ->(value, definition, *) { value }

    populator_scalar_to_f = ->(value, definition, *) { value.to_f } # this is just for testing.


    twin_schema = {
      recursion: :recurse_nested, populator: populator,
      twin: Disposable::Twin.build_for(:id, :total, :taxes, :memos, :ids_ids, :ids),
      definitions: [
        {name: :id,    recursion: :recurse_scalar, populator: populator_scalar },
        {name: :total, recursion: :recurse_nested, populator: populator, twin: Disposable::Twin.build_for(:amount, :currency),
          definitions: [
            {name: :amount,  recursion: :recurse_scalar, populator: populator_scalar },
            {name: :currency,  recursion: :recurse_scalar, populator: populator_scalar },
          ]
        },

        {name: :taxes, recursion: :recurse_collection, populator: populator, twin: Collection, item_dfn: {recursion: :recurse_nested, populator: populator, twin: Disposable::Twin.build_for(:amount, :percent),
          definitions: [
            {name: :amount,  recursion: :recurse_scalar, populator: populator_scalar },
            {name: :percent,  recursion: :recurse_scalar, populator: populator_scalar },
          ] } },

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
  it do
    document = {
      id: "1.1",

      total: {
        amount: 100,
        # currency  : 7,
      }
    }

    model = Struct.new(:id, :taxes, :total, :memos, :ids_ids, :ids).new(1, [Struct.new(:amount, :percent).new(99, 19)], Struct.new(:amount, :currency).new(199, "EUR"), [], [], [])
    twin = Runtime.run_scalar(twin_schema, model)

    # TODO: call `nested`
    twin = Disposable::Schema::Parse.run_definitions(twin_schema, document, twin)

    twin = twin[0] # FIXME

    pp twin

    twin.id.must_equal "1.1"
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
