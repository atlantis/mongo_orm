class BSON
  def []=(key, value : Mongo::ORM::EmbeddedDocument)
    self[key] = value.to_bson
  end

  def []=(key, value : Array)
    self[key] = value.to_bson
  end
end

module Mongo::ORM::EmbeddedBSON
  macro extended
    macro __process_embedded_bson

      def self.from_bson(bson : BSON)
        model = \{{@type.name.id}}.new
        fields = {} of String => Bool
        \{% for name, hash in FIELDS %}
          fields["\{{name.id}}"] = true
          if \{{hash[:type_].id}}.is_a? Mongo::ORM::EmbeddedDocument.class
            model.\{{name.id}} = \{{hash[:type_].id}}.from_bson(bson["\{{name}}"])
          # elsif \ { { hash[:type_].id}}.is_a? Array(String)
          #   model.\ { { name.id}} = [] of String
          elsif bson.has_key?("\{{name}}")
            model.\{{name.id}} = bson["\{{name}}"].as(Union(\{{hash[:type_].id}} | Nil))
          elsif !bson.has_key?("\{{name}}") && \{{hash}}.has_key?(:default)
            \{{hash[:default]}}
          end
          \{% if hash[:type_].id == Time %}
            model.\{{name.id}} = model.\{{name.id}}.not_nil!.to_utc if model.\{{name.id}}
          \{% end %}
        \{% end %}
        model
      end

      def to_bson(exclude_nil = true)
        bson = BSON.new
        \{% for name, hash in FIELDS %}
          if \{{hash[:type_].id}} == Array(String)
            if as_a = \{{name.id}}.as?(Array(String))
              bson.append_array(\{{name.stringify}}) do |array_appender|
                as_a.each do |strval|
                  if s = strval.as?(String)
                    array_appender << strval
                  end
                end
              end
            end
          else
						if self.\{{name.id}} != nil || !exclude_nil
							bson["\{{name}}"] = \{{name.id}}.as(Union(\{{hash[:type_].id}} | Nil))
						end
          end
        \{% end %}
        bson
      end
    end
  end
end
