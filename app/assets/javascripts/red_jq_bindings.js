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
        var params = {};
        var ser = $('#'+formId).serializeArray();
        for (var i = 0; i < ser.length; i++) {
            params[ser[i].name] = ser[i].value;
        }
        Red.event(eventName, params).fire();
        return false;
    });
    
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
        for (var i = 0; i < ev.paramNames.length; i++) {
            var paramName = ev.paramNames[i];
            var paramValue = $elem.attr("data-param-" + paramName);
            var len = paramValue.length;
            if (paramValue === undefined) {
                paramValue = window.prompt(paramName, "");
            } else if (paramValue.substring(0, 2) === "${" &&
                       paramValue.substring(len-1, len) === "}") {
                paramValue = eval(paramValue.substring(2, len-1));
                if (paramValue instanceof jQuery) {
                    paramValue = jQuery.makeArray(paramValue);                    
                }
            }
            ev.params[paramName] = paramValue;
        }
        $elem.trigger(eventName + "Triggered", [ev]);
        if (ev.fired !== true) {
            ev.fire(
            ).done(function(response) {
                $elem.trigger(eventName + "Done", [response]);
            }).fail(function(response) {
                $elem.trigger(eventName + "Failed", [response]);
            });
        }
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
