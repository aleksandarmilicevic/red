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

