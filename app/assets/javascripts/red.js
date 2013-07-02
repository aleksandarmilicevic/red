var Red = (function() {
  // ============================================================
  // private stuff
  // ============================================================
  var me = {
    EventMeta : function() {},
    RecordMeta :  function() {},

    construct : function(name) {
      eval('var ' + name + ' = function (){};');
      return eval('new ' + name + ';');
    },

    defineRecordNonEnumProps : function(record) {
      var func = function() {return record.__type__; };
      Object.defineProperty(record, "name", {value: func});
      Object.defineProperty(record, "type", {value: func});
      Object.defineProperty(record, "meta", {value: new me.RecordMeta()});
    },

    defineEventNonEnumProps : function(event) {
    },

    check_defined : function(x, msg) {
      if (x === undefined) throw Error(msg);
    },

    sweepDom : function(from, to, html) {
      if (!(from.size() == 1 && to.size() == 1)) {
        var msg = "inconsistent start/end tags: #startTag = " +
            from.size() + ", #endTag = " + to.size();
        console.error(msg);
        return;
      }
      from.nextUntil(to).detach();
      from.after(html);
      from.detach();
      to.detach();
    },

    searchDom : function(node_id, html) {
      //TODO: cache this stuff somehow
      var startTag = "reds_" + node_id;
      var endTag = "rede_" + node_id;
      var startTagStr = "<" + startTag + ">";
      var endTagStr = "</" + endTag + ">";
      var elements = document.getElementsByTagName("*");
      for (var i = 0; i < elements.length; i++) {
        var element = elements[i];
        if (element.tagName.toLowerCase() === startTag) {
          me.sweepDom($(element), $("rede_" + node_id), html);
          return;
        }
        var attr = element.attributes;
        for (var j = 0; j < attr.length; j++) {
          var attrVal = attr[j].nodeValue;
          var startIdx = attrVal.indexOf(startTagStr);
          if (startIdx != -1) {
            var endIdx = attrVal.indexOf(endTagStr);
            if (endIdx != -1) {
              attr[j].nodeValue = attrVal.substring(0, startIdx) + html + attrVal.substring(endIdx + endTagStr.length);
              return;
            } else {
              console.error("start but not end tag found in attribute " + attrVal);
            }
          }
        }
      }
    }
  };

  // ============================================================
  //   Some meta stuff about the underlying Red model
  // ============================================================

  var Meta = {
    modelForRecord : function(recordName) {
      return this.record2model[recordName];
    }
  };

  // ============================================================
  //  Simulates jQuery's jqXHR type.
  // ============================================================

  var MyXHR = function() {
    var proto = {
      doneFuncs: [],
      failFuncs: [],
      alwaysFuncs: [],

      done:   function(doneFunc)   {
        this.doneFuncs.push(doneFunc);
        return this;
      },

      fail:   function(failFunc)   {
        this.failFuncs.push(failFunc);
        return this;
      },

      always: function(alwaysFunc) {
        this.alwaysFuncs.push(alwaysFunc);
        return this;
      }
    };
    jQuery.extend(this, proto);
  };

  // ============================================================
  //   Various utility functions
  // ============================================================

  var Utils = {

    defaultTo : function(val, defaultVal) {
      if (typeof(val) === "undefined") {
        return defaultVal;
      } else {
        return val;
      }
    },

    toggleShow : function($elem, opts) {
      if ($elem.attr('disabled')) return false;
      $elem.attr('disabled', 'disabled');
      opts = Red.Utils.defaultTo(opts, {});  
      var $target = opts.target || $(Utils.readData($elem, 'toggle-show'));
      var effect = opts.effect || Utils.readData($elem, 'effect') || "blind";
      var animOpts = opts.animOptions || 
            Utils.readData($elem, 'anim-opts') || 
            {direction: "up"};
       var dur = opts.duration || Utils.readData($elem, 'duration') || 500;

       var cb = function() { $elem.removeAttr('disabled'); };

       var showing = $target.is(":visible");
       if (showing) {
         $target.hide(effect, animOpts, dur, cb);
       } else {
         $target.show(effect, animOpts, dur, cb);
       }
       return false;
     },

     /* ----------------------------------------------------------------
      * 
      * Asynchronously fires up a server-side action.  
      * 
      * Function used for this async call is
      * 
      *   - `hash.method'         when hash.method is a function
      *   - jQuery.<hash.method>  when hash.method is a string
      *   - jQuery.get            otherwise
      * 
      * If `hash.url' is present, it simply send a request to that URL.
      * Otherwise, it builds the URL from a number of Rails-like
      * parameters:
      * 
      *   - controller
      *   - action
      *   - format 
      *   - params
      * 
      * The URL pattern is
      * 
      *   '/${controller}#${action}.#{format}?#{params}'
      * 
      * @param requestOpts: {
      *          url: string, 
      *          controller: string,
      *          format: string,
      *          action: string,
      *          params: object,
      *          method: string || function,
      *        }
      * 
      * @return jqXHR
      * 
      * ---------------------------------------------------------------- */
     remoteAction : function(requestOpts) {
       if (typeof(requestOpts) === 'undefined') { requestOpts = {}; }
       var url = "";
       var method = jQuery.get;
       if (typeof(requestOpts) === 'object') {
         url = "/";
         if (requestOpts.controller) url += requestOpts.controller;
         if (requestOpts.action) url += '#' + requestOpts.action;
         if (requestOpts.format) url += '.' + requestOpts.format;
         if (requestOpts.params) url += '?' + jQuery.param(requestOpts.params);
         if (typeof(requestOpts.method) === "string") {
           method = eval('jQuery.' + requestOpts.method);
         } else if (typeof(requestOpts.method) === "function") {
           method = requestOpts.method;
         }
       } else {
         url = "" + requestOpts;
       }
       return method(url, function() {});
     },

     /* ----------------------------------------------------------------
      * 
      * Asynchrounously fires up a request to remotely render a given
      * record and send back the rendered HTML.
      * 
      * By default sends a GET request to the "recordRenderer"
      * controller with parameters including the given record and the
      * rendering options.  These request options can be overriden
      * by the user. 
      * 
      * @param record [Red.Record]  - record to be rendered
      * @param renderOpts [object]  - server-side rendering options 
      * @param requestOpts [object] - remoteAction request options
      * 
      * @return jqXHR
      * 
      * ---------------------------------------------------------------- */
     remoteRenderRecord : function(record, renderOpts, requestOpts) {
       if (typeof(renderOpts) === 'undefined')  { renderOpts = {}; }
       if (typeof(requestOpts) === 'undefined') { requestOpts = {}; }
       var params = {
         record: record,
         options: jQuery.extend({
           autoview: false
         }, renderOpts)
       };
       var hash = jQuery.extend({
           controller: "recordRenderer",
           params: params,
           method: "get"
       }, requestOpts);
       return Utils.remoteAction(hash);
     },

     /* ----------------------------------------------------------------
      * 
      * Reads the attribute value from a jQuery element, with some
      * additional processing.
      * 
      *   - returns `undefined' if f no attribute with `paramName' is
      *     defined in `elem'.
      * 
      *   - when the attribute value matches /^\$\{.*\}$/, evaluates
      *     the string inside ${}.  If the result is a jQuery array, 
      *     it turns it into a regular Javascript array (by calling
      *     `jQuery.makeArray' on it. 
      * 
      * @param elem [jQuery]       - a jQuery element
      * @param paramName [string]  - name of the attribute to be read from `elem'
      * 
      * @return undefined || string || anything (result of `eval')
      * 
      * ---------------------------------------------------------------- */
     readParamValue : function(elem, paramName) {
       var $elem = $(elem);
       var paramValue = $elem.attr(paramName);

       if (paramValue === undefined) return undefined;

       // eval if matches /^\$\{.*\}$/
       var len = paramValue.length;
       if (paramValue.substring(0, 2) === "${" &&
         paramValue.substring(len-1, len) === "}") {
         paramValue = eval(paramValue.substring(2, len-1));
         if (paramValue instanceof jQuery) {
           paramValue = jQuery.makeArray(paramValue);
         }
       }
       return paramValue;
     },

    readData : function(elem, name) {
      return Utils.readParamValue(elem, "data-" + name);
    },

    /* ----------------------------------------------------------------
     * 
     * Takes an array of "actions" (`actions') and a hash of callbacks
     * (`cb').  Executes one action at a time, and as soon as one
     * action fails it calls `cb.fail' and stops the process.  Only if
     * all actions succeed, `cb.done' is called.  At the end of the
     * process (regardless of whether it succeeded or failed)
     * `cb.always' is called.
     * 
     * An "action" is a no-arg function which return an XHR kind of
     * object (e.g., `jqXHR', `Red.MyXHR' or anything that allows
     * "done", "fail" and "always" callbacks to be assigned).
     * 
     * @param actions [array(function)] - a list of actions
     * @param cb : {
     *          done:   function
     *          fail:   function
     *          always: function
     *        }
     * 
     * @return undefined
     * 
     * ---------------------------------------------------------------- */
    chainActions : function(actions, cb) {
      return function() {
        if (actions.length == 0) throw new Error("0 actions not allowed");
        var action = actions.shift();
        var doneFunc = null; 
        if (actions.length == 0)
          doneFunc = function(r) {
            if (cb.done) cb.done(r); 
            if (cb.always) cb.always(r);
          };
        else 
          doneFunc = function(r) { Utils.chainActions(actions, cb)(); };
        action()
          .done(doneFunc)
          .fail(function(r)   { if (cb.fail) cb.fail(r);});
      };
    },

    /* ----------------------------------------------------------------
     * 
     * Implements a transition protocol for updating a DOM
     * element. This protocol looks something like this.
     *                        
     *  -- addClass(updating, upStartDur)
     *    `-- action()
     *       `-- <action done>
     *          `-- removeClass(updating, upEndDur)
     *             `-- addClass(update-ok, duration)
     *                `-- hash.done()
     *                 -- sleep(timeout)
     *                   `-- removeClass(updateOk)
     *       `-- <action fail>
     *          `-- removeClass(updating, upEndDur)
     *             `-- addClass(update-fail, duration)
     *                `-- hash.fail()
     *                 -- sleep(timeout)
     *                   `-- removeClass(updateFail)
     *       `-- <whatever>
     *          `-- removeClass(updating, upEndDur)
     *             `-- hash.always()
     *           
     * 
     * This allows animations to be specified via the CSS
     * classes. First "${cls}-updating" is added to the element and is
     * animated for the `upStartDur' number of milliseconds, next the
     * action (`opts.action' or chained `opts.actions') is issued,
     * upon whose completion the "${cls}-updating" class is removed,
     * "${cls}-update-<ok/fail>" class is animated for the
     * `opts.duration' number of milliseconds, user callback
     * (`opts.done' or `opts.fail') is called, and finally after a
     * timeout (`opts.timeout') the ok/fail class is removed.
     * 
     * @param $elem : jQuery - a jQuery element
     * @param cb : {
     *          action:  function        - action to be performed
     *          actions: array(function) - a chain of actions to be performed
     *          upStartDur: number       - begin updating animation duration
     *          upEndDur: number         - end updating animation duration
     *          duration: number         - begin ok/fail animation duration
     *          timeout: number          - time to wait before removing the ok/fail class
     *          done:   function         - ok callback
     *          fail:   function         - fail callback
     *          always: function         - always callback
     *        }
     * 
     * @return undefined
     * 
     * ---------------------------------------------------------------- */
    asyncUpdate : function($elem, cls, opts) {
      var oldHtml = $elem.html();
      var updatingCls = cls + "-updating";
      var okCls = cls + "-update-ok";
      var failCls = cls + "-update-fail";

      var duration = opts.duration || 200;
      var timeout = opts.timeout || 800;
      var upStartDur = opts.upStartDur || opts.duration || "fast";
      var upEndDur = opts.upEndDur || opts.duration || 0;
      var actions = opts.actions || [opts.action];

      var myAddClass = function(el, cls, speed, cont) {
        if (speed) { el.addClass(cls, speed, cont); }
        else       { el.addClass(cls); if (cont) cont(); }
      };

      var myRemoveClass = function(el, cls, speed, cont) {
        if (speed) { el.removeClass(cls, speed, cont); }
        else       { el.removeClass(cls); if (cont) cont(); }
      };

      myAddClass($elem, updatingCls, upStartDur, function(){
        Utils.chainActions(actions, {
          done: function(r) {
            myRemoveClass($elem, updatingCls, upEndDur, function() {
              if (opts.done) { opts.done(r); } else { $elem.html(r); }
              myAddClass($elem, okCls, duration, function() {
                setTimeout(function() {myRemoveClass($elem, okCls);}, timeout);
              });
            });
          },
          fail: function(r) {
            myRemoveClass($elem, updatingCls, upEndDur, function() {
              if (opts.fail) { opts.fail(r); }
              myAddClass($elem, failCls, duration, function() {
                setTimeout(function() {myRemoveClass($elem, failCls);}, timeout);
              });
            });
          },
          always: function(r) {
            myRemoveClass($elem, updatingCls, upEndDur, function() {
              if (opts.always) { opts.always(r); }
            });
          }
        })();
      });
    },

    /* ----------------------------------------------------------------
     * 
     * Goes through all undefined parameters (`undefParams') and asks
     * the user to provide values for them.  Once all values have been
     * provided, it calles the continuation function `triggerFunc'.
     *
     * Rules for asking the user to provide missing parameter values:
     *
     *   - if the parameter is of a primitive type, it simply prompts
     *     for a string value
     *
     *   - if the parameter is a file, it dynamically creates a form
     *     with a file input, and an iframe in order to achieve
     *     ajax-like file upload.
     *
     *   - if the parameter is of a record type, it shows a browse
     *     widget where the user can select an object.
     * 
     * @param $elem       : jQuery    - a jQuery element
     * @param ev          : Red.Event - a Red event
     * @param undefParams : array     - list of parameters to prompt the
     *                                  user
     * @param triggerFunc : function  - continuation to run after all
     *                                  parameter values have been collected
     * 
     * @return undefined
     * 
     * ---------------------------------------------------------------- */
    askParams : function($elem, ev, undefParams, triggerFunc) {
      if (undefParams.length === 0) {
        $elem.removeData('file-form');
        triggerFunc();
        return;
      }
      var elemId = $elem.attr("id");
      var param = undefParams.shift();
      if (param.isFile) {
        var uploadDiv = null;
        var iframe = null;
        var fileForm = $elem.data('file-form');
        if (typeof(fileForm) === "undefined") {
          uploadDiv = $('<div><form></form><iframe></iframe></div>');
          fileForm = $(uploadDiv.children()[0]);
          iframe = $(uploadDiv.children()[1]);

          uploadDiv.hide();

          var csrf = $('<input type="hidden" name="authenticity_token"></input>');
          csrf.val($('meta[name="csrf-token"]').attr("content"));
          fileForm.append(csrf);

          iframe.attr('id', elemId + "_upload_target");
          iframe.attr('name', iframe.attr('id'));
          iframe.attr('src', '#');
          iframe.attr('style', 'width:0;height:0;border:0px solid #fff;');

          fileForm.attr('method', 'post');
          fileForm.attr('enctype', 'multipart/form-data');
          fileForm.attr('target', iframe.attr('id'));

          ev.viaForm = fileForm;

          $elem.data('file-form', fileForm);
          $elem.after(uploadDiv);
        } else {
          uploadDiv = fileForm.parent();
          iframe = fileForm.next();
        }

        var fileInput = $('<input type="file"></input>');
        fileInput.attr('name', param.name);
        fileForm.append(fileInput);
        fileInput.bind("change", function(){
          ev.params[param.name] = $(this).val();
          Utils.askParams($elem, ev, undefParams, triggerFunc);
        });
        fileInput.trigger("click");
      } else if (param.isPrimitive) {
        ev.params[param.name] =  window.prompt(param.name, "");
        Utils.askParams($elem, ev, undefParams, triggerFunc);
      } else if (param.isRecord) {
        alert("Missing Record parameters (" + param.name + ") not implemented");
      } else {
        console.debug("Unsupported parameter kind:");
        console.debug(param);
        throw new Error("unsupported parameter kind");
      }
    },

    /* ---------------------------------------------------------------- 
     * 
     * Creates event declaratively specified through element's data
     * attributes:
     *
     *  - event name is read from either 'data-trigger-event' or
     *    'data-event-name' attribute
     * 
     *  - event parameters are read from 'data-param-*' attributes
     * 
     * @param $elem : jQuery    - a jQuery element
     * 
     * ---------------------------------------------------------------- */
    declCreateEvent : function($elem) {
      var eventName = $elem.attr("data-trigger-event") ||
            $elem.attr("data-event-name");
      var ev = eval('new ' + eventName + '({})');
      var undefParams = [];
      for (var i = 0; i < ev.meta.params.length; i++) {
        var param = ev.meta.params[i];
        var paramName = param.name;
        var paramValue = Utils.readParamValue($elem, "data-param-" + paramName);
        if (paramValue === undefined) {
          undefParams.push(param);
        }
        ev.params[paramName] = paramValue;
      }
      return { event: ev, undefParams: undefParams };
    },

    /* ---------------------------------------------------------------- 
     * 
     * Creates event declaratively specified through element's data
     * attributes (via the Utils.declCreateEvent func), and then
     *
     *  - prompts for missing parameters
     * 
     *  - fires the event asynchronously (via jQuery.post)
     * 
     *  - triggers either ${eventName}Done or ${eventName}Failed
     *    handler (if bound) after the event has been executed
     * 
     * @param $elem : jQuery    - a jQuery element
     * 
     * @return undefined
     * 
     * ---------------------------------------------------------------- */
    declTriggerEvent : function($elem) {
      if ($elem.attr("disabled") === "disabled")
        return;

      var ans = Utils.declCreateEvent($elem);
      var ev = ans.event;
      var undefParams = ans.undefParams;
      var eventName = ev.meta.shortName;

      Utils.askParams($elem, ev, undefParams, function() {
        $elem.trigger(eventName + "Triggered", [ev]);
        if (!ev.canceled) {
          ev.fire(
          ).done(function(response) {
            $elem.trigger(eventName + "Done", [response]);
          }).fail(function(response) {
            $elem.trigger(eventName + "Failed", [response]);
          });
        }
      });
    }
  };

  var PubSub = {

  };

  var Red = {

    // ===============================================================
    //   publish subscribe
    // ===============================================================
    publish_status_kind : function(kind, msg) {
      Red.publish({
        "type" : "status_message",
        "payload" : {
          "kind" : kind,
          "msg" : msg
        }
      });
    },

    publish_status : function(msg) {
      Red.publish_status_kind("status", msg);
    },
    publish_warning : function(msg) {
      Red.publish_status_kind("warning", msg);
    },
    publish_error : function(msg) {
      Red.publish_status_kind("error", msg);
    },

    // ===============================================================
    //   publish subscribe
    // ===============================================================

    Meta : $.extend({}, Meta),

    Utils : $.extend({}, Utils),

    // ===============================================================
    //   AST: records/events
    // ===============================================================

    /* ----------------------------------------------------------------
     *   Creates a new Record object.
     * ---------------------------------------------------------------- */
    record : function(type, props) {
      var that = me.construct("Record");

      that.is_record = true;

      var recordProps = $.extend({__type__: type}, props);
      for (p in recordProps) {
        that[p] = recordProps[p];
      }

      me.defineRecordNonEnumProps(that);

      /* ----------------------------------------------------------------
       * 
       * Extends a given "obj" object to include all the properties
       * (including the non-enumerable ones) of this.
       * 
       * ---------------------------------------------------------------- */
      Object.defineProperty(that, "cloneOnto", {
        enumerable: false,
        value: function(obj) {
          $.extend(obj, this);
          me.defineRecordNonEnumProps(obj);
          return obj;
        }
      });

      return that;
    },

    /* ----------------------------------------------------------------
     * 
     *   Creates a new Event object.
     * 
     * ---------------------------------------------------------------- */
    event : function(name, params) {
      var that = me.construct("Event");

      that.is_event = true;
      that.name     = name;
      that.params   = params;
      that.meta     = new me.EventMeta();
      that.viaForm  = undefined;

      that.canceled = false;
      that.cancel   = function() { this.canceled = true; };

      that.fire = function(cb) {
        cb = Utils.defaultTo(cb, function(response) {});
        if (this.viaForm) {
          return this.fireViaForm(this.viaForm, cb);
        } else {
          return this.fireDirectly(cb);
        }
      };

      /* ----------------------------------------------------------------
       * 
       * Fires this event by submitting a form to this events action URL. 
       * 
       * This is used mainly for file uploads, when an event requires 
       * a file parameter. 
       * 
       * If the form has a 'target' attribute pointing to an iframe,
       * it binds an 'onload' handler to that iframe, which simply
       * emits a 'done' event (through the returned MyXHR object) when
       * the iframe is loaded.
       * 
       * ---------------------------------------------------------------- */
      that.fireViaForm = function(form, cb) {
        cb = Utils.defaultTo(cb, function(response) {});
        Object.defineProperty(this, "fired", {value: true});

        if (!(typeof(form) === "object")) {
          form = $(form);
        }

        var iframe = $("#" + form.attr("target"));
        var myXHR = new MyXHR();
        iframe.load(function(){
          for (var i=0; i < myXHR.doneFuncs.length; i++) {
            myXHR.doneFuncs[i](iframe);
          }
          for (i=0; i < myXHR.alwaysFuncs.length; i++) {
            myXHR.alwaysFuncs[i](iframe);
          }
          $(iframe).parent().detach();
        });
        form.attr("action", this.actionUrl());
        form.submit();
        return myXHR;
      };

      /* ----------------------------------------------------------------
       * Fires an Ajax POST request to this events action URL. 
       * 
       * Returns the same XHR object returned by jQuery.post. 
       * ---------------------------------------------------------------- */
      that.fireDirectly = function(cb) {
        cb = Utils.defaultTo(cb, function(response) {});
        Object.defineProperty(this, "fired", {value: true});

        var url = this.actionUrl();
        return jQuery.post(url, cb);
      };

      /* ----------------------------------------------------------------
       * 
       * Returns an URL where where a POST request should be sent to
       * trigger this event.  This URL encodes the event name and the
       * values of event parameters.
       * 
       * ---------------------------------------------------------------- */
      that.actionUrl = function() {
        var urlParams = {
            event : this.name,
            params : this.params
        };
        // TODO: auth token?
        return "/event?" + jQuery.param(urlParams);
      };

      /* ----------------------------------------------------------------
       * 
       * Extends a given "obj" object to include all the properties
       * (including the non-enumerable ones) of this.
       * 
       * ---------------------------------------------------------------- */
      that.cloneOnto = function(obj) {
        jQuery.extend(obj, this);
        me.defineEventNonEnumProps(obj);
        return obj;
      };

      return that;
    },

    // must call with new, better to call record instead
    Record : function(props) {
      $.extend(this, Red.record(props));
    },

    // must call with new, better to call event instead
    Event : function(name, params) {
      $.extend(this, Red.event(name, params));
    },

    createRecord : function(recordClass, recordId) {
      return Red.record(recordClass, {"id": recordId });
    },

    fireEvent : function(eventName, params, cb) {
      Red.event(eventName, params).fire(cb);
    },

    // ===============================================================
    //   handlers
    // ===============================================================

    logMessages : function(data) {
      console.debug("[RED] update received; type:" + data.type + ", payload: " + JSON.stringify(data.payload));
    },

    /**
     */
    updateReceived : function(data) {
      var updateStart = new Date().getTime();
      me.check_defined(data.type, "malformed JSON update: field 'type' not found");
      if (data.type === "record_update") {
        me.check_defined(data.payload, "field 'payload' not found in a 'record_update' message");
        var store = DS.get('defaultStore');
        var loader = DS.loaderFor(store);
        loader.load = function(type, data, prematerialized) {
          prematerialized = prematerialized || {};
          return store.load(type, data, prematerialized);
        };
        for (var i = 0; i < data.payload.length; i++) {
          var elem = data.payload[i];
          var cls = Red.Meta.modelForRecord(elem.record_type);
          DS.JSONSerializer.create().extract(loader, elem.json, cls, null);
        }
      } else if (data.type === "node_update") {
        me.check_defined(data.payload, "field 'payload' not found in a 'node_update' message");
        me.check_defined(data.payload.node_id, "field 'payload.node_id' not found in a 'node_update' message");
        me.check_defined(data.payload.inner_html, "field 'payload.inner_html' not found in a 'node_update' message");
        me.searchDom(data.payload.node_id, data.payload.inner_html);

        // var reds = $('reds_'+data.payload.node_id);
        // var rede = $('rede_'+data.payload.node_id);
        // if (reds.size() > 0) {
        // me.sweepDom(reds, rede, data.payload.inner_html);
        // } else {
        // var start = new Date().getTime();
        // me.searchAttributes(data.payload.node_id, data.payload.inner_html);
        // var end = new Date().getTime();
        // var time = end - start;
        // console.debug('Start time: ' + start);
        // console.debug('End time: ' + end);
        // console.debug('Execution time: ' + time);
        // }
      } else if (data.type === "body_update") {
        me.check_defined(data.payload, "field 'payload' not found in a 'body_update' message");
        me.check_defined(data.payload.html, "field 'payload.html' not found in a 'body_update' message");
        $('body').html(data.payload.html);
      } else {
        //throw Error("unknown update message type: " + data.type)
      }
      var updateEnd = new Date().getTime();
      var time = updateEnd - updateStart;
      console.debug('Total update execution time: ' + time + "ms");
    }
  };

  return Red;
})();

