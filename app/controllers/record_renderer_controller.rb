class RecordRendererController < RedAppController

  def index
    target = params[:record]
    error "No record specified" unless target
    if Array === target
      records = unmarshal_to_array(target) rescue nil
    else
      record = unmarshal_to_record(target) rescue nil
    end
    error "Could not find record: #{record_hash.inspect}" unless record || records

    opts = record ? {:object => record} : {:collection => records}
    (params[:options] || {}).each {|key, val| 
      opts.merge!({key.to_sym => val})
    }

    autoview = to_bool(opts.delete(:autoview))
    if autoview
      error "autoview not implemented"
    else
      render opts
    end
  end

end
