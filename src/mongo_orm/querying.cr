class Object
  def from_bson(val)
    nil
  end
end

class String
	def self.from_bson(val)
	  val.as?(self)
	end

	def to_bson
    self
	end
end

struct Float32
	def self.from_bson(val)
		val.as?(self)
	end

	def to_bson
		self
	end
end

struct Float64
	def self.from_bson(val)
		val.as?(self)
	end

	def to_bson
		self
	end
end

struct Int32
	def self.from_bson(val)
		val.as?(self)
	end

	def to_bson
		self
	end
end

struct Int64
	def self.from_bson(val)
		val.as?(self)
	end

	def to_bson
		self
	end
end

module Mongo::ORM::Querying
  macro extended
    macro __process_querying
      \{% primary_name = PRIMARY[:name] %}
      \{% primary_type = PRIMARY[:type] %}

      def self.from_bson(bson : BSON)
        model = \{{@type.name.id}}.new
        model._id = bson["_id"].as(BSON::ObjectId) if bson["_id"]?
        fields = {} of String => Bool

        \{% for name, hash in FIELDS %}
					fields["\{{name.id}}"] = true
					if bson.has_key?("\{{name}}")
						model.\{{name.id}} = if \{{hash[:type].id}}.is_a? Mongo::ORM::EmbeddedDocument.class
							if embedded = bson["\{{name}}"]?
								\{{hash[:type].id}}.from_bson(embedded)
							end
						else bson.has_key?("\{{name}}")
							bson["\{{name}}"].as(Union(\{{hash[:type].id}} | Nil))
						end
					end
          \{% if hash[:type].id == Time %}
            model.\{{name.id}} = model.\{{name.id}}.not_nil!.to_utc if model.\{{name.id}}
          \{% end %}
        \{% end %}

				\{% for name, hash in SPECIAL_FIELDS %}
					fields["\{{name.id}}"] = true
					model.\{{name.id}} = [] of \{{hash[:type].id}}
					k = "\{{name}}"
					if bson.has_key?("\{{name}}")
            bson["\{{name}}"].not_nil!.as(BSON).each do |item|
							loaded = \{{hash[:type].id}}.from_bson(item.value)
							model.\{{name.id}} << loaded unless loaded.nil?
            end
          elsif !bson.has_key?("\{{name}}") && \{{ hash }}.has_key?(:default)
            \{{hash[:default]}}

          end
        \{% end %}

        \{% if SETTINGS[:timestamps] %}
          model.created_at = bson["created_at"].as(Union(Time | Nil)) if bson["created_at"]?
          model.updated_at = bson["updated_at"].as(Union(Time | Nil)) if bson["updated_at"]?
          model.created_at = model.created_at.not_nil!.to_utc if model.created_at
          model.updated_at = model.updated_at.not_nil!.to_utc if model.updated_at
        \{% end %}

				model.clear_dirty
				model.cache_original_values
        model
      end

      def to_bson(only_dirty = false, exclude_nil = true, only_nil = false)
        bson = BSON.new
        bson["_id"] = self._id  if self._id != nil && !only_dirty # id should never be dirty
        \{% for name, hash in FIELDS %}
          if !only_dirty || self.dirty?("\{{name}}")
            if (!exclude_nil || !\{{name.id}}.nil?)
							bson["\{{name}}"] = \{{name.id}}.as(Union(\{{hash[:type].id}} | Nil))
						elsif only_nil && \{{name.id}}.nil?
							bson["\{{name}}"] = nil
            end
          end
        \{% end %}
        \{% for name, hash in SPECIAL_FIELDS %}
          if \{{hash[:type].id}} == String
            if as_a = self.\{{name.id}}.as?(Array(String))
              bson.append_array(\{{name.stringify}}) do |array_appender|
                as_a.each{ |strval| array_appender << strval }
              end
            end
          else
            count_appends = 0
            if self.\{{name.id}} != nil || !exclude_nil
              bson.append_array(\{{name.stringify}}) do |array_appender|
                if self.\{{name.id}} != nil
                  self.\{{name}}.each do |item|
                    array_appender << item.to_bson if item
                  end
                end
              end
						end
          end
        \{% end %}
        \{% if SETTINGS[:timestamps] %}
          bson["created_at"] = created_at.as(Union(Time | Nil))
          bson["updated_at"] = updated_at.as(Union(Time | Nil))
        \{% end %}
        bson
      end
    end
  end

  def clear
    begin
      collection.drop
    rescue
    end
  end

	def all(query = BSON.new, skip = 0, limit = 0, batch_size = 0, flags = LibMongoC::QueryFlags::NONE, prefs = nil)
		{% if @type.class.has_method? "add_find_conditions" %}
			self.add_find_conditions(query)
		{% end %}

    rows = [] of self
    collection.find(query, BSON.new, flags, skip, limit, batch_size, prefs).each do |doc|
      rows << from_bson(doc) if doc
    end
    rows
  end

	def all_batches(query = BSON.new, batch_size = 100)
		{% if @type.class.has_method? "add_find_conditions" %}
			self.add_find_conditions(query)
		{% end %}

		collection.find(query, BSON.new, LibMongoC::QueryFlags::NONE, 0, 0, batch_size, nil).each do |doc|
      yield from_bson(doc)
    end
  end

	def first(query = BSON.new)
		all(query, 0, 1).first?
  end

  def find(value, query = BSON.new)
    if strval = value.as?(String)
      value = BSON::ObjectId.new(strval)
    end
    return find_by(@@primary_name.to_s, value, query)
  end

  # find_by using symbol for field name.
  def find_by(field : Symbol, value)
    field = :_id if field == :id
    find_by(field.to_s, value)  # find_by using symbol for field name.
  end

  # find_by returns the first row found where the field maches the value
	def find_by(field : String, value, query = BSON.new)
		query[field] = value

		{% if @type.class.has_method? "add_find_conditions" %}
			self.add_find_conditions(query)
		{% end %}

		collection.find(query, BSON.new, LibMongoC::QueryFlags::NONE, 0, 1) do |doc|
      return from_bson(doc)
    end

		nil
  end

  def count(query = BSON.new, flags = LibMongoC::QueryFlags::NONE)
    {% if @type.class.has_method? "add_find_conditions" %}
      self.add_find_conditions(query)
    {% end %}

    rows = [] of self
    collection.count(query, flags)
  end

  def create(**args)
    create(args.to_h)
  end

  def create(args : Hash(Symbol | String, DB::Any))
    instance = new
    instance.set_attributes(args)
    instance.save
    instance
  end
end
