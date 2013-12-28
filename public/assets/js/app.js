$('document').ready(function(){
	var toolbar_height = $('#toolbar').height();
	$('#toolbar').hide();
	$(window).bind("mousemove",function (e) {
		var _x = e.pageX, _y = e.pageY;
		if(_y < toolbar_height * 2) {
			$('#toolbar').show();
		} else {
			$('#toolbar').hide();
		}
	});
})