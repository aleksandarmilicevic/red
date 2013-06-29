$(function() {
    jQuery.fn.selectText = function(){
        var doc = document;
        var element = this[0];
        var range = null;
        if (doc.body.createTextRange) {
            range = document.body.createTextRange();
            range.moveToElementText(element);
            range.select();
        } else if (window.getSelection) {
            var selection = window.getSelection();        
            range = document.createRange();
            range.selectNodeContents(element);
            selection.removeAllRanges();
            selection.addRange(range);
        }
    };

    $(document).on("click", "[data-type='submit-event']", function(e) {
        var formId = $(this).attr("data-event-form");
        var eventName = $(this).attr("data-event-type");
        var ev = Red.event(eventName, {});
        ev.fireViaForm('#' + formId);
        // var params = {};
        // var ser = $('#'+formId).serializeArray();
        // for (var i = 0; i < ser.length; i++) {
        //     params[ser[i].name] = ser[i].value;
        // }
        // Red.event(eventName, params).fire();
        return false;
    });

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
    var askParams = function($elem, ev, undefParams, triggerFunc) {
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
                askParams($elem, ev, undefParams, triggerFunc);
            });
            fileInput.trigger("click");
        } else if (param.isPrimitive) {
            ev.params[param.name] =  window.prompt(param.name, "");
            askParams($elem, ev, undefParams, triggerFunc);
        } else if (param.isRecord) {
            alert("Missing Record parameters (" + param.name + ") not implemented");
        } else {
            console.debug("Unsupported parameter kind:");
            console.debug(param);
            throw new Error("unsupported parameter kind");
        }
    };

    /* ===========================================================
     * Handle the 'click' event for all elements that have
     * the 'data-trigger-event' attribute set.
     * 
     *  - reads event params from 'data-param-*' attributes
     *  - prompts for missing parameters
     *  - fires the event asynchronously (via $.post)
     *  - triggers either ${eventName}Done or ${eventName}Failed 
     *    handler (if bound) after the event has been executed 
     * =========================================================== */
    $(document).on("click", "[data-trigger-event]", function(e) {
        var $elem = $(this);
        if ($elem.attr("disabled") === "disabled") 
            return false;
        var eventName = $elem.attr("data-trigger-event");
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

        askParams($elem, ev, undefParams, function() {
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
        return false;
    });
    
    // ---------------------------------------------------------------- 
    //   autosave stuff 
    // ---------------------------------------------------------------- 
  
    var isInput = function(elem) {
        return !(elem.is("pre") || elem.is("div") || elem.is("span") || elem.is("a"));
    };
   
    var extractValue = function(elem) {
        if (isInput(elem)) { return elem.val(); }
        else               { return elem.html(); }  
    };
   
    var setValue = function(elem, val) {
        if (isInput(elem)) { return elem.val(val); } 
        else               { return elem.html(val); }  
    };
   
    $(document).on("focus", ".singlelineedit", function(e) {
        $(this).keypress(function(e) { if(e.which == 13) { $(this).blur(); } });
    });
   
    $(document).on("focus", ".red-autosave", function(e) {
        $(this).addClass("red-editing");
        var currentValue = extractValue($(this));
        $(this).data("old-value", currentValue);
        $(this).data("canceled", false);
        $(this).keyup(function(e) { 
            if(e.which == 27) { 
                $(this).data("canceled", true);
                $(this).blur(); 
            } 
        });
    });
   
    $(document).on("blur", ".red-autosave", function(e) {
        var $elem = $(this);
        $elem.removeClass("red-editing");
        var currentValue = extractValue($elem);
        var oldValue = $elem.data("old-value");
        if (oldValue == currentValue) return;
        if ($elem.data("canceled")) {
            setValue($elem, oldValue);
            return;
        }
        var duration = 200;
        var timeout = 800;
        var recordCls = $elem.attr("data-record-cls");
        var recordId = $elem.attr("data-record-id");
        var fieldName = $elem.attr("data-field-name");
        var params = {};
        params[fieldName] = currentValue;
        $elem.addClass("red-updating", "fast", function(){
            new UpdateRecord({
                "target": Red.createRecord(recordCls, recordId),
                "params": params
            }).fire(
            ).done(function(r) {
                console.debug("autosaved " + recordCls + "(" + recordId + ")." + fieldName);
                console.debug(r);
                $elem.removeClass("red-updating");
                $elem.addClass("red-update-ok", duration, function() {
                  setTimeout(function() {$elem.removeClass("red-update-ok");}, timeout); 
              });
            }).fail(function() { 
                console.debug("autosave failed");
                setValue($elem, oldValue);
                $elem.removeClass("red-updating");
                $elem.addClass("red-update-fail", duration, function() {
                  setTimeout(function() {$elem.removeClass("red-update-fail");}, timeout); 
              });
            }).always(function() {
                $elem.removeClass("red-updating");
            });
        });
     });
     
});  
