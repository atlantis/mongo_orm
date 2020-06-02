require "json"

module Mongo::ORM::EmbeddedFields
  alias Type = JSON::Any | DB::Any | Array(String) | Array(BSON::ObjectId) | Array(Int32) | Array(Float32)
  TIME_FORMAT_REGEX = /\d{4,}-\d{2,}-\d{2,}\s\d{2,}:\d{2,}:\d{2,}/

  macro included
    macro inherited
			FIELDS = {} of Nil => Nil
			SPECIAL_FIELDS = {} of Nil => Nil
    end
  end

  macro field(decl, options = {} of Nil => Nil)
    {% not_nilable_type = decl.type.is_a?(Path) ? decl.type.resolve : (decl.type.is_a?(Union) ? decl.type.types.reject(&.resolve.nilable?).first : (decl.type.is_a?(Generic) ? decl.type.resolve : decl.type)) %}
    {% nilable = (decl.type.is_a?(Path) ? decl.type.resolve.nilable? : (decl.type.is_a?(Union) ? decl.type.types.any?(&.resolve.nilable?) : (decl.type.is_a?(Generic) ? decl.type.resolve.nilable? : decl.type.nilable?))) %}
    {% hash = {type: not_nilable_type, nillable: nilable} %}
    {% unless decl.value.is_a?(Nop) %}
      {% hash[:default] = decl.value %}
    {% end %}
    {% FIELDS[decl.var] = hash %}
  end

  macro embeds(decl)
    {% FIELDS[decl.var] = {type: decl.type} %}
    #raise "can only embed classes inheriting from Mongo::ORM::EmbeddedDocument" unless {{decl.type}}.new.is_a?(Mongo::ORM::EmbeddedDocument)
	end

	macro embeds_many(children_collection, class_name = nil)
    {% if children_collection.is_a?(SymbolLiteral) %}
      {% children_class = children_collection.id[0...-1].camelcase %}
      {% collection_name = children_collection.id %}
    {% else %}
      {% children_class = children_collection.type.id %}
      {% collection_name = children_collection.var.id %}
    {% end %}

    
    @{{collection_name}} = [] of {{children_class}}
    def {{collection_name}}
      @{{collection_name}}
    end

    def {{collection_name}}=(value : Array({{children_class}}))
      unless value == @{{collection_name}}
        @{{collection_name}} = value
      end
    end

    {% SPECIAL_FIELDS[collection_name] = {type: children_class} %}
  end

  # include created_at and updated_at that will automatically be updated
  macro timestamps
    {% SETTINGS[:timestamps] = true %}
  end

  macro __process_embedded_fields
    # Create the properties
    {% for name, hash in FIELDS %}
			property {{name.id}} : Union({{hash[:type].id}} | Nil) = {{hash[:default]}}
    {% end %}

    # keep a hash of the fields to be used for mapping
    def self.fields(fields = [] of String)
      {% for name, hash in FIELDS %}
        fields << "{{name.id}}"
			{% end %}
			{% for name, hash in SPECIAL_FIELDS %}
				fields << "{{name.id}}"
			{% end %}
      return fields
    end

    # keep a hash of the fields to be used for mapping
    def fields(fields = {} of String => Type | Nil)
      {% for name, hash in FIELDS %}
        fields["{{name.id}}"] = self.{{name.id}}
			{% end %}
			{% for name, hash in SPECIAL_FIELDS %}
				{% if hash[:type].id == String.id || hash[:type].id == BSON::ObjectId.id || hash[:type].id == Int32.id || hash[:type].id == Float32.id || hash[:type].id == Int64.id || hash[:type].id == Float64.id %}
					fields["{{name.id}}"] = [] of {{hash[:type].id}}
					if docs = self.{{name.id}}.as?(Array({{hash[:type].id}}))
						fields["{{name.id}}"] = docs
					end
				{% else %}
					adocs = [] of Mongo::ORM::EmbeddedDocument
					if docs = self.{{name.id}}.as?(Array({{hash[:type].id}}))
						docs.each{|doc| adocs << doc.as(Mongo::ORM::EmbeddedDocument)}
					end
					fields["{{name.id}}"] = adocs
				{% end %}
			{% end %}
      return fields
    end

    # keep a hash of the params that will be passed to the adapter.
    def params
      parsed_params = [] of DB::Any
      {% for name, hash in FIELDS %}
        {% if hash[:type].id == Time.id %}
          parsed_params << {{name.id}}.try(&.to_s("%F %X"))
        {% else %}
          parsed_params << {{name.id}}
        {% end %}
      {% end %}
      return parsed_params
		end

		# keep a hash of the fields to be used for mapping
    def multi_embeds(membeds = [] of {name: String, type: String})
      return [] of {name: String, type: String}
		end

		def to_h
      fields = {} of String => DB::Any

      {% for name, hash in FIELDS %}
        {% if hash[:type].id == Time.id %}
          fields["{{name}}"] = {{name.id}}.try(&.to_s("%F %X"))
        {% elsif hash[:type].id == Slice.id %}
          fields["{{name}}"] = {{name.id}}.try(&.to_s(""))
        {% else %}
          fields["{{name}}"] = {{name.id}}
        {% end %}
      {% end %}

      return fields
    end

    def to_json(json : JSON::Builder)
			json.object do
				{% for name, hash in FIELDS %}
				  %field, %value = "{{name.id}}", {{name.id}}
          {% if hash[:type].id == Time.id %}
            json.field %field, %value.try(&.to_s("%F %X"))
          {% elsif hash[:type].id == Slice.id %}
						json.field %field, %value.id.try(&.to_s(""))
					{% elsif hash[:type].id == BSON::ObjectId.id %}
						json.field %field, %value.try(&.to_s)
          {% else %}
            json.field %field, %value
          {% end %}
        {% end %}
      end
    end

    def set_attributes(args : Hash(String | Symbol, Type))
      args.each do |k, v|
        cast_to_field(k, v.as(Type))
      end
    end

    def set_attributes(**args)
      set_attributes(args.to_h)
    end

    # Casts params and sets fields
    private def cast_to_field(name, value : Type)
      case name.to_s
			{% for _name, hash in FIELDS %}
			when "{{_name.id}}"
				return @{{_name.id}} = nil if value.nil?
				{% if hash[:type].id == BSON::ObjectId.id %}
					@{{_name.id}} = BSON::ObjectId.new value.to_s
				{% elsif hash[:type].id == Int32.id %}
					@{{_name.id}} = value.is_a?(String) ? value.to_i32 : value.is_a?(Int64) ? value.to_s.to_i32 : value.as(Int32)
				{% elsif hash[:type].id == Int64.id %}
					@{{_name.id}} = value.is_a?(String) ? value.to_i64 : value.as(Int64)
				{% elsif hash[:type].id == Float32.id %}
					@{{_name.id}} = value.is_a?(String) ? value.to_f32 : value.is_a?(Float64) ? value.to_s.to_f32 : value.as(Float32)
				{% elsif hash[:type].id == Float64.id %}
					@{{_name.id}} = value.is_a?(String) ? value.to_f64 : value.as(Float64)
				{% elsif hash[:type].id == Bool.id %}
					@{{_name.id}} = ["1", "yes", "true", true].includes?(value)
				{% elsif hash[:type].id == Time.id %}
					if value.is_a?(Time)
							@{{_name.id}} = value.to_utc
						elsif value.to_s =~ TIME_FORMAT_REGEX
							@{{_name.id}} = Time.parse(value.to_s, "%F %X").to_utc
						end
				{% else %}
					@{{_name.id}} = value.to_s
				{% end %}
			{% end %}
			else
				Log.debug { "cast_to_field got nuthin for #{name.to_s}" }
			end

			case name.to_s
			{% for _name, hash in SPECIAL_FIELDS %}
			when "{{_name.id}}"
				if array_val = value.as_a?(Array({{hash[:type].id}}))
					@{{_name.id}} = array_val
				else
					@{{_name.id}} = [] of {{hash[:type].id}}
				end
			{% end %}
			else
				Log.debug { "cast_to_field got nuthin for #{name.to_s}" }
			end
    end
  end
end
