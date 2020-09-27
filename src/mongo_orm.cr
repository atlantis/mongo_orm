require "mongo"
require "./mongo_orm/*"
require "yaml"

module Mongo::ORM
  Log = ::Log.for("orm")
end
