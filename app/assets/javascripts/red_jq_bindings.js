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

  Red.Autoview.processAutoview($("body"));

  /* ----------------------------------------------------------------
   * Handle the 'click' event for all elements that have
   * the 'data-trigger-event' attribute set.
   * ---------------------------------------------------------------- */
  $(document).on("click", "[data-trigger-event]", function(e) {
    var $elem = $(this);
    Red.Utils.declTriggerEvent($elem);
    return false;
  });

  // ===========================================================
  //   truncate stuff
  // ===========================================================

  var isEditing = function($elem)   { return $elem.hasClass('red-editing'); };
  var getVal = function($elem)      { return $elem.attr('data-value'); };
  var setVal = function($elem, val) { return $elem.attr('data-value', val); };

  $(document).on("mouseover", ".truncate-body", function(e) {
    var $elem = $(this);
    if (isEditing($elem)) return;
    $elem.html(getVal($elem));
  });

  $(document).on("mouseout", ".truncate-body", function(e) {
    var $elem = $(this);
    if (isEditing($elem)) return;
    $elem.html(Red.Utils.trunc(getVal($elem), 15));
  });

  $(document).on("blur", ".truncate-body", function(e) {
    var $elem = $(this);
    setVal($elem, $elem.html());
    $elem.mouseout();
  });

  // ===========================================================
  //   autotrigger stuff
  // ===========================================================

  var isInput = function(elem) {
    return elem.is("input") || elem.is("textarea");
    //return !(elem.is("pre") || elem.is("div") || elem.is("span") || elem.is("a"));
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

  $(document).on("keydown", ".red-autotrigger", function(e) {
    if(e.which == 13 && e.ctrlKey) { $(this).blur(); }
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
        $elem.trigger(event.meta().shortName() + "Done", [response]);
      },
      fail: function(response) {
        setValue($elem, oldValue);
        $elem.trigger(event.meta().shortName() + "Failed", [response]);
      }
    });
  });

});
