require "json"

module Mongo::ORM::Fields
  alias SingleType = JSON::Any | DB::Any | Mongo::ORM::EmbeddedDocument
  alias Type = SingleType | Array(Mongo::ORM::EmbeddedDocument) | Array(String) | Array(BSON::ObjectId)
  TIME_FORMAT_REGEX = /\d{4,}-\d{2,}-\d{2,}\s\d{2,}:\d{2,}:\d{2,}/

  macro included
    macro inherited
      FIELDS = {} of Nil => Nil
			SPECIAL_FIELDS = {} of Nil => Nil

			@[JSON::Field(ignore: true)]
			getter? original_values = {} of String => Type

      @[JSON::Field(ignore: true)]
      getter? dirty_field_names = [] of String

      @[JSON::Field(ignore: true)]
      property? destroyed = false
    end
  end

  # specify the fields you want to define and types
  macro field(decl, options = {} of Nil => Nil)
    {% not_nilable_type = decl.type.is_a?(Path) ? decl.type.resolve : (decl.type.is_a?(Union) ? decl.type.types.reject(&.resolve.nilable?).first : (decl.type.is_a?(Generic) ? decl.type.resolve : decl.type)) %}
    {% nilable = (decl.type.is_a?(Path) ? decl.type.resolve.nilable? : (decl.type.is_a?(Union) ? decl.type.types.any?(&.resolve.nilable?) : (decl.type.is_a?(Generic) ? decl.type.resolve.nilable? : decl.type.nilable?))) %}
    {% hash = {type: not_nilable_type, nillable: nilable} %}
    {% if !decl.value.is_a?(Nop) %}
			{% hash[:default] = decl.value %}
    {% end %}
    {% FIELDS[decl.var] = hash %}
  end

  macro embeds(decl)
    {% FIELDS[decl.var] = {type: decl.type, nillable: true, embedded_document: true} %}
    #raise "can only embed classes inheriting from Mongo::ORM::EmbeddedDocument" unless {{decl.type}}.new.is_a?(Mongo::ORM::EmbeddedDocument)
  end

  macro embeds_many(children_collection)
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
				mark_dirty("{{collection_name}}")
			end
		end

    {% SPECIAL_FIELDS[collection_name] = {type: children_class} %}
  end

  # include created_at and updated_at that will automatically be updated
  macro timestamps
    {% SETTINGS[:timestamps] = true %}
  end

  macro __process_fields
    # Create the properties
		{% for name, hash in FIELDS %}
			{% unless hash[:default].nil? %}
				Log.warn {  "Setting defaulg value for field {{name.id}} to #{{{hash[:default]}}.inspect}" }
				@{{name.id}} : {{hash[:type]}}? = {{hash[:default]}}
			{% end %}

			def {{name.id}}=(new_val : {{hash[:type]}}?)
				# don't allow non-nillable fields to be set to nil
				{% unless hash[:nillable] %}
					return false if new_val.nil?
				{% end %}

				unless @{{name.id}} == new_val
					mark_dirty("{{name.id}}")
					@{{name.id}} = new_val
				end
      end

			{% if hash[:nillable] %}
				def {{name.id}} : {{hash[:type]}}?
					@{{name.id}}
				end

				#Warning - if you change this function change below too
				def {{name.id}}! : {{hash[:type]}}
					raise NilAssertionError.new {{name.stringify}} + "#" + {{name.id.stringify}} + " cannot be nil" if @{{name.id}}.nil?
					@{{name.id}}.not_nil!
				end
			{% else %}
				#Warning - if you change this function change above too
				def {{name.id}} : {{hash[:type]}}
					raise NilAssertionError.new {{name.stringify}} + "#" + {{name.id.stringify}} + " cannot be nil" if @{{name.id}}.nil?
					@{{name.id}}.not_nil!
				end
			{% end %}
    {% end %}
    {% if SETTINGS[:timestamps] %}
      property created_at : Time?
      property updated_at : Time?
    {% end %}

    # keep a hash of the fields to be used for mapping
    def multi_embeds(membeds = [] of {name: String, type: String})
      {% for name, hash in SPECIAL_FIELDS %}
      	membeds << {name: "{{name.id}}", type: "{{hash[:type].id}}"}
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
			{% for name, hash in SPECIAL_FIELDS %}
				fields << "{{name.id}}"
			{% end %}
      return fields
    end

    # keep a hash of the fields to be used for mapping
    def fields(fields = {} of String => Type | Nil)
      {% for name, hash in FIELDS %}
        fields["{{name.id}}"] = @{{name.id}}
      {% end %}
      {% if SETTINGS[:timestamps] %}
        fields["created_at"] = self.created_at
        fields["updated_at"] = self.updated_at
      {% end %}
			fields["_id"] = self._id
			{% for name, hash in SPECIAL_FIELDS %}
				{% if hash[:type].id == String.id || hash[:type].id == BSON::ObjectId.id || hash[:type].id == Int32.id || hash[:type].id == Float32.id || hash[:type].id == Int64.id || hash[:type].id == Float64.id %}
					fields["{{name.id}}"] = [] of {{hash[:type].id}}
					if docs = self.{{name.id}}.as?(Array({{hash[:type].id}}))
						fields["{{name.id}}"] = docs
					end
				{% else %}
					adocs = [] of Mongo::ORM::EmbeddedDocument
					self.{{name.id}}.each do |doc|
						adocs << doc.as(Mongo::ORM::EmbeddedDocument)
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
      {% if SETTINGS[:timestamps] %}
        parsed_params << created_at.not_nil!.to_s("%F %X")
        parsed_params << updated_at.not_nil!.to_s("%F %X")
      {% end %}
      return parsed_params
    end

    def to_h
      fields = {} of String => DB::Any

      fields[{{PRIMARY[:display_name]}}] = {{PRIMARY[:name]}}

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
        json.field {{PRIMARY[:display_name]}}, {{PRIMARY[:name]}} ? {{PRIMARY[:name]}}.to_s : nil

        {% for name, hash in FIELDS %}
          %field, %value = "{{name.id}}", {{name.id}}
          {% if hash[:type].id == Time.id %}
            json.field %field, %value.to_s
          {% elsif hash[:type].id == Slice.id %}
            json.field %field, %value.id.try(&.to_s(""))
          {% elsif hash[:type].id == BSON::ObjectId.id %}
            json.field %field, %value.to_s
          {% elsif hash[:type].id == Array(String).id %}
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
          json.field {{PRIMARY[:display_name]}}, {{PRIMARY[:name]}} ? {{PRIMARY[:name]}}.to_s : nil

          {% for name, hash in FIELDS %}
            %field, %value = "{{name.id}}", {{name.id}}
            {% if hash[:type].id == Time.id %}
              json.field %field, %value.to_s
            {% elsif hash[:type].id == Slice.id %}
              json.field %field, %value.id.try(&.to_s(""))
            {% elsif hash[:type].id == BSON::ObjectId.id %}
              json.field %field, %value.to_s
            {% elsif hash[:type].id == Array(String).id %}
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

    def mark_dirty(field_name : String)
			@dirty_field_names << field_name unless @dirty_field_names.includes?(field_name)
    end

    def unmark_dirty(field_name : String)
      @dirty_field_names.delete(field_name)
    end

    def dirty_fields_to_bson
      self.to_bson(true, true)
		end

		def nil_dirty_fields_to_bson
			bson = BSON.new
			self.dirty_fields.each do |field, value|
				if value.nil?
					bson[field] = nil
				end
			end
			bson
		end

    def dirty?
      @dirty_field_names.size > 0
    end

    def dirty?(field_name : String)
      @dirty_field_names.includes?(field_name)
		end

		def dirty_fields
			self.fields.select @dirty_field_names
    end

    def clear_dirty
			@dirty_field_names.clear
			self.cache_original_values
		end

		def cache_original_values
      @original_values = self.fields
		end

		def original_value( field_name : String )
      @original_values[field_name]
    end

    # Casts params and sets fields - make sure to use the setter function rather than direct instance variable
		private def cast_to_field(name, value : Type)
			if value.is_a?(SingleType)
				case name.to_s
					{% for _name, hash in FIELDS %}
					when "{{_name.id}}"
						self.{{_name.id}} = self.cast_single_value(value, "{{hash[:type].id}}").as?({{hash[:type].id}})
					{% end %}
				else
					Log.debug { "cast_to_field got nuthin for #{name.to_s}" }
				end
			else
				case name.to_s
					{% for _name, hash in SPECIAL_FIELDS %}
					when "{{_name.id}}"
						self.{{_name.id}} = [] of {{hash[:type].id}}
						if array_val = value.as?(Array)
							array_val.each do |each_val|
								v = self.cast_single_value(each_val, "{{hash[:type].id}}").as?({{hash[:type].id}})
								self.{{_name.id}} << v unless v.nil?
							end
              self.mark_dirty {{_name.id.stringify}}
						end
					{% end %}
				else
					Log.debug { "cast_to_field got nuthin for #{name.to_s}" }
				end
			end
		end

		private def cast_single_value(value : SingleType, klass : String) : Type
			return nil if value.nil?
			case klass
			when "BSON::ObjectId"
				value.is_a?(BSON::ObjectId) ? value : BSON::ObjectId.new(value.to_s)
			when "Int32"
				if value.is_a?(String)
					value.to_i32
				elsif value.is_a?(Int64)
					value.to_s.to_i32
				else
					value.as?(Int32)
				end
			when "Int64"
				value.is_a?(String) ? value.to_i64 : value.as?(Int64)
			when "Float32"
				if value.is_a?(String)
					value.to_f32
				elsif value.is_a?(Float64)
					value.to_s.to_f32
				else
					value.as?(Float32)
				end
			when "Float64"
				value.is_a?(String) ? value.to_f64 : value.as?(Float64)
			when "Bool"
				["1", "yes", "true", true].includes?(value)
			when "Time"
				if value.is_a?(Time)
					value.to_utc
				elsif value.to_s =~ TIME_FORMAT_REGEX
					Time.parse_utc(value.to_s, "%F %X").to_utc
				end
			when "String"
				value.to_s
			else
				nil
			end
		end
  end
end
