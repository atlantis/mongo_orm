module Mongo::ORM::Associations
  # define getter and setter for parent relationship
  macro belongs_to(model_name, **options)
		{%  class_name = options[:class_name] %}
		{%  nillable = options[:nillable] || false %}
    field {{class_name ? class_name.id.underscore.gsub(/::/,"_") : model_name.id}}_id : BSON::ObjectId? = nil

    # retrieve the parent relationship
    def {{model_name.id}}!
      {{class_name ? class_name.id : model_name.id.camelcase}}.find({{class_name ? class_name.id.underscore.gsub(/::/,"_") : model_name.id}}_id).not_nil!
		end

		def {{model_name.id}}
			{% if options[:nillable] %}
				if parent = {{class_name ? class_name.id : model_name.id.camelcase}}.find {{class_name ? class_name.id.underscore.gsub(/::/,"_") : model_name.id}}_id
					parent
				else
					nil
				end
			{% else %}
				self.{{model_name.id}}!
			{% end %}
    end

    # set the parent relationship
    def {{model_name.id}}=(parent)
      self.{{class_name ? class_name.id.underscore.gsub(/::/,"_") : model_name.id}}_id = parent.try &._id
    end
  end

  macro has_many(children_collection, **options)
    {%  class_name = options[:class_name] %}
    def {{children_collection.id}}
      {% children_class = class_name ? class_name.id : children_collection.id[0...-1].camelcase %}
      return [] of {{children_class}} unless self._id
      {% if options[:foreign_key] %}
        foreign_key = "{{options[:foreign_key]}}"
      {% else %}
        foreign_key = "#{self.class.to_s.underscore.gsub(/::/,"_")}_id"
      {% end %}
      {{children_class}}.all({foreign_key => self._id})
    end
  end
end
