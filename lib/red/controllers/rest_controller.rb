module Red
  module Controllers
    module MRedRestController

      def self.included(cls)
        cls.send :before_filter, :extract_info
      end

      # GET /<resource>.json (e.g., GET /posts.json)
      def index
        ids = params[:ids] || params[:id]
        @records = if ids
                     @record_cls.find(ids)
                   else
                     @record_cls.all
                   end
        render_json @records
      end

      # GET /<resource>/<id>.json  (e.g., GET /posts/1.json)
      def show
        # @record = @record_cls.find(params[:id])
        # #instance_variable_set("@#{params[:resource].singularize}".to_sym, @record)
        
        respond
      end

      # GET /<resource>/new.json (e.g., GET /posts/new.json)
      def new
        @record = @record_cls.new

        render_json @record
      end

      # GET /<resource>/<id>/edit
      def edit
        show
      end

      # POST /<resource> (e.g., POST /posts.json)
      def create
        params_key = params[:resource].singularize.to_sym
        @record = @record_cls.new(params[params_key])

        if @post.save
          render_json @post, status: :created, location: @post
        else
          render_json @post.errors, status: :unprocessable_entity
        end
      end

      # PUT /posts/1
      # PUT /posts/1.json
      def update
        params_key = @resource.singularize.to_sym
        fail if @record.nil?
        if @record.update_attributes(params[params_key])
          head :no_content
        else
          respond
        end
      end

      # DELETE /<resource>/<id>.json (e.g., DELETE /posts/1.json)
      def destroy
        @record.destroy

        head :no_content
      end

      protected

      def render_json(target, hash={})
        # opts = hash.merge :json => target, :root => @resource.singularize
        # render opts

        if target.kind_of?(ActiveRecord::Relation) || target.kind_of?(Array)
          root = @resource.pluralize
        else
          root = @resource.singularize
        end
        json = { root => target.as_red_json({:root => false}) }
        render :text => json.to_json
      end

      def extract_info
        @record_id  = params[:id]
        @record     = params[:record]
        @record_cls = params[:klass]
        @resource   = params[:resource].to_s || request.path

        @record = self.instance_eval &@record if @record.is_a?(Proc)

        @record_cls =
          (@record.class if @record) ||
           (@record_cls) ||
           (Red.meta.record_or_machine(@resource.classify.singularize) if @resource)

           @resource ||= (@record_cls.name.underscore if @record_cls)
           unless @record_cls
             if @resource
               fail("No #{@resource} record class found")
             else
               fail "No record class specified"
             end
           end

           if @record_id && !@record
             @record = @record_cls.find(@record_id)
           end

           @aliases = Array(params[:record_alias]) + Array(params[:record_aliases])
           @aliases.each {|a| instance_variable_set "@#{a}", @record}
         end
    end

    def respond
      respond_to do |format|
        format.html { render :template => "#{@resource}/#{params[:action]}" }
        format.json { render_json @record }
      end
    end
  end
end
