require "json"

module Mongo::ORM::EmbeddedFields
  alias Type = JSON::Any | DB::Any
  TIME_FORMAT_REGEX = /\d{4,}-\d{2,}-\d{2,}\s\d{2,}:\d{2,}:\d{2,}/

  macro included
    macro inherited
      FIELDS = {} of Nil => Nil
    end
  end

  # specify the fields you want to define and types
  macro field(decl, options = {} of Nil => Nil)
    {% hash = { type_: decl.type } %}
    {% if options.keys.includes?("default".id) %}
      {% hash[:default] = options[:default.id] %}
    {% end %}
    {% FIELDS[decl.var] = hash %}
  end

  macro embeds(decl)
    {% FIELDS[decl.var] = {type_: decl.type} %}
    raise "can only embed classes inheriting from Mongo::ORM::EmbeddedDocument" unless {{decl.type}}.new.is_a?(Mongo::ORM::EmbeddedDocument)
  end

  # include created_at and updated_at that will automatically be updated
  macro timestamps
    {% SETTINGS[:timestamps] = true %}
  end

  macro __process_embedded_fields
    # Create the properties
    {% for name, hash in FIELDS %}
      property {{name.id}} : Union({{hash[:type_].id}} | Nil)
    {% end %}

    # keep a hash of the fields to be used for mapping
    def self.fields(fields = [] of String)
      {% for name, hash in FIELDS %}
        fields << "{{name.id}}"
      {% end %}
      return fields
    end

    # keep a hash of the fields to be used for mapping
    def fields(fields = {} of String => Type | Nil)
      {% for name, hash in FIELDS %}
        fields["{{name.id}}"] = self.{{name.id}}
      {% end %}
      return fields
    end

    # keep a hash of the params that will be passed to the adapter.
    def params
      parsed_params = [] of DB::Any
      {% for name, hash in FIELDS %}
        {% if hash[:type_].id == Time.id %}
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

		def set_string_array(name : String, value : Array(String))
    end

    def to_h
      fields = {} of String => DB::Any

      {% for name, hash in FIELDS %}
        {% if hash[:type_].id == Time.id %}
          fields["{{name}}"] = {{name.id}}.try(&.to_s("%F %X"))
        {% elsif hash[:type_].id == Slice.id %}
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
          {% if hash[:type_].id == Time.id %}
            json.field %field, %value.try(&.to_s(%F %X))
          {% elsif hash[:type_].id == Slice.id %}
            json.field %field, %value.id.try(&.to_s(""))
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
          {% if hash[:type_].id == BSON::ObjectId.id %}
            @{{_name.id}} = BSON::ObjectId.new value.to_s
          {% elsif hash[:type_].id == Int32.id %}
            @{{_name.id}} = value.is_a?(String) ? value.to_i32 : value.is_a?(Int64) ? value.to_s.to_i32 : value.as(Int32)
          {% elsif hash[:type_].id == Int64.id %}
            @{{_name.id}} = value.is_a?(String) ? value.to_i64 : value.as(Int64)
          {% elsif hash[:type_].id == Float32.id %}
            @{{_name.id}} = value.is_a?(String) ? value.to_f32 : value.is_a?(Float64) ? value.to_s.to_f32 : value.as(Float32)
          {% elsif hash[:type_].id == Float64.id %}
            @{{_name.id}} = value.is_a?(String) ? value.to_f64 : value.as(Float64)
          {% elsif hash[:type_].id == Bool.id %}
            @{{_name.id}} = ["1", "yes", "true", true].includes?(value)
          {% elsif hash[:type_].id == Time.id %}
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
          Log.debug { "cast_to_field got nuthin" }
      end
    end
  end
end
