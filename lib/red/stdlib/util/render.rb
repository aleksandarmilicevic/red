require 'red/model/marshalling'

module RedLib
module Util

  #===========================================================
  # Data model
  #===========================================================

  Red::Dsl.data_model do
  end

  #===========================================================
  # Event model
  #===========================================================

  Red::Dsl.event_model do
    event RenderTemplate do
      include Red::Model::Marshalling

      params {{
          name: String,
          vars: Hash
        }}

      ensures {
        opts = {
          :partial => name,
          :locals => vars || {}
        }
        
        Red.boss.thr(:controller).send :render_to_string, opts
      }
    end
    
    event RenderRecord do
      include Red::Model::Marshalling

      params {{
          record: Red::Model::Record,
          options: Hash
        }}

      requires {
        check_present :options, :record
      }

      ensures {
        opts = {:object => record}
        (options || {}).each {|key, val|
          opts.merge!({key.to_sym => val})
        }

        autoview = to_bool(opts.delete(:autoview))
        if autoview
          error "autoview not implemented"
        else
          Red.boss.thr(:controller).send :render_to_string, opts
        end
      }
    end
  end

end
end
