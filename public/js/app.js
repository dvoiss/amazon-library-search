$(document).ready(function() {
  // the event source
  var src;

  $("#searchBtn").click(function(event) {
    newSearch();

    src = new EventSource('/retrieve/ssj4_dave@hotmail.com/320');
    src.onmessage = function(event) {
      (!event.data) ? handleDataFinished() : handleData(event.data);
    }
    src.onerror = function(event) {
      handleDataFinished();
    }

    function handleDataFinished() {
      $('#statusContainer').hide();
      src.close();
    }
    
    function handleData(data) {
      if (data.indexOf('status: ') == 0)
        $('#status').html(data.slice(8, -1));
      else
        $('#list').append( data );
    }
  });

  function newSearch() {
    $('#list').empty();
    $('#form').hide();
    $('#statusContainer').show();
    $('#progressSpinner').show();
    $('#backBtn').show();
  }

  $("#backBtn").click(function(event) {
    src.close();
    $('#form').show();
    $('#statusContainer').hide();
    $('#progressSpinner').hide();
    $('#backBtn').hide();
  });
}); 