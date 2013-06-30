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

    /* ===========================================================
     * Handle the 'click' event for all elements that have
     * the 'data-trigger-event' attribute set.
     * =========================================================== */
    $(document).on("click", "[data-trigger-event]", function(e) {
        var $elem = $(this);
        Red.Utils.declTriggerEvent($elem);
        // if ($elem.attr("disabled") === "disabled") 
        //     return false;
        // var eventName = $elem.attr("data-trigger-event");
        // var ev = eval('new ' + eventName + '({})');
        // var undefParams = [];
        // for (var i = 0; i < ev.meta.params.length; i++) {
        //     var param = ev.meta.params[i];
        //     var paramName = param.name;
        //     var paramValue = Red.Utils.readParamValue($elem, "data-param-" + paramName);
        //     if (paramValue === undefined) {
        //         undefParams.push(param);
        //     }
        //     ev.params[paramName] = paramValue;
        // }

        // askParams($elem, ev, undefParams, function() {
        //     $elem.trigger(eventName + "Triggered", [ev]);
        //     if (ev.fired !== true) {
        //         ev.fire(
        //         ).done(function(response) {
        //             $elem.trigger(eventName + "Done", [response]);
        //         }).fail(function(response) {
        //             $elem.trigger(eventName + "Failed", [response]);
        //         });
        //     }
        // });
        return false;
    });
    
    // ---------------------------------------------------------------- 
    //   autotrigger stuff 
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
   
    $(document).on("keypress", ".singlelineedit", function(e) {
        if(e.which == 13) { $(this).blur(); }
    });

    $(document).on("keyup", ".red-autotrigger", function(e) {
        if(e.which == 27) { 
            $(this).data("canceled", true);
            $(this).blur(); 
        } 
    });

    $(document).on("focus", ".red-autotrigger", function(e) {
        $(this).addClass("red-editing");
        var currentValue = extractValue($(this));
        $(this).data("old-value", currentValue);
        $(this).data("canceled", false);
    });
   
    $(document).on("blur", ".red-autotrigger", function(e) {
        var $elem = $(this);
        $elem.removeClass("red-editing");
        var currentValue = extractValue($elem);
        var oldValue = $elem.data("old-value");
        if (oldValue == currentValue) return;
        if ($elem.data("canceled")) {
            setValue($elem, oldValue);
            return;
        }
        var fieldName = $elem.attr("data-field-name");
        $elem.attr('data-param-' + fieldName, currentValue);
        var event = Red.Utils.declCreateEvent($elem).event;
        Red.Utils.asyncUpdate($elem, "red", {
            action: function(){
                return event.fire();
            }, 
            done: function(response) {
                $elem.trigger(event.meta.shortName + "Done", [response]);
            },
            fail: function(response) {
                $elem.trigger(event.meta.shortName + "Failed", [response]);
            }
        });
     });
     
});  
