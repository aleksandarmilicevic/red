Red.subscribe(function() {
    var source   = $("#red_status_msg_tpl").html();
    var template = Handlebars.compile(source);
    
    return function (data) {
        if (data.type === "status_message") {
            var parent = $("#red_" + data.payload.kind + "_message");
            if (parent != null) {
                var context = {kind: data.payload.kind, msg: data.payload.msg};
                var msgHtml = template(context);
                parent.append(msgHtml);
                var chldrn = parent.children();
                var elem = chldrn[chldrn.size()-1];                
                $(elem).fadeIn().delay(5000).fadeOut();
            } 
        }
    };
}());
