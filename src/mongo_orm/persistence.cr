module Mongo::ORM::Persistence
  macro __process_persistence

    @updated_at : Time | Nil
    @created_at : Time | Nil

    # The save method will check to see if the primary exists yet. If it does it
    # will call the update method, otherwise it will call the create method.
    # This will update the timestamps apropriately.
    def save
			begin
        if self.valid?
        	fields_to_update = BSON.new
					__run_before_save
        	if _id
						__run_before_update
        		@updated_at = Time.utc

						if model_id = self.id
							fields_to_update = self.dirty_fields_to_bson
							fields_to_unset = self.nil_dirty_fields_to_bson
							Log.debug { "save() updating dirty fields: #{fields_to_update.inspect} unseting dirty fields: #{fields_to_unset.inspect}"}
							bson = BSON.new
							bson["$set"] = fields_to_update unless fields_to_update.empty?
							bson["$unset"] = fields_to_unset unless fields_to_unset.empty?
							unless fields_to_update.empty? && fields_to_unset.empty?
								@@collection.update({"_id" => model_id}, bson)
							else
								Log.debug { "save() skipping operation cause no dirty fields!" }
							end
						else
							@errors << Mongo::ORM::Error.new(:base, "Must have an ID to update a model")
						end
						__run_after_update
					else
						__run_before_create
						if self.id.nil?
							@created_at = Time.utc
							@updated_at = Time.utc
							self._id = BSON::ObjectId.new
							fields_to_update = self.to_bson(false, true)
							Log.debug { "save() creating fields: #{fields_to_update.inspect}"}
							@@collection.save(fields_to_update) unless fields_to_update.empty?
							__run_after_create
						else
							@errors << Mongo::ORM::Error.new(:base, "Tried to create a model that already had an id")
						end
					end
					__run_after_save
					self.clear_dirty
					return true
				else
					return false
				end
      rescue ex
        if message = ex.message
          Log.warn { "Save Exception: #{message}... fields to update: #{fields_to_update.inspect}" }
          @errors << Mongo::ORM::Error.new(:base, message)
        end
        return false
      end
		end

		def persisted?
			(self._id)
		end

    def save!
      return if save
      raise @errors.last
    end

    def destroy!
      return if destroy
      raise @errors.last
    end

    def destroyed?
      @destroyed
    end

    # Destroy will remove this from the database.
    def destroy
      raise "cannot destroy an unsaved document!" unless self._id
      begin
        __run_before_destroy
        @@collection.remove({"_id" => self._id})
        @destroyed = true
        __run_after_destroy
        return true
      rescue ex
        if message = ex.message
          puts "Destroy Exception: #{message}"
          errors << Mongo::ORM::Error.new(:base, message)
        end
        return false
      end
    end

    def delete
      begin
        __run_before_delete
        raise "cannot delete an unsaved document!" unless self._id

        if fields.includes?("deleted_at")
          {% for name, hash in FIELDS %}
            {% if name.id == "deleted_at".id %}
              if delat = self.{{name.id}}.as?(Time)
                Log.debug { "about to soft delete" }
                #make sure we JUST update the dirty field and no other changes
                self.clear_dirty
                self.deleted_at = Time.utc
                @@collection.update({"_id" => model_id}, {"$set" => self.dirty_fields_to_bson})
                self.clear_dirty
              else
                Log.warn { "Cannot delete a document that's already been deleted" }
                #but still return true cause it's done already
              end
            {% end %}
          {% end %}
        else
          Log.debug { "about to hard delete" }
          self.destroy
        end

        __run_after_delete
        return true
      rescue ex
        if message = ex.message
          Log.warn { "Save Exception: #{message} #{self.inspect}" }
          @errors << Mongo::ORM::Error.new(:base, message)
        end
        return false
      end
    end

    def delete!
      return if delete
      raise @errors.last
    end
  end
end
