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
    
    $( ".right_div .yield_area" ).sortable({
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
       createNewObject(id, "right_div")
		 
	});

 
  function createNewObject( record_reference, yield_div_id){
    console.log(record_reference);

    //new object identifiers 
    var localId = record_reference+idGen
    idGen++;
    
    //data from record
    var record = eval("Red.Meta.records."+record_reference);
    var obj_params = record.meta.fields;
    

     // Make Links for the additional Model Objects
    var obj_param_links ="";
    for (var i=0;i<obj_params.length;i++){
            str = obj_params[i].name;
            var newid = str;
            str = "Add "+record_reference+"'s "+str;
            obj_param_links = obj_param_links +("<li><a class='newObjParams' id='"+localId+newid+"' href='#''>"+str+"</a></li>");
           
    }
      


        //Create the new Element and Append it to the View
     var newElem ="<div id='"+localId+"' class='new_item'>"
                             +"<div class='name&Btn'>"
                                  +"<span class='btn-group left'>"
                                       +"<span class='className dropdown-toggle' data-toggle='dropdown'>"+record_reference+"<span class='caret'></span></span>"
                                         +"<ul class='dropdown-menu' role='menu'>"
                                          +obj_param_links 
                                          +"</ul>"
                                   +"</span>"
                                  +"<span id ='delete"+localId+"' class='deleteBtn'>Delete</span>"
                            +"</div>"
                             +"<div id='"+localId+"yield' class='yield_area'>"
                             +"</div></div>"
     $("#"+yield_div_id).append(newElem);

    $("li .newObjParams").click(function() {
              var identifier = $(this).html();
              identifier = identifier.split(" ");
              var identifier = identifier[identifier.length-1];
              var newRecord = "Red.Meta.records."+record_reference;
              createNewParam(record_reference, newRecord, identifier, localId+"yield" );
                    
     });

     //Create A means to delete it.
     $("#delete"+localId).click(function() {
                  var el = document.getElementById( localId);
                    el.parentNode.removeChild( el );
                    
     });
  }




  function createNewParam(original_record_name, new_record, name, yield_div_id){
            console.log(original_record_name + " " + new_record + " " + name + " " + yield_div_id)
            var record = eval(new_record+".meta.fields");
        
            for (i=0; i<record.length; i++){
              if (record[i].name === name){
                        if(record[i].isPrimitive()){
                          var newElement = "<div class='param_view'>"+original_record_name+"."+name+"<div>";
                          $("#"+yield_div_id).append(newElement);
                        }
                        else{
                            console.log(record[i].type.name);
                            createNewObject(record[i].type.name , yield_div_id);
                        }
                        
              }
               
            }

  }








});
