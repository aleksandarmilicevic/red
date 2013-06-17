$(function() {
    $(document).on("click", "[data-type='submit-event']", function(e) {
        var formId = $(this).attr("data-event-form");
        var eventName = $(this).attr("data-event-type");
        var params = {};
        var ser = $('#'+formId).serializeArray();
        for (var i = 0; i < ser.length; i++) {
            params[ser[i].name] = ser[i].value;
        }
        Red.event(eventName, params).fire();
    });
    
    $(document).on("click", "[data-type='submit-event-ask']", function(e) {
        var eventName = $(this).attr("data-event-type");
        var ev = eval('new ' + eventName + '({})');
        for (var i = 0; i < ev.paramNames.length; i++) {
            ev.params[ev.paramNames[i]] = window.prompt(ev.paramNames[i], "");
        }
        ev.fire();
    });
    
    $(document).on("click", "[data-trigger-event]", function(e) {
        var $elem = $(this);
        var eventName = $elem.attr("data-trigger-event");
        var ev = eval('new ' + eventName + '({})');
        for (var i = 0; i < ev.paramNames.length; i++) {
            var paramName = ev.paramNames[i];
            var paramValue = $elem.attr("data-param-" + paramName);
            if (paramValue === undefined) {
                paramValue = window.prompt(paramName, "")
            }
            ev.params[paramName] = paramValue;
        }
        ev.fire()
        .done(function(response){$elem.trigger("eventFinished", [response]);})
        .fail(function(response){$elem.trigger("eventFailed", [response]);});
    });
    
    /* autosave elements */
   
   var isInput = function(elem) {
       return !(elem.is("pre") || elem.is("div") || elem.is("span") || elem.is("a"))
   };
   
   var extractValue = function(elem) {
       if (isInput(elem)) { return elem.val(); }
       else               { return elem.html(); }  
   };
   
   var setValue = function(elem, val) {
       if (isInput(elem)) { return elem.val(val); } 
       else               { return elem.html(val); }  
   };
   
   $(document).on("focus", ".red-autosave", function(e) {
       $(this).addClass("red-editing");
       var currentValue = extractValue($(this));
       $(this).data("old-value", currentValue);
   });
   
   $(document).on("blur", ".red-autosave", function(e) {
       var $elem = $(this);
       $elem.removeClass("red-editing");
       var currentValue = extractValue($elem);
       var oldValue = $elem.data("old-value");
       if (oldValue == currentValue) return;
       var duration = 200;
       var timeout = 800;
       var recordCls = $elem.attr("data-record-cls");
       var recordId = $elem.attr("data-record-id");
       var fieldName = $elem.attr("data-field-name");
       var params = {}
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
                 setTimeout(function() {$elem.removeClass("red-update-ok")}, timeout); 
             });
           }).fail(function() { 
               console.debug("autosave failed");
               setValue($elem, oldValue);
               $elem.removeClass("red-updating");
               $elem.addClass("red-update-fail", duration, function() {
                 setTimeout(function() {$elem.removeClass("red-update-fail")}, timeout); 
             });
           }).always(function() {
               $elem.removeClass("red-updating");
           });
       });
    });
     
    
});
