require "./error"

module Mongo::ORM::Validators
  property errors = [] of Error

  macro included
    macro inherited
      @@validators = Array({field: Symbol, message: String, block: Proc(self, Bool)}).new
    end
  end

  macro validate(message, block)
    @@validators << {field: :base, message: {{message}}, block: {{block}}}
  end

  macro validate(field, message, block)
    @@validators << {field: {{field}}, message: {{message}}, block: {{block}}}
  end

  def valid?
    @@validators.each do |validator|
      unless validator[:block].call(self)
        errors << Error.new(validator[:field], validator[:message])
      end
    end
    errors.empty?
  end

  def error_messages
    errors.map{|err| err.to_s}
  end
end
