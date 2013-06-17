class RestController < RedAppController
  
  before_filter :extract_info
  before_filter :start_listener
  after_filter  :stop_listener
  
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
    @record = @record_cls.find(params[:id])
    #instance_variable_set("@#{params[:resource].singularize}".to_sym, @record)
    
    render_json @record
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
    params_key = params[:resource].singularize.to_sym
    @record = @record_cls.find(params[:id])
    
    if @post.update_attributes(params[params_key])
      head :no_content
    else
      render_json @post.errors, status: :unprocessable_entity
    end
  end

  # DELETE /<resource>/<id>.json (e.g., DELETE /posts/1.json)
  def destroy
    @record = @record_cls.find(params[:id])
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

  def start_listener
    @lstner = Red.boss.client_listener(client)
    @lstner.start_listening if @lstner
  end

  def stop_listener
    @lstner.stop_listening if @lstner
  end

  def extract_info
    @resource = params[:resource] 
    fail "No record class specified" unless @resource
     
    @record_name = @resource.classify
     
    @record_cls = Red.meta.record(@record_name) || Red.meta.machine(@record_name)
    fail "No #{@record_name} record found" unless @record_cls    
  end
      
end
