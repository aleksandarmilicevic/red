// This is a manifest file that'll be compiled into application.js, which will include all the files
// listed below.
//
// Any JavaScript/Coffee file within this directory, lib/assets/javascripts, vendor/assets/javascripts,
// or vendor/assets/javascripts of plugins, if any, can be referenced here using a relative path.
//
// It's not advisable to add code directly here, but if you do, it'll appear at the bottom of the
// the compiled file.
//
// WARNING: THE FIRST BLANK LINE MARKS THE END OF WHAT'S TO BE PROCESSED, ANY BLANK LINE SHOULD
// GO AFTER THE REQUIRES BELOW.
//
//= require jquery
//= require jquery_ujs
//= require red
// require handlebars
// require ember
// require ember-data
// require red-ember
//= require red_jq_bindings
//= require_tree .


$(document).ready(function() {

 
    //////////////////////
    $( ".right_div" ).sortable({
        opacity: 0.75,
        placeholder: "ui-state-highlight"
    });


    //  $( ".box_element_param" ).draggable({
    //     connectToSortable: ".right_div",
    //     scroll: true,
    //     cursor: "move",
    //     helper: "clone",
    //     opacity: 0.75,
    //     // revert: 'invalid',
    //     stop: function(event, ui) {
    //         //alert(ui)
    //     }
    // });

     
    var idGen = 0;

	$(".obj_class").click(function() {

        //Extract Information on Which Model is being produced
		var id = $(this).html();
		var obj_params = $("#"+id+"data").html();
        var obj_params_list = obj_params.split(",");

        //Create Unique Identifier for the new Element
		var localId = id+idGen
		idGen++;

        // Make Links for the additional Model Objects
        var obj_param_links ="";
        for (var i=0;i<obj_params_list.length-1;i++){
            str = obj_params_list[i].replace(/\s/g, '');
            str = "Add "+id+"'s "+str;
            obj_param_links = obj_param_links +("<li><a id='param"+id+str+"' href='#''>"+str+"</a></li>");
            console.log(obj_params_list[i]);
        }

        // $("#param"+id+str+).click(function() {
        //          console.log("clicked");
        // });


        //Create the new Element and Append it to the View
		 var newElem ="<div id='"+localId+"' class='new_item'>"
                             +"<div class='name&Btn'>"
                                  +"<span class='btn-group left'>"
                                       +"<span class='className dropdown-toggle' data-toggle='dropdown'>"+id+"<span class='caret'></span></span>"
                                         +"<ul class='dropdown-menu' role='menu'>"
                                          +obj_param_links 
                                          +"</ul>"
                                   +"</span>"
                                  +"<span id ='delete"+localId+"' class='deleteBtn'>Delete</span>"
                            +"</div>"
                             +"<div class='yield_area'>"
                             +"</div></div>"
		 $(".right_div").append(newElem);

         //Create A means to delete it.
		 $("#delete"+localId).click(function() {
	                var el = document.getElementById( localId);
                    el.parentNode.removeChild( el );
                    
	      });
		 
	});

	 

     


});
