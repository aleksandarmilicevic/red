var Red = (function() {
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
            Object.defineProperty(event, "meta", {value: new me.EventMeta()});        
            Object.defineProperty(event, "viaForm", {
                writable: true,
                value: undefined
            });        
        },

        check_defined : function(x, msg) {
            if (x === undefined) throw Error(msg);
        },
        
        defaultTo : function(val, defaultVal) {
            if (typeof(val) === "undefined") {
                return defaultVal;
            } else {
                return val;
            }
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

    var Meta = {
        modelForRecord : function(recordName) {
            return this.record2model[recordName];
        }
    };

    var Utils = {
        remoteAction : function(hash) {
            if (typeof(hash) === 'undefined') { hash = {}; }
            var url = "";
            if (typeof(hash) === 'object') {
                url = "/";
                if (hash.controller) url += hash.controller;
                if (hash.action) url += '#' + hash.action;
                if (hash.format) url += '.' + hash.format;
                if (hash.params) url += '?' + jQuery.param(hash.params);
            } else {
                url = "" + hash;
            }
            return jQuery.get(url, function() {});
        },

        remoteRenderRecord : function(record, hash) {
            if (typeof(hash) === 'undefined') { hash = {}; }
            var params = {
                record: record, 
                options: jQuery.extend({
                    autoview: false
                }, hash)
            };
            var url = '/recordRenderer?' + jQuery.param(params);
            return Red.Utils.remoteAction(url);
        },

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

        chainActions : function(actions, hash) {
            return function() {
                if (actions.length == 0) throw new Error("0 actions not allowed");
                var action = actions.shift();
                action()
                    .done(function(r){
                        if (actions.length == 0) {
                            if (hash.done) hash.done(r);
                        } else {  
                            Red.Utils.chainActions(actions, hash)();
                        }
                    })
                    .fail(function(r)   { if (hash.fail) hash.fail(r);})
                    .always(function(r) { if (hash.always) hash.always(r);});
            };
        },

        asyncUpdate : function($elem, cls, hash) {
            var oldHtml = $elem.html();
            var updatingCls = cls + "-updating";
            var okCls = cls + "-update-ok";
            var failCls = cls + "-update-fail";
            
            var duration = hash.duration || 200; 
            var timeout = hash.timeout || 800;
            
            var actions = hash.actions || [hash.action];
            $elem.addClass(updatingCls, "fast", function(){
                Red.Utils.chainActions(actions, {
                    done: function(r) {
                        $elem.removeClass(updatingCls);
                        if (hash.done) { hash.done(r); } else { $elem.html(r); }
                        $elem.addClass(okCls, duration, function() {
                            setTimeout(function() {$elem.removeClass(okCls);}, timeout); 
                        });
                    }, 
                    fail: function(r) {
                        $elem.removeClass(updatingCls);
                        if (hash.fail) { hash.fail(r); }
                        $elem.addClass(failCls, duration, function() {
                            setTimeout(function() {$elem.removeClass(failCls);}, timeout); 
                        });
                    },
                    always: function(r) {
                        $elem.removeClass(updatingCls);
                        if (hash.always) { hash.always(r); }
                    }
                })();
            });
        }, 

        /* ==============================================================
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
         * ============================================================== */
        askParams : function($elem, ev, undefParams, triggerFunc) {
            if (undefParams.length === 0) {
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
                    Red.Utils.askParams($elem, ev, undefParams, triggerFunc);
                });
                fileInput.trigger("click");
            } else if (param.isPrimitive) {
                ev.params[param.name] =  window.prompt(param.name, "");
                Red.Utils.askParams($elem, ev, undefParams, triggerFunc);
            } else if (param.isRecord) {
                alert("Missing Record parameters (" + param.name + ") not implemented");
            } else {
                console.debug("Unsupported parameter kind:");
                console.debug(param);
                throw new Error("unsupported parameter kind");
            }
        },

        /* ===========================================================
         * Creates event declaratively specified through element's 
         * data attributes:
         * 
         *  - event name is read from either 'data-trigger-event' or 
         *    'data-event-name' attribute
         *  - reads event params from 'data-param-*' attributes
         * =========================================================== */
        declCreateEvent : function($elem) {
            var eventName = $elem.attr("data-trigger-event") || 
                            $elem.attr("data-event-name");
            var ev = eval('new ' + eventName + '({})');
            var undefParams = [];
            for (var i = 0; i < ev.meta.params.length; i++) {
                var param = ev.meta.params[i];
                var paramName = param.name;
                var paramValue = Red.Utils.readParamValue($elem, "data-param-" + paramName);
                if (paramValue === undefined) {
                    undefParams.push(param);
                }
                ev.params[paramName] = paramValue;
            }
            return { event: ev, undefParams: undefParams };
        },

        /* ===========================================================
         * Creates event declaratively specified through element's
         * data attributes (via the Red.Utils.declCreateEvent func),
         * and then
         * 
         *  - prompts for missing parameters
         *  - fires the event asynchronously (via $.post)
         *  - triggers either ${eventName}Done or ${eventName}Failed 
         *    handler (if bound) after the event has been executed 
         * =========================================================== */
        declTriggerEvent : function($elem) {
            if ($elem.attr("disabled") === "disabled") 
                return;
            
            var ans = Red.Utils.declCreateEvent($elem);
            var ev = ans.event;
            var undefParams = ans.undefParams;
            var eventName = ev.meta.shortName;

            Red.Utils.askParams($elem, ev, undefParams, function() {
                $elem.trigger(eventName + "Triggered", [ev]);
                if (ev.fired !== true) {
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

        record : function(type, props) {
            var that = me.construct("Record");

            that.is_record = true;

            var recordProps = $.extend({__type__: type}, props);
            for (p in recordProps) {
                that[p] = recordProps[p];
            }

            me.defineRecordNonEnumProps(that);
            
            Object.defineProperty(that, "cloneOnto", {
                enumerable: false,
                value: function(obj) {
                    $.extend(obj, that);
                    me.defineRecordNonEnumProps(obj);    
                    return obj;
                }
            });

            return that;
        },

        event : function(name, params) {
            var that = me.construct("Event");

            that.is_event = true;
            that.name = name;
            that.params = params;

            that.fire = function(cb) {
                cb = me.defaultTo(cb, function(response) {});
                if (this.viaForm) {
                    return this.fireViaForm(this.viaForm, cb);
                } else {
                    return this.fireDirectly(cb);
                }
            };

            that.fireViaForm = function(form, cb) {
                cb = me.defaultTo(cb, function(response) {});
                
                if (!(typeof(form) === "object")) {
                    form = $(form);
                }

                var iframe = $("#" + form.attr("target"));
                var myXHR = new MyXHR();
                iframe.load(function(){
                    for (var i=0; i < myXHR.doneFuncs.length; i++) {
                        myXHR.doneFuncs[i]("repodfnsdf");
                    }
                });
                form.attr("action", Red.eventUrl(this));
                form.submit();
                return myXHR;
            }; 

            that.fireDirectly = function(cb) {
                cb = me.defaultTo(cb, function(response) {}); 

                var url = Red.eventUrl(this);
                Object.defineProperty(this, "fired", {value: true});
                return jQuery.post(url, cb);
            };

            Object.defineProperty(that, "cloneOnto", {
                enumerable: false,
                value: function(obj) {
                    $.extend(obj, that);
                    me.defineEventNonEnumProps(obj);    
                    return obj;
                }
            });

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

        eventUrl : function(ev) {
            var urlParams = {
                event : ev.name,
                params : ev.params
            };
            // TODO: auth token
            return "/event?" + jQuery.param(urlParams);
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
            console.debug("[RED] update received; type: " + data.type + ", payload: " + JSON.stringify(data.payload));
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

