require "json"

module Mongo::ORM::Fields
  alias Type = JSON::Any | DB::Any
  TIME_FORMAT_REGEX = /\d{4,}-\d{2,}-\d{2,}\s\d{2,}:\d{2,}:\d{2,}/

  macro included
    macro inherited
      FIELDS = {} of Nil => Nil
      SPECIAL_FIELDS = {} of Nil => Nil

      @[JSON::Field(ignore: true)]
      getter? dirty_fields = [] of String
    end
  end

  # specify the fields you want to define and types
  macro field(decl, options = {} of Nil => Nil)
    {% not_nilable_type = decl.type.is_a?(Path) ? decl.type.resolve : (decl.type.is_a?(Union) ? decl.type.types.reject(&.resolve.nilable?).first : (decl.type.is_a?(Generic) ? decl.type.resolve : decl.type)) %}
    {% nilable = (decl.type.is_a?(Path) ? decl.type.resolve.nilable? : (decl.type.is_a?(Union) ? decl.type.types.any?(&.resolve.nilable?) : (decl.type.is_a?(Generic) ? decl.type.resolve.nilable? : decl.type.nilable?))) %}
    {% hash = {type_: not_nilable_type, nillable_: nilable} %}
    {% if options.keys.includes?("default".id) %}
      {% hash[:default] = options[:default.id] %}
    {% elsif !decl.value.is_a?(Nop) %}
      {% hash[:default] = decl.value %}
    {% end %}
    {% FIELDS[decl.var] = hash %}
  end

  macro embeds(decl)
    {% FIELDS[decl.var] = {type_: decl.type} %}
    raise "can only embed classes inheriting from Mongo::ORM::EmbeddedDocument" unless {{decl.type}}.new.is_a?(Mongo::ORM::EmbeddedDocument)
  end

  macro embeds_many(children_collection, class_name = nil)
    {% children_class = class_name ? class_name.id : children_collection.id[0...-1].camelcase %}
    {% children_array_class = "Array(#{children_class})" %}
    @{{children_collection.id}} = [] of {{children_class}}
    def {{children_collection.id}}
      @{{children_collection.id}}
    end

    def {{children_collection.id}}=(value : Array({{children_class}}))
      @{{children_collection.id}} = value
      mark_dirty("{{children_collection.id}}")
    end
    {% SPECIAL_FIELDS[children_collection.id] = {type_: children_class} %}
  end

  # include created_at and updated_at that will automatically be updated
  macro timestamps
    {% SETTINGS[:timestamps] = true %}
  end

  macro __process_fields
    # Create the properties
    {% for name, hash in FIELDS %}
      #property {{name.id}} : Union({{hash[:type_].id}} | Nil)
      def {{name.id}}=(@{{name.id}} : {{hash[:type_]}}?)
        self.mark_dirty("{{name.id}}")
      end

      def {{name.id}} : {{hash[:type_]}}?
        @{{name.id}}
      end

      def {{name.id}}! : {{hash[:type_]}}
        raise NilAssertionError.new {{name.stringify}} + "#" + {{name.id.stringify}} + " cannot be nil" if @{{name.id}}.nil?
        @{{name.id}}.not_nil!
      end
    {% end %}
    {% if SETTINGS[:timestamps] %}
      property created_at : Time?
      property updated_at : Time?
    {% end %}

    # keep a hash of the fields to be used for mapping
    def multi_embeds(membeds = [] of {name: String, type: String})
      {% for name, hash in SPECIAL_FIELDS %}
      membeds << {name: "{{name.id}}", type: "{{hash[:type_].id}}"}
      {% end %}
      return membeds
    end

    # keep a hash of the fields to be used for mapping
    def self.fields(fields = [] of String)
      {% for name, hash in FIELDS %}
        fields << "{{name.id}}"
      {% end %}
      {% if SETTINGS[:timestamps] %}
        fields << "created_at"
        fields << "updated_at"
      {% end %}
      return fields
    end

    # keep a hash of the fields to be used for mapping
    def fields(fields = {} of String => Type | Nil)
      {% for name, hash in FIELDS %}
        fields["{{name.id}}"] = self.{{name.id}}
      {% end %}
      {% if SETTINGS[:timestamps] %}
        fields["created_at"] = self.created_at
        fields["updated_at"] = self.updated_at
      {% end %}
      fields["_id"] = self._id
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
      {% if SETTINGS[:timestamps] %}
        parsed_params << created_at.not_nil!.to_s("%F %X")
        parsed_params << updated_at.not_nil!.to_s("%F %X")
      {% end %}
      return parsed_params
    end

    def to_h
      fields = {} of String => DB::Any

      fields["{{PRIMARY[:name]}}"] = {{PRIMARY[:name]}}

      {% for name, hash in FIELDS %}
        {% if hash[:_type].id == Time.id %}
          fields["{{name}}"] = {{name.id}}.try(&.to_s("%F %X"))
        {% elsif hash[:_type].id == Slice.id %}
          fields["{{name}}"] = {{name.id}}.try(&.to_s(""))
        {% else %}
          fields["{{name}}"] = {{name.id}}
        {% end %}
      {% end %}
      {% if SETTINGS[:timestamps] %}
        fields["created_at"] = created_at.try(&.to_s("%F %X"))
        fields["updated_at"] = updated_at.try(&.to_s("%F %X"))
      {% end %}

      return fields
    end

    def to_json(json : JSON::Builder)
      json.object do
        json.field "{{PRIMARY[:name]}}", {{PRIMARY[:name]}} ? {{PRIMARY[:name]}}.to_s : nil

        {% for name, hash in FIELDS %}
          %field, %value = "{{name.id}}", {{name.id}}
          {% if hash[:type_].id == Time.id %}
            json.field %field, %value.to_s
          {% elsif hash[:type_].id == Slice.id %}
            json.field %field, %value.id.try(&.to_s(""))
          {% elsif hash[:type_].id == BSON::ObjectId.id %}
            json.field %field, %value.to_s
          {% elsif hash[:type_].id == Array(String).id %}
            if v = %value.as?(Array(String))
              json.field %field, v.join(",")
            end
          {% else %}
            json.field %field, %value
          {% end %}
        {% end %}

        {% if SETTINGS[:timestamps] %}
          json.field "created_at", created_at.to_s
          json.field "updated_at", updated_at.to_s
        {% end %}
      end
    end

    def to_json
      JSON.build do |json|
        json.object do
          json.field "{{PRIMARY[:name]}}", {{PRIMARY[:name]}} ? {{PRIMARY[:name]}}.to_s : nil

          {% for name, hash in FIELDS %}
            %field, %value = "{{name.id}}", {{name.id}}
            {% if hash[:type_].id == Time.id %}
              json.field %field, %value.to_s
            {% elsif hash[:type_].id == Slice.id %}
              json.field %field, %value.id.try(&.to_s(""))
            {% elsif hash[:type_].id == BSON::ObjectId.id %}
              json.field %field, %value.to_s
            {% elsif hash[:type_].id == Array(String).id %}
              if v = %value.as?(Array(String))
                json.field %field, v.join(",")
              end
            {% else %}
              json.field %field, %value
            {% end %}
          {% end %}

          {% if SETTINGS[:timestamps] %}
            json.field "created_at", created_at.to_s
            json.field "updated_at", updated_at.to_s
          {% end %}
        end
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

    def set_string_array(name : String, value : Array(String))
      case name
        {% for _name, hash in SPECIAL_FIELDS %}
        when "{{_name.id}}"
          {% if hash[:type_].id == String.id %}            
            @{{_name.id}} = value         
          {% end %}
        {% end %}
        else
          puts "set_string_array field not found: #{name}"
      end
    end

    def mark_dirty(field_name : String)
      @dirty_fields << field_name
    end
  
    def unmark_dirty(field_name : String)
      @dirty_fields.delete(field_name)
    end
  
    def dirty_fields_to_bson
      self.to_bson(true, true)
    end
  
    def dirty?
      @dirty_fields.size > 0
    end
  
    def clear_dirty
      @dirty_fields.clear
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
               @{{_name.id}} = Time.parse_utc(value.to_s, "%F %X").to_utc
             end                    
          {% else %}
            @{{_name.id}} = value.to_s
          {% end %}
        {% end %}
      end
    end
  end
end
