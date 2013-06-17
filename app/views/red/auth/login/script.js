$(function() {
    $(document).on("click", "#register_lnk", function(e) {
        var regDiv = $("#reg");
        var sgnDiv = $("#signin");
        var regGrp = $("#register_grp");
        var sgnGrp = $("#signin_grp");
        var nameDiv = $("#name_div");
        regDiv.show();
        sgnDiv.hide();
        regGrp.show();
        sgnGrp.hide();
        nameDiv.show();
    });
    
    $(document).on("click", "#signin_lnk", function(e) {
        var regDiv = $("#reg");
        var sgnDiv = $("#signin");
        var regGrp = $("#register_grp");
        var sgnGrp = $("#signin_grp");
        var nameDiv = $("#name_div");
        sgnDiv.show();
        regDiv.hide();
        sgnGrp.show();
        regGrp.hide();
        nameDiv.hide();
    });
});