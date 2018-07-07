$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "trailblazer/disposable"

require "minitest/autorun"

Disposable = Trailblazer::Disposable
