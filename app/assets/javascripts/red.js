var Red = (function() {
  // ============================================================
  // private stuff
  // ============================================================
  var me = {
    assert : function(cond, msg) {
      if (!cond) {
        throw message || "Assertion failed";
      }
    },

    construct : function(name) {
      eval('var ' + name + ' = function (){};');
      return eval('new ' + name + ';');
    },

    defineRecordNonEnumProps : function(record) {
      var func = function() {return record.__type__; };
      Object.defineProperty(record, "name", {value: func});
      Object.defineProperty(record, "type", {value: func});
    },

    defineEventNonEnumProps : function(event) {
    },

    check_defined : function(x, msg) {
      if (x === undefined) throw Error(msg);
    }
  };

  // ============================================================
  //   Some meta stuff about the underlying Red model
  // ============================================================

  var RedMeta = function() {
    this.records = {};
    this.events = {};
  };
  RedMeta.prototype = {
    search: function(hash, name) {
      var ans = hash[name];
      if (ans) return ans;
      for (var p in hash) {
        if (new RegExp("::" + name + "$").test(p))
          return hash[p];
      }
      return null;
    },

    record : function(name) { return this.search(this.records, name); },
    event  : function(name) { return this.search(this.events, name); },

    create      : function(constr, args) { return new constr(args); },
    createRecord: function(name, id)     { return this.create(this.record(name), id); },
    createEvent : function(name, params) { return this.create(this.event(name), params); }
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
      },

      fireEach: function(funcs, args) {
        for (var i=0; i < funcs.length; i++) {
          funcs[i](args);
        }
      },

      fireDone: function(args)   { this.fireEach(this.doneFuncs, args); },
      fireFail: function(args  ) { this.fireEach(this.failFuncs, args); },
      fireAlways: function(args) { this.fireEach(this.alwaysFuncs, args); }
    };
    jQuery.extend(this, proto);
  };

  // ============================================================
  //   Constructor functions
  // ============================================================

  var Constr = {
    id : function(id) {
      return (id instanceof jQuery) ? id.attr('data-record-id') : id;
    },

    extendProto : function(superFunc) {
      var constr = function() {};
      constr.prototype = superFunc.prototype;
      return new constr();
    },

    extendSig : function(name, superConstr, paramsStr, superArgsStr, body) {
      var funcStr = "f=function " + name + "(" + paramsStr + "){\n";
      if (superConstr)
        funcStr += "  superConstr.call(this, " + superArgsStr + ");\n";
      if (body)
        funcStr += "  " + body + "\n";
      var cstr = "{writable: true, value: arguments.callee}";
      funcStr += "  Object.defineProperty(this, 'constructor', " + cstr + ");\n";
      if (superConstr) {
        var sup = "{writable: true, value: superConstr}";
        funcStr += "  Object.defineProperty(this, 'superConstructor', " + sup + ");\n";
      }
      funcStr += "}";
      var c = eval(funcStr);
      if (superConstr)
        c.prototype = Constr.extendProto(superConstr);
      return c;
    },

    record : function(name, superRecordConstr) {
      if (superRecordConstr === undefined) superRecordConstr = Red.Model.Record;
      var c;
      if (superRecordConstr === null) {
        var body = "this['id']=id;";
        c = Constr.extendSig(name, null, "id", null, body);
      } else {
        c = Constr.extendSig(name, superRecordConstr, "id", "Constr.id(id)");
      }
      c.isRecordConstr = true;
      return c;
    },

    event : function(name, superEventConstr) {
      if (superEventConstr === undefined) superEventConstr = Red.Model.Event;
      var c;
      if (superEventConstr === null) {
        var body = "this.params=params || {}; this.canceled=false;";
        c = Constr.extendSig(name, null, "params", null, body);
      } else {
        c = Constr.extendSig(name, superEventConstr, "params", "params");
      }
      c.isEventConstr = true;
      return c;
    }
  };

  // ============================================================
  //   Serialization
  // ============================================================

  var Serializer = {
    serializeObject : function(obj) {
      var ans = {};
      for (var p in obj) { ans[p] = Serializer.serialize(obj[p]); }
      return ans;
    },

    serializeArray : function(arr) {
      var ans = [];
      for (var i in arr) { ans.push(Serializer.serialize(arr[i])); }
      return ans;
    },

    serialize : function(obj) {
      var ans;
      if (obj instanceof Array) {
        ans = Serializer.serializeArray(obj);
      } else if (obj instanceof Red.Model.Record) {
        ans = Serializer.serializeObject(obj);
        ans["is_record"] = true;
        ans["__type__"] = obj.meta().name;
      } else if (obj instanceof Object) {
        ans = Serializer.serializeObject(obj);
      } else {
        ans = obj;
      }
      return ans;
    },

    param : function(obj) {
      return jQuery.param(Serializer.serialize(obj));
    }
  };

  // ============================================================
  //   Various utility functions
  // ============================================================

  var Rendering = {
    renderTemplate : function(template, context) {
      var ans = template;
      for (var key in context) {
        ans = ans.replace(new RegExp("\\$\\{" + key + "\\}", 'g'), context[key]);
      }
      return ans;
    }
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

    truncate : function(str, len, opts) {
      str = jQuery.trim(str);
      if (str.length > len)
        return str.substring(0, len-3) + "...";
      else
        return str;
    },

    trunc : function(str, len, opts) { return Utils.truncate(str, len, opts); },

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
         if (requestOpts.params) url += '?' + Serializer.param(requestOpts.params);
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
       var renderEvent = new RenderRecord({
         record: record,
         options: jQuery.extend({
           autoview: false
         }, renderOpts)
       });
       var xhr = new MyXHR();
       renderEvent.fire()
         .done(function(response)   {
           var elem = $("<span></span>");
           elem.html(response.ans);
           var ret = elem.children().size() === 1 ? $(elem.children()[0]) : elem;
           Red.Autoview.processAutoview(ret);
           xhr.fireDone(ret);
         })
         .fail(function(response)   { xhr.fireFail(response); })
         .always(function(response) { xhr.fireAlways(response); });
       return xhr;
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

     readParamForField : function(elem, paramName, fldMeta) {
       var ans = Utils.readParamValue(elem, paramName);
       if (ans !== undefined) {
         if (fldMeta.parent.isRecordConstr) {
           var id = Number(ans);
           if (isFinite(id)) ans = new fldMeta.parent(id);
         }
       }
       return ans;
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
              var cont = function() {
                myAddClass($elem, okCls, duration, function() {
                  //setTimeout(function() {myRemoveClass($elem, okCls);}, timeout);
                });
              };
              cont.cancel = false;
              if (opts.done) {
                opts.done(r, cont);
                if (!cont.cancel)
                  cont();
              } else {
                $elem.html(r);
                cont();
              }
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
      if (param.isFile()) {
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
      } else if (param.isPrimitive()) {
        var ans = window.prompt("Enter value for '" + param.name + "'", "");
        if (ans !== null) {
          ev.params[param.name] = ans;
          Utils.askParams($elem, ev, undefParams, triggerFunc);
        } else {
          ev.cancel();
        }
      } else if (param.isRecord()) {
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
     *  - event parameters are read from
     *      - 'data-param-*' attributes and
     *      - 'data-params-form' form input elements (if specified)
     *
     * @param $elem : jQuery    - a jQuery element
     *
     * ---------------------------------------------------------------- */
    declCreateEvent : function($elem) {
      var eventName = $elem.attr("data-trigger-event") ||
                      $elem.attr("data-event-name");
      //var ev = eval('new ' + eventName + '({})');
      var ev = Red.Meta.createEvent(eventName, {});
      var undefParams = [];

      var formId = $elem.attr("data-params-form");
      var formParams = {};
      if (formId !== undefined) {
        var form = $('#' + formId);
        form.serializeArray().map(function(e){
          formParams[e.name] = e.value;
        });
      }

      for (var paramIdx in ev.meta().params()) {
        var param = ev.meta().params()[paramIdx];
        var paramName = param.name;
        var paramValue = Utils.readParamValue($elem, "data-param-" + paramName) ||
                         formParams[paramName];
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
      var eventName = ev.meta().shortName();

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

  var RedModel = function RedModel() {

    ///////////////////////////////////////////////////////
    this.RecordMeta = function RecordMeta(props) {
      jQuery.extend(this, props);
      var fullname = props["name"];
      var constr = props["sigCls"];
      if (constr.isRecordConstr) {
        Red.Meta.records[fullname] = constr;
      } else if (constr.isEventConstr) {
        Red.Meta.events[fullname] = constr;
      }
    };
    this.RecordMeta.prototype = {
      superRecord: function() { return this.parentSig; },
      subRecords: function() { return this.subsigs; }
    };

    ///////////////////////////////////////////////////////
    this.EventMeta = Constr.extendSig("EventMeta", this.RecordMeta, "props", "props");
    this.EventMeta.prototype = {
      superEvent: function() { return this.parentSig; },
      subEvents: function() { return this.subsigs; },
      shortName: function() { return this.relative_name; },

      params: function() {
        var ans = [];
        if (this.superEvent() && this.superEvent().meta) {
          ans = [].concat(this.superEvent().meta.params());
        }
        var toFld = this.to();
        var fromFld = this.from();
        for (var fldIdx in this.fields) {
          var fld = this.fields[fldIdx];
          if (fld !== toFld && fld !== fromFld)
            ans.push(fld);
        }
        return ans;
      }
    };

    ///////////////////////////////////////////////////////
    this.Field = function Field(props) { jQuery.extend(this, props); };
    this.Field.prototype = {
      isRecord : function() {
        var t = this.type;
        return typeof(t) === "function" && t.isRecordConstr;
      },
      isFile : function() {
        return this.isRecord() && this.type.meta.name === "RedLib::Util::FileRecord";
      },
      isPrimitive : function() {
        return !this.isRecord(); //TODO: fix
      }
    };


    ///////////////////////////////////////////////////////
    this.Record = Constr.record("Record", null);
    jQuery.extend(this.Record.prototype, {
      is_record : true
    });
    Object.defineProperty(this.Record.prototype, "meta", {
      value: function() { return this.constructor.meta; }
    });

    ///////////////////////////////////////////////////////
    this.Event = Constr.event("Event", null);
    jQuery.extend(this.Event.prototype, {
      is_event : true,

      cancel : function() { this.canceled = true; },

      fire : function(cb) {
        cb = Utils.defaultTo(cb, function(response) {});
        if (this.viaForm) {
          return this.fireViaForm(this.viaForm, cb);
        } else {
          return this.fireDirectly(cb);
        }
      },

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
      fireViaForm : function(form, cb) {
        cb = Utils.defaultTo(cb, function(response) {});
        Object.defineProperty(this, "fired", {value: true});

        if (!(typeof(form) === "object")) { form = $(form); }

        var iframe = $("#" + form.attr("target"));
        var myXHR = new MyXHR();
        iframe.load(function(){
          myXHR.fireDone(iframe);
          myXHR.fireAlways(iframe);
          $(iframe).parent().detach();
        });
        form.attr("action", this.actionUrl());
        form.submit();
        return myXHR;
      },

      /* ----------------------------------------------------------------
       * Fires an Ajax POST request to this events action URL.
       *
       * Returns the same XHR object returned by jQuery.post.
       * ---------------------------------------------------------------- */
      fireDirectly : function(cb) {
        cb = Utils.defaultTo(cb, function(response) {});
        Object.defineProperty(this, "fired", {value: true});

        var url = this.actionUrl();
        return jQuery.post(url, cb);
      },

      /* ----------------------------------------------------------------
       *
       * Returns an URL where where a POST request should be sent to
       * trigger this event.  This URL encodes the event name and the
       * values of event parameters.
       *
       * ---------------------------------------------------------------- */
      actionUrl : function() {
        var urlParams = {
            event : this.meta().name,
            params : this.params
        };
        // TODO: auth token?
        return "/event?" + Serializer.param(urlParams);
      },

      /* ----------------------------------------------------------------
       *
       * Returns the meta object for type of event.
       *
       * ---------------------------------------------------------------- */
      meta : function() {
        return this.constructor.meta;
      }
    });
  };


  // ===============================================================
  //   publish subscribe
  // ===============================================================
  var RedEvents = function() {
    var proto = {
      publish_status_kind : function(kind, msg) {
        Red.publish({
          "type" : "status_message",
          "payload" : {
            "kind" : kind,
            "msg" : msg
          }
        });
      },

      publish_status  : function(msg) { proto.publish_status_kind("status", msg); },
      publish_warning : function(msg) { proto.publish_status_kind("warning", msg); },
      publish_error   : function(msg) { proto.publish_status_kind("error", msg); },

      subscribe_message_kind : function(kind, func) {
        Red.subscribe(function(data) {
          if (data.payload && data.payload.kind === kind) func(data, data.payload);
        });
      },

      subscribe_event_completed : function(eventName, func) {
        proto.subscribe_message_kind("event_completed", function(data, payload) {
          if (payload.event.name === eventName) func(data, payload.ans);
        });
      }
    };
    return $.extend(this, proto);
  };

  // ===============================================================
  //   publish subscribe
  // ===============================================================
  var RedAutoview = function() {
    var thisPrivate = {
      attrMap : {},

      sweepDom : function($from, $to, html) {
        if (!($from.size() == 1 && $to.size() == 1)) {
          var msg = "inconsistent start/end tags: #startTag = " +
                $from.size() + ", #endTag = " + $to.size();
          console.error(msg);
          return;
        }
        var current = $from[0];
        var end = $to[0];
        if (current.parentNode !== end.parentNode) {
          console.error("From and to nodes not at the same level");
          console.debug("From: ");
          console.debug(current);
          console.debug("To: ");
          console.debug(end);
          return;
        }
        //NOTE: from.nextUntil(to).detach() is not good enough since it
        //      skips over text nodes.
        var toDetach = [];
        while (current !== end) {
          toDetach.push(current);
          current = current.nextSibling;
        }
        $(toDetach.slice(1, toDetach.length)).detach();
        $from.before(html);
        $from.detach();
        $to.detach();
      },

      searchDom : function(node_id, html) {
        // check attrMap first
        var startTag = "reds_" + node_id;
        var endTag = "rede_" + node_id;

        var attrInfo = thisPrivate.attrMap[node_id];
        if (attrInfo) {
          var attr = attrInfo.attr;
          var attrVal = attrInfo.origAttrVal;
          var startTagStr = "<" + startTag + ">";
          var endTagStr = "</" + endTag + ">";
          var startIdx = attrVal.indexOf(startTagStr);
          var endIdx = attrVal.indexOf(endTagStr);
          me.assert(startIdx !== -1 && endIdx !== -1);
          var newValue  = attrVal.substring(0, startIdx) + html +
                          attrVal.substring(endIdx + endTagStr.length);
          // console.debug("updated attribute '" + attr.name + "' from '" +
          //               attr.nodeValue + "' to '" + newValue + "'");
          attr.nodeValue = newValue;
          proto.processAttribute(attrInfo.node, attr);
        } else {
          thisPrivate.sweepDom($(startTag), $(endTag), html);
        }

        // var elements = document.getElementsByTagName("*");
        // for (var i = 0; i < elements.length; i++) {
        //   var element = elements[i];
        //   if (element.tagName.toLowerCase() === startTag) {
        //     thisPrivate.sweepDom($(element), $("rede_" + node_id), html);
        //     return;
        //   }
        //   var attr = element.attributes;
        //   for (var j = 0; j < attr.length; j++) {
        //     var attrVal = attr[j].nodeValue;
        //     var startIdx = attrVal.indexOf(startTagStr);
        //     if (startIdx != -1) {
        //       var endIdx = attrVal.indexOf(endTagStr);
        //       if (endIdx != -1) {
        //         attr[j].nodeValue = attrVal.substring(0, startIdx) + html +
        //                             attrVal.substring(endIdx + endTagStr.length);
        //         return;
        //       } else {
        //         console.error("start but not end tag found in attribute " + attrVal);
        //       }
        //     }
        //   }
        // }
      },

      assocTagToAttribute : function(node, attr, tagId, origAttrVal) {
        console.debug("associated tag " + tagId + " with " +
                       node.tagName + "." + attr.name);
        thisPrivate.attrMap[tagId] = {
          node: node,
          attrName: attr.name,
          attr: attr,
          origAttrVal: origAttrVal
        };
      }
    };

    var proto = {

     /* ----------------------------------------------------------------
      *
      * Searches for elements with attributes containing <reds_?> and
      * <rede_?> tags, removes those tags from the attribute value but
      * remembers the association between the two.
      *
      * @return undefined
      *
      * ---------------------------------------------------------------- */
      processAttribute : function(node, attr) {
        var attrVal = attr.nodeValue;
        var currVal = attrVal;
        while (true) {
          var startTagMatch = currVal.match(/<reds_(\d+)><\/reds_(\d+)>/);
          if (startTagMatch) {
            me.assert(startTagMatch.length === 3);
            var tagId = startTagMatch[1];
            me.assert(tagId === startTagMatch[2]);
            var startTag = startTagMatch[0];
            var endTag = '<rede_' + tagId + '></rede_' + tagId + '>';
            var endTagIdx = currVal.indexOf(endTag);
            me.assert(endTagIdx !== -1);
            thisPrivate.assocTagToAttribute(node, attr, tagId, currVal);
            currVal = currVal.replace(startTag, "").replace(endTag, "");
          } else {
            break;
          }
        }
        if (currVal !== attrVal) {
          console.debug("changed attribute value from '" +
                        attrVal + "' to '" + currVal + "'");
          attr.nodeValue = currVal;
        }
      },

     /* ----------------------------------------------------------------
      *
      * Searches for elements with attributes containing <reds_?> and
      * <rede_?> tags, removes those tags from the attribute value but
      * remembers the association between the two.
      *
      * @return undefined
      *
      * ---------------------------------------------------------------- */
      processAutoview : function($elem) {
        var elements = $elem.find("*");
        for (var i = 0; i < elements.length; i++) {
          var element = elements[i];
          var attr = element.attributes;
          for (var j = 0; j < attr.length; j++) {
            proto.processAttribute(element, attr[j]);
          }
        }
      },

      updateReceived : function(data) {
        var updateStart = new Date().getTime();
        me.check_defined(data.type, "malformed JSON update: field 'type' not found");

        if (data.type === "node_update") {

          me.check_defined(data.payload,
              "field 'payload' not found in a 'node_update' message");
          me.check_defined(data.payload.node_id,
              "field 'payload.node_id' not found in a 'node_update' message");
          me.check_defined(data.payload.inner_html,
              "field 'payload.inner_html' not found in a 'node_update' message");

          thisPrivate.searchDom(data.payload.node_id, data.payload.inner_html);

        } else if (data.type === "body_update") {

          me.check_defined(data.payload,
              "field 'payload' not found in a 'body_update' message");
          me.check_defined(data.payload.html,
              "field 'payload.html' not found in a 'body_update' message");
          $('body').html(data.payload.html);

        } else {
          //throw Error("unknown update message type: " + data.type)
        }

        var updateEnd = new Date().getTime();
        var time = updateEnd - updateStart;
        console.debug('Total update execution time: ' + time + "ms");
      }
    };
    return $.extend(this, proto);
  };

  var Red = {

    Events     : new RedEvents(),
    Meta       : new RedMeta(),
    Model      : new RedModel(),

    Constr     : jQuery.extend({}, Constr),
    Utils      : jQuery.extend({}, Utils),
    Renderer   : jQuery.extend({}, Rendering),
    Serializer : jQuery.extend({}, Serializer),

    Autoview   : new RedAutoview(),

    // ===============================================================
    //   handlers
    // ===============================================================

    logMessages : function(data) {
      console.debug("[RED] update received; type:" + data.type
                    + ", payload: " + JSON.stringify(data.payload));
    },

    updateReceived : function(data) {
      return Red.Autoview.updateReceived(data);
    }
  };

  return Red;
})();

